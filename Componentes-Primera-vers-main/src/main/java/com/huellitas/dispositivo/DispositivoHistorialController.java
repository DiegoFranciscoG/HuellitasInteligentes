package com.huellitas.dispositivo;

import com.huellitas.config.AuthContext;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;
import java.time.OffsetDateTime;
import java.util.List;

/**
 * Expone el historial de lecturas de sensores y de comandos ejecutados sobre
 * los actuadores de un dispositivo IoT, para graficar tendencias y auditar acciones pasadas.
 */
@RestController
@RequestMapping("/api/huellitas/dispositivo")
public class DispositivoHistorialController {

    private final JdbcTemplate jdbc;
    private final AuthContext authContext;

    public DispositivoHistorialController(JdbcTemplate jdbc, AuthContext authContext) {
        this.jdbc = jdbc;
        this.authContext = authContext;
    }

    /** @return {@code true} si el dispositivo pertenece a la casa del usuario autenticado. */
    private boolean tieneAccesoADispositivo(Long dispositivoId) {
        var filas = jdbc.queryForList(
            "SELECT z.casa_id FROM dispositivo d JOIN zona z ON d.zona_id = z.id WHERE d.id = ?", dispositivoId);
        if (filas.isEmpty()) return false;
        Long casaId = ((Number) filas.get(0).get("casa_id")).longValue();
        return authContext.perteneceACasa(casaId);
    }

    private ResponseEntity<String> sinAcceso() {
        return ResponseEntity.status(403).body("{\"ok\":false,\"error\":\"No tienes acceso a este dispositivo\",\"message\":\"No tienes acceso a este dispositivo\"}");
    }

    /**
     * Lista los dispositivos IoT registrados en las zonas de la casa del
     * usuario autenticado (tabla {@code dispositivo}, vía su zona).
     *
     * @return un JSON (como texto) con los dispositivos de la casa; {@code "[]"} si no tiene ninguno registrado.
     */
    @GetMapping(value = "/casa", produces = "application/json")
    public ResponseEntity<List<java.util.Map<String, Object>>> listarDispositivosCasa() {
        Long casaId = authContext.casaIdActual();
        var filas = jdbc.queryForList(
            "SELECT d.id, d.zona_id, d.mac_address, d.tipo, d.categoria, d.modelo, d.estado, d.ultima_conexion " +
            "FROM dispositivo d JOIN zona z ON d.zona_id = z.id " +
            "WHERE z.casa_id = ? AND d.deleted_at IS NULL ORDER BY d.id", casaId);
        return ResponseEntity.ok(filas);
    }

    /**
     * Obtiene el historial de lecturas de un sensor dentro de un rango de fechas.
     *
     * @param dispositivoId identificador del dispositivo sensor.
     * @param desde inicio del rango de fechas (ISO-8601); por defecto, 30 días antes de {@code hasta}.
     * @param hasta fin del rango de fechas (ISO-8601); por defecto, el momento actual.
     * @param limite cantidad máxima de lecturas a devolver (1 a 500).
     * @return un JSON (como texto) con las lecturas encontradas, o 400 si el rango de fechas es inválido.
     */
    @GetMapping(value = "/{dispositivoId}/historial", produces = "application/json")
    public ResponseEntity<String> obtenerHistorialSensor(
            @PathVariable Long dispositivoId,
            @RequestParam(required = false) String desde,
            @RequestParam(required = false) String hasta,
            @RequestParam(defaultValue = "100") Integer limite) {
        if (!tieneAccesoADispositivo(dispositivoId)) return sinAcceso();
        int limiteSeguro = Math.max(1, Math.min(limite, 500));
        OffsetDateTime dHasta;
        OffsetDateTime dDesde;
        try {
            dHasta = hasta != null ? OffsetDateTime.parse(hasta) : OffsetDateTime.now();
            dDesde = desde != null ? OffsetDateTime.parse(desde) : dHasta.minusDays(30);
        } catch (java.time.format.DateTimeParseException e) {
            return ResponseEntity.status(400).body("{\"ok\":false,\"error\":\"Fecha inválida\",\"message\":\"Fecha inválida\"}");
        }
        if (dDesde.isAfter(dHasta)) {
            return ResponseEntity.status(400).body("{\"ok\":false,\"error\":\"El rango de fechas es inválido\",\"message\":\"El rango de fechas es inválido\"}");
        }

        String sql = "SELECT fn_historial_sensor(?, ?::timestamptz, ?::timestamptz, ?, 0)";
        String json = jdbc.queryForObject(sql, String.class, dispositivoId, dDesde, dHasta, limiteSeguro);
        return ResponseEntity.ok(json != null ? json : "[]");
    }

    /**
     * Obtiene el historial de comandos ejecutados sobre un dispositivo actuador.
     *
     * @param dispositivoId identificador del dispositivo actuador.
     * @param limite cantidad máxima de comandos a devolver (1 a 500).
     * @return un JSON (como texto) con los comandos encontrados.
     */
    @GetMapping(value = "/{dispositivoId}/actuadores", produces = "application/json")
    public ResponseEntity<String> obtenerHistorialActuadores(
            @PathVariable Long dispositivoId,
            @RequestParam(defaultValue = "50") Integer limite) {
        if (!tieneAccesoADispositivo(dispositivoId)) return sinAcceso();
        int limiteSeguro = Math.max(1, Math.min(limite, 500));
        String sql = "SELECT fn_historial_actuador(?, ?)";
        String json = jdbc.queryForObject(sql, String.class, dispositivoId, limiteSeguro);
        return ResponseEntity.ok(json != null ? json : "[]");
    }
}
