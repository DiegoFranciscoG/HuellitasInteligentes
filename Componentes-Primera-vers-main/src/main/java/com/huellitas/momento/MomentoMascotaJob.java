package com.huellitas.momento;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.huellitas.ia.ContenidoMascotaService;
import com.huellitas.storage.S3Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * "Momentos de tu mascota": cada cierto tiempo pide un fotograma a cada
 * cámara IoT vinculada (ESP32-CAM vía {@code /capture} — nunca el celular por
 * WebRTC, cuyo video es punto a punto y el servidor no lo ve), lo clasifica
 * con {@link ContenidoMascotaService#clasificarActividad(byte[])} y, si hay
 * una mascota, avisa por el mismo canal de {@code notificacion} que ya usan
 * los avisos de IoT. Si la actividad es comer o beber, además sube una ráfaga
 * de fotos que el dueño tiene 3 minutos para guardar antes de que se borren solas.
 *
 * <p>El enfriamiento por cámara vive en {@code camara.ultima_captura}, la
 * misma columna que V43 dejó preparada para esto: mientras no pase
 * {@link #cooldownSegundos}, esa cámara se salta el ciclo siguiente.</p>
 */
@Component
public class MomentoMascotaJob {

    private static final Logger log = LoggerFactory.getLogger(MomentoMascotaJob.class);
    private static final Set<String> ACTIVIDADES_CON_RAFAGA = Set.of("COMIENDO", "BEBIENDO");
    private static final int FRAMES_RAFAGA = 5;
    private static final int MINUTOS_EXPIRACION = 3;

    private final JdbcTemplate jdbc;
    private final ContenidoMascotaService clasificador;
    private final S3Service s3Service;
    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Value("${iot.presencia.ventana-segundos:30}")
    private int ventanaSegundos;

    @Value("${momento.mascota.cooldown-segundos:90}")
    private int cooldownSegundos;

    @Value("${momento.mascota.umbral-confianza:0.55}")
    private double umbralConfianza;

    public MomentoMascotaJob(JdbcTemplate jdbc, ContenidoMascotaService clasificador, S3Service s3Service) {
        this.jdbc = jdbc;
        this.clasificador = clasificador;
        this.s3Service = s3Service;

        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(3000);
        factory.setReadTimeout(4000);
        this.restTemplate = new RestTemplate(factory);
    }

    @Scheduled(fixedRate = 30_000)
    public void detectar() {
        List<Map<String, Object>> camaras;
        try {
            camaras = jdbc.queryForList(
                "SELECT c.id AS camara_id, c.casa_id, c.perro_id, p.nombre AS perro_nombre, " +
                "       pr.ip_local, casa.propietario_id " +
                "FROM camara c " +
                "JOIN dispositivo d ON d.id = c.dispositivo_id AND d.deleted_at IS NULL " +
                "JOIN dispositivo_presencia pr ON pr.mac_address = d.mac_address " +
                "JOIN casa ON casa.id = c.casa_id " +
                "LEFT JOIN perro p ON p.id = c.perro_id AND p.deleted_at IS NULL " +
                "WHERE c.activo = true " +
                "  AND pr.ultimo_latido > now() - make_interval(secs => ?) " +
                "  AND (c.ultima_captura IS NULL OR c.ultima_captura < now() - make_interval(secs => ?))",
                (double) ventanaSegundos, (double) cooldownSegundos);
        } catch (Exception e) {
            log.error("[MOMENTOS MASCOTA] Error listando cámaras elegibles", e);
            return;
        }

        for (Map<String, Object> camara : camaras) {
            try {
                procesarCamara(camara);
            } catch (Exception e) {
                log.error("[MOMENTOS MASCOTA] Error procesando cámara {}: {}", camara.get("camara_id"), e.getMessage());
            }
        }
    }

    private void procesarCamara(Map<String, Object> camara) {
        Long camaraId = ((Number) camara.get("camara_id")).longValue();
        String ip = (String) camara.get("ip_local");
        if (ip == null || ip.isBlank()) return;

        String urlCaptura = "http://" + ip + "/capture";
        byte[] primerFrame = capturar(urlCaptura);

        // Se marca el intento aunque falle la captura, para no reintentar en
        // el próximo tick de 30s contra una cámara que ahora mismo no responde.
        jdbc.update("UPDATE camara SET url_captura = ?, ultima_captura = now() WHERE id = ?", urlCaptura, camaraId);
        if (primerFrame == null) return;

        ContenidoMascotaService.VeredictoActividad veredicto = clasificador.clasificarActividad(primerFrame);
        if (!veredicto.hayMascota()) return;

        Long casaId = ((Number) camara.get("casa_id")).longValue();
        Long propietarioId = ((Number) camara.get("propietario_id")).longValue();
        Long perroId = camara.get("perro_id") != null ? ((Number) camara.get("perro_id")).longValue() : null;
        String perroNombre = (String) camara.get("perro_nombre");
        String nombreMostrado = (perroNombre != null && !perroNombre.isBlank()) ? perroNombre : "tu mascota";

        List<byte[]> frames = new ArrayList<>();
        frames.add(primerFrame);
        boolean conRafaga = ACTIVIDADES_CON_RAFAGA.contains(veredicto.actividad());
        if (conRafaga) {
            for (int i = 1; i < FRAMES_RAFAGA; i++) {
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    break;
                }
                byte[] siguiente = capturar(urlCaptura);
                if (siguiente != null) frames.add(siguiente);
            }
        }

        List<String> claves = new ArrayList<>();
        if (conRafaga && frames.size() > 1) {
            // Ráfaga de actividad (COMIENDO/BEBIENDO): armar GIF animado en memoria
            // y subir un solo objeto. Usa solo javax.imageio del JDK — sin ffmpeg.
            byte[] gif = GifBuilder.construir(frames, 100); // 100 ms entre frames
            if (gif != null) {
                try {
                    claves.add(s3Service.uploadBytes(gif, "image/gif", ".gif"));
                } catch (Exception e) {
                    log.warn("[MOMENTOS MASCOTA] No se pudo subir el GIF: {}", e.getMessage());
                }
            }
            // Si el GIF falla, subir al menos el primer frame como JPEG de respaldo.
            if (claves.isEmpty()) {
                try {
                    claves.add(s3Service.uploadBytes(frames.get(0), "image/jpeg", ".jpg"));
                } catch (Exception e) {
                    log.warn("[MOMENTOS MASCOTA] No se pudo subir el fotograma de respaldo: {}", e.getMessage());
                }
            }
        } else {
            // Sin ráfaga (un solo frame): subir el JPEG directamente.
            try {
                claves.add(s3Service.uploadBytes(frames.get(0), "image/jpeg", ".jpg"));
            } catch (Exception e) {
                log.warn("[MOMENTOS MASCOTA] No se pudo subir el fotograma: {}", e.getMessage());
            }
        }
        if (claves.isEmpty()) return;

        String clavesJson;
        try {
            clavesJson = objectMapper.writeValueAsString(claves);
        } catch (Exception e) {
            log.error("[MOMENTOS MASCOTA] Error serializando claves de fragmento", e);
            return;
        }

        jdbc.update(
            "INSERT INTO momento_mascota (casa_id, camara_id, perro_id, actividad, confianza, claves_fragmento, expira_at) " +
            "VALUES (?, ?, ?, ?::actividad_mascota, ?, ?::jsonb, now() + make_interval(mins => ?))",
            casaId, camaraId, perroId, veredicto.actividad(), veredicto.confianza(), clavesJson, (double) MINUTOS_EXPIRACION);

        String mensaje = mensajePara(nombreMostrado, veredicto);
        jdbc.update(
            "INSERT INTO notificacion (usuario_id, canal, contenido, estado, tipo, enviado_at) " +
            "VALUES (?, 'WEBSOCKET'::canal_notificacion, ?, 'PENDIENTE'::estado_notificacion, 'MOMENTO_MASCOTA', now())",
            propietarioId, mensaje);

        log.info("[MOMENTOS MASCOTA] Cámara {} · actividad={} confianza={} fragmento={} objeto(s)",
            camaraId, veredicto.actividad(), veredicto.confianza(), claves.size());
    }

    private String mensajePara(String nombre, ContenidoMascotaService.VeredictoActividad veredicto) {
        if (veredicto.confianza() < umbralConfianza || "NINGUNA_CLARA".equals(veredicto.actividad())) {
            return "🐾 Detectamos a " + nombre + " frente a la cámara, pero no distinguimos bien qué está haciendo.";
        }
        String accion = switch (veredicto.actividad()) {
            case "COMIENDO" -> "está comiendo";
            case "BEBIENDO" -> "está bebiendo agua";
            case "DURMIENDO" -> "está durmiendo";
            case "JUGANDO" -> "está jugando";
            default -> "está frente a la cámara";
        };
        boolean guardable = ACTIVIDADES_CON_RAFAGA.contains(veredicto.actividad());
        return "🐾 " + nombre + " " + accion + " ahora mismo."
            + (guardable ? " Tienes 3 minutos para verlo y guardarlo en Momentos." : " Revísalo en Momentos.");
    }

    private byte[] capturar(String url) {
        try {
            return restTemplate.getForObject(java.net.URI.create(url), byte[].class);
        } catch (Exception e) {
            log.warn("[MOMENTOS MASCOTA] No se pudo capturar de {}: {}", url, e.getMessage());
            return null;
        }
    }
}
