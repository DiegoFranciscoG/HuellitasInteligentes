package com.huellitas.momento;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.huellitas.config.AuthContext;
import com.huellitas.storage.S3Service;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * "Momentos de tu mascota": lo que detectó una cámara IoT, con la cuenta
 * regresiva de 3 minutos para guardarlo antes de que el fragmento se borre
 * solo, y la galería de lo que ya se guardó.
 */
@RestController
@RequestMapping("/api/huellitas/momentos")
public class MomentoMascotaController {

    private static final int MINUTOS_URL_FIRMADA = 5;

    private final JdbcTemplate jdbc;
    private final AuthContext authContext;
    private final S3Service s3Service;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public MomentoMascotaController(JdbcTemplate jdbc, AuthContext authContext, S3Service s3Service) {
        this.jdbc = jdbc;
        this.authContext = authContext;
        this.s3Service = s3Service;
    }

    private static final String SELECT_BASE =
        "SELECT m.id, m.actividad::text AS actividad, m.confianza, m.claves_fragmento::text AS claves_json, " +
        "       m.capturado_at, m.expira_at, m.guardado, m.perro_id, " +
        "       p.nombre AS perro_nombre, p.foto_url AS perro_foto_url, c.nombre AS camara_nombre, " +
        "       GREATEST(0, EXTRACT(EPOCH FROM (m.expira_at - now()))::int) AS segundos_restantes " +
        "FROM momento_mascota m " +
        "JOIN camara c ON c.id = m.camara_id " +
        "LEFT JOIN perro p ON p.id = m.perro_id AND p.deleted_at IS NULL ";

    /**
     * Momentos todavía pendientes de decisión: no guardados y sin vencer.
     * Es lo que alimenta la tarjeta de cuenta regresiva.
     *
     * @return los momentos activos de la vivienda del usuario, más recientes primero.
     */
    @GetMapping("/activo")
    public ResponseEntity<?> activos() {
        Long casaId = authContext.casaIdActual();
        if (casaId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "Necesitas una vivienda para ver esto"));
        }
        List<Map<String, Object>> filas = jdbc.queryForList(
            SELECT_BASE + "WHERE m.casa_id = ? AND m.guardado = false AND m.expira_at > now() " +
            "ORDER BY m.capturado_at DESC LIMIT 5", casaId);
        return ResponseEntity.ok(Map.of("ok", true, "momentos", filas.stream().map(this::conUrls).toList()));
    }

    /**
     * Galería de momentos ya guardados por el usuario.
     *
     * @return hasta 50 momentos guardados de la vivienda, más recientes primero.
     */
    @GetMapping
    public ResponseEntity<?> historial() {
        Long casaId = authContext.casaIdActual();
        if (casaId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "Necesitas una vivienda para ver esto"));
        }
        List<Map<String, Object>> filas = jdbc.queryForList(
            SELECT_BASE + "WHERE m.casa_id = ? AND m.guardado = true " +
            "ORDER BY m.capturado_at DESC LIMIT 50", casaId);
        return ResponseEntity.ok(Map.of("ok", true, "momentos", filas.stream().map(this::conUrls).toList()));
    }

    /**
     * Guarda un momento antes de que expire, para que su fragmento deje de
     * borrarse automáticamente.
     *
     * @param id identificador del momento.
     * @return 404 si no existe o no es de tu vivienda; 410 si ya venció sin guardarse.
     */
    @PostMapping("/{id}/guardar")
    public ResponseEntity<?> guardar(@PathVariable Long id) {
        Long casaId = authContext.casaIdActual();
        if (casaId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "Necesitas una vivienda para guardar esto"));
        }
        List<Map<String, Object>> filas = jdbc.queryForList(
            "SELECT guardado, expira_at < now() AS vencido FROM momento_mascota WHERE id = ? AND casa_id = ?",
            id, casaId);
        if (filas.isEmpty()) {
            return ResponseEntity.status(404).body(Map.of("ok", false, "error", "Momento no encontrado"));
        }
        boolean yaGuardado = Boolean.TRUE.equals(filas.get(0).get("guardado"));
        boolean vencido = Boolean.TRUE.equals(filas.get(0).get("vencido"));
        if (!yaGuardado && vencido) {
            return ResponseEntity.status(410).body(Map.of("ok", false, "error", "Este momento ya expiró"));
        }
        jdbc.update("UPDATE momento_mascota SET guardado = true WHERE id = ?", id);
        return ResponseEntity.ok(Map.of("ok", true));
    }

    /** Añade `urlsFragmento` (firmadas al vuelo) y `segundosRestantes` ya presente a la fila cruda. */
    private Map<String, Object> conUrls(Map<String, Object> fila) {
        Map<String, Object> resultado = new LinkedHashMap<>(fila);
        String clavesJson = (String) resultado.remove("claves_json");
        List<String> urls = List.of();
        try {
            List<String> claves = objectMapper.readValue(clavesJson,
                objectMapper.getTypeFactory().constructCollectionType(List.class, String.class));
            urls = claves.stream().map(k -> s3Service.generatePresignedUrlMinutos(k, MINUTOS_URL_FIRMADA)).toList();
        } catch (Exception ignored) {
            // Sin claves legibles: se devuelve la lista vacía en vez de romper toda la respuesta.
        }
        resultado.put("urlsFragmento", urls);
        return resultado;
    }
}
