package com.huellitas.camara;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.huellitas.ia.ContenidoMascotaService;
import com.huellitas.momento.GifBuilder;
import com.huellitas.storage.S3Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Endpoint para que la ESP32-CAM mande fotos al servidor.
 *
 * Cuando el backend esta en internet, la camara ya no puede recibir peticiones
 * de captura (/capture) porque la IP local no es alcanzable. La solucion es
 * invertir el flujo: la camara manda la foto (POST /api/huellitas/camara/momento)
 * y el servidor la clasifica, igual que lo hace MomentoMascotaJob cuando si puede
 * alcanzar la camara.
 *
 * Autenticacion: X-Device-Code (codigo de vivienda) validado por DeviceTokenFilter.
 */
@RestController
@RequestMapping("/api/huellitas/camara")
public class CamaraMomentoController {

    private static final Logger log = LoggerFactory.getLogger(CamaraMomentoController.class);
    private static final Set<String> ACTIVIDADES_CON_RAFAGA = Set.of("COMIENDO", "BEBIENDO");
    private static final int MINUTOS_EXPIRACION = 3;

    private final JdbcTemplate jdbc;
    private final ContenidoMascotaService clasificador;
    private final S3Service s3Service;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Value("${momento.mascota.umbral-confianza:0.55}")
    private double umbralConfianza;

    public CamaraMomentoController(JdbcTemplate jdbc,
                                   ContenidoMascotaService clasificador,
                                   S3Service s3Service) {
        this.jdbc = jdbc;
        this.clasificador = clasificador;
        this.s3Service = s3Service;
    }

    /**
     * La ESP32-CAM sube una foto. El servidor la clasifica y, si hay mascota
     * activa, genera el momento y la notificacion igual que MomentoMascotaJob.
     *
     * Headers requeridos:
     *   X-Device-Code: codigo de vivienda (validado por DeviceTokenFilter)
     *   X-Device-Mac:  MAC de la placa (para identificar la camara en BD)
     */
    @PostMapping(value = "/momento", consumes = "multipart/form-data")
    public ResponseEntity<?> recibirFoto(
            @RequestHeader(value = "X-Device-Code", required = false) String deviceCode,
            @RequestHeader(value = "X-Device-Mac", required = false) String mac,
            @RequestParam("fotos") List<MultipartFile> fotos) {

        if (fotos == null || fotos.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("ok", false, "error", "Se requiere al menos una foto"));
        }

        // Buscar la camara por MAC de la placa en dispositivo_presencia -> dispositivo -> camara
        Map<String, Object> info = null;
        if (mac != null && !mac.isBlank()) {
            try {
                List<Map<String, Object>> rows = jdbc.queryForList(
                    "SELECT c.id AS camara_id, c.casa_id, c.perro_id, p.nombre AS perro_nombre, " +
                    "       casa.propietario_id " +
                    "FROM camara c " +
                    "JOIN dispositivo d ON d.id = c.dispositivo_id AND d.deleted_at IS NULL " +
                    "JOIN dispositivo_presencia pr ON pr.mac_address = d.mac_address " +
                    "JOIN casa ON casa.id = c.casa_id " +
                    "LEFT JOIN perro p ON p.id = c.perro_id AND p.deleted_at IS NULL " +
                    "WHERE pr.mac_address = ? AND c.activo = true " +
                    "LIMIT 1", mac);
                if (!rows.isEmpty()) info = rows.get(0);
            } catch (Exception e) {
                log.warn("[CAMARA MOMENTO] Error buscando camara por MAC {}: {}", mac, e.getMessage());
            }
        }

        // Si no se encontro la camara, intentar por codigo de vivienda (primera camara activa)
        if (info == null && deviceCode != null && !deviceCode.isBlank()) {
            try {
                List<Map<String, Object>> rows = jdbc.queryForList(
                    "SELECT c.id AS camara_id, c.casa_id, c.perro_id, p.nombre AS perro_nombre, " +
                    "       casa.propietario_id " +
                    "FROM camara c " +
                    "JOIN casa ON casa.id = c.casa_id " +
                    "LEFT JOIN perro p ON p.id = c.perro_id AND p.deleted_at IS NULL " +
                    "WHERE casa.codigo_vinculacion = ? AND c.activo = true " +
                    "ORDER BY c.id LIMIT 1", deviceCode);
                if (!rows.isEmpty()) info = rows.get(0);
            } catch (Exception e) {
                log.warn("[CAMARA MOMENTO] Error buscando camara por codigo_vinculacion: {}", e.getMessage());
            }
        }

        int recibidas = fotos.size();

        // Si no hay camara registrada, igual procesamos la foto (logs para debug)
        if (info == null) {
            log.warn("[CAMARA MOMENTO] Foto recibida pero no se encontro camara. MAC={} Code={}", mac, deviceCode);
            return ResponseEntity.ok(Map.of("ok", true, "recibidas", recibidas, "hayMascota", false,
                    "mensaje", "Foto recibida; camara no registrada aun"));
        }

        Long camaraId = ((Number) info.get("camara_id")).longValue();
        Long casaId = ((Number) info.get("casa_id")).longValue();
        Long perroId = info.get("perro_id") != null ? ((Number) info.get("perro_id")).longValue() : null;
        String perroNombre = (String) info.get("perro_nombre");
        Long propietarioId = info.get("propietario_id") != null ? ((Number) info.get("propietario_id")).longValue() : null;

        // Clasificar la primera foto
        byte[] primerFrame;
        try {
            primerFrame = fotos.get(0).getBytes();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("ok", false, "error", "No se pudo leer la foto"));
        }

        ContenidoMascotaService.VeredictoActividad veredicto;
        try {
            veredicto = clasificador.clasificarActividad(primerFrame);
        } catch (Exception e) {
            log.warn("[CAMARA MOMENTO] Error clasificando: {}", e.getMessage());
            return ResponseEntity.ok(Map.of("ok", true, "recibidas", recibidas, "hayMascota", false));
        }

        if (veredicto == null || veredicto.actividad() == null ||
            veredicto.confianza() < umbralConfianza ||
            veredicto.actividad().equals("NINGUNA") ||
            veredicto.actividad().equals("NINGUNA_CLARA")) {
            log.debug("[CAMARA MOMENTO] Sin mascota detectada. camara={}", camaraId);
            return ResponseEntity.ok(Map.of("ok", true, "recibidas", recibidas, "hayMascota", false,
                    "actividad", veredicto != null ? veredicto.actividad() : "NINGUNA"));
        }

        // Hay mascota — recopilar todos los frames recibidos
        List<byte[]> frames = new ArrayList<>();
        frames.add(primerFrame);
        for (int i = 1; i < fotos.size(); i++) {
            try { frames.add(fotos.get(i).getBytes()); } catch (Exception ignored) {}
        }

        // Subir GIF (rafaga) o JPEG (un solo frame)
        List<String> claves = new ArrayList<>();
        boolean conRafaga = ACTIVIDADES_CON_RAFAGA.contains(veredicto.actividad()) && frames.size() > 1;
        if (conRafaga) {
            byte[] gif = GifBuilder.construir(frames, 100);
            if (gif != null) {
                try { claves.add(s3Service.uploadBytes(gif, "image/gif", ".gif")); }
                catch (Exception e) { log.warn("[CAMARA MOMENTO] Error subiendo GIF: {}", e.getMessage()); }
            }
        }
        if (claves.isEmpty()) {
            try { claves.add(s3Service.uploadBytes(frames.get(0), "image/jpeg", ".jpg")); }
            catch (Exception e) { log.warn("[CAMARA MOMENTO] Error subiendo JPEG: {}", e.getMessage()); }
        }

        if (!claves.isEmpty()) {
            try {
                String clavesJson = objectMapper.writeValueAsString(claves);
                jdbc.update(
                    "INSERT INTO momento_mascota (casa_id, camara_id, perro_id, actividad, confianza, " +
                    "claves_fragmento, expira_at) " +
                    "VALUES (?, ?, ?, ?::actividad_mascota, ?, ?::jsonb, now() + make_interval(mins => ?))",
                    casaId, camaraId, perroId, veredicto.actividad(), veredicto.confianza(),
                    clavesJson, (double) MINUTOS_EXPIRACION);
            } catch (Exception e) {
                log.error("[CAMARA MOMENTO] Error guardando momento: {}", e.getMessage());
            }
        }

        // Notificacion al propietario
        if (propietarioId != null) {
            String nombre = perroNombre != null ? perroNombre : "tu mascota";
            String actividad = veredicto.actividad().toLowerCase().replace("_", " ");
            String msg = nombre + " esta " + actividad;
            try {
                jdbc.update(
                    "INSERT INTO notificacion (usuario_id, canal, contenido, estado, tipo, enviado_at) " +
                    "VALUES (?, 'WEBSOCKET'::canal_notificacion, ?, 'PENDIENTE'::estado_notificacion, " +
                    "'MOMENTO_MASCOTA', now())", propietarioId, msg);
            } catch (Exception e) {
                log.warn("[CAMARA MOMENTO] Error insertando notificacion: {}", e.getMessage());
            }
        }

        // Actualizar ultima_captura de la camara
        try {
            jdbc.update("UPDATE camara SET ultima_captura = now() WHERE id = ?", camaraId);
        } catch (Exception ignored) {}

        log.info("[CAMARA MOMENTO] camara={} actividad={} confianza={} frames={}",
            camaraId, veredicto.actividad(), veredicto.confianza(), frames.size());

        return ResponseEntity.ok(Map.of(
            "ok", true,
            "recibidas", recibidas,
            "hayMascota", true,
            "actividad", veredicto.actividad(),
            "confianza", veredicto.confianza()
        ));
    }

    /** Endpoint de prueba para verificar conectividad sin subir foto. */
    @GetMapping("/momento/ping")
    public ResponseEntity<?> ping(
            @RequestHeader(value = "X-Device-Code", required = false) String code) {
        return ResponseEntity.ok(Map.of("ok", true, "mensaje", "Servidor alcanzable",
            "codigoRecibido", code != null));
    }
}
