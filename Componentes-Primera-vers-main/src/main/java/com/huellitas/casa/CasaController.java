package com.huellitas.casa;
import com.huellitas.config.AuthContext;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * Expone los paneles de resumen de una vivienda: el dashboard general de la
 * casa (mascotas, dispositivos, alertas) y el panel de una zona específica
 * dentro de ella.
 */
@RestController
@RequestMapping("/api/huellitas/casa")
public class CasaController {
    private final CasaRepository repo;
    private final JdbcTemplate jdbcTemplate;
    private final AuthContext authContext;

    public CasaController(CasaRepository repo, JdbcTemplate jdbcTemplate, AuthContext authContext) {
        this.repo = repo;
        this.jdbcTemplate = jdbcTemplate;
        this.authContext = authContext;
    }

    private ResponseEntity<String> sinAcceso() {
        return ResponseEntity.status(403).body("{\"ok\":false,\"error\":\"No tienes acceso a esta vivienda\",\"message\":\"No tienes acceso a esta vivienda\"}");
    }

    /**
     * Obtiene el dashboard general de una vivienda.
     *
     * @param id identificador de la vivienda.
     * @return un JSON (como texto) con el resumen de la vivienda.
     */
    @GetMapping(value = "/{id}/dashboard", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> dashboardCasa(@PathVariable Long id) {
        if (!authContext.perteneceACasa(id)) return sinAcceso();
        return ResponseEntity.ok(repo.dashboardCasa(id));
    }

    /**
     * Variante de {@link #dashboardCasa(Long)} que recibe el identificador de la vivienda como parámetro de consulta.
     *
     * @param casaId identificador de la vivienda.
     * @return un JSON (como texto) con el resumen de la vivienda.
     */
    @GetMapping(value = "/dashboard", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> dashboardCasaParam(@RequestParam Long casaId) {
        if (!authContext.perteneceACasa(casaId)) return sinAcceso();
        return ResponseEntity.ok(repo.dashboardCasa(casaId));
    }

    /**
     * Obtiene el panel de resumen de una zona específica de la vivienda (por ejemplo, sus dispositivos y sensores).
     *
     * @param zonaId identificador de la zona.
     * @return un JSON (como texto) con el resumen de la zona.
     */
    @GetMapping(value = "/zona/{zonaId}/panel", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> panelZona(@PathVariable Long zonaId) {
        var filas = jdbcTemplate.queryForList("SELECT casa_id FROM zona WHERE id = ?", zonaId);
        if (filas.isEmpty()) {
            return ResponseEntity.status(404).body("{\"ok\":false,\"error\":\"Zona no encontrada\",\"message\":\"Zona no encontrada\"}");
        }
        Long casaId = ((Number) filas.get(0).get("casa_id")).longValue();
        if (!authContext.perteneceACasa(casaId)) return sinAcceso();
        return ResponseEntity.ok(repo.panelZona(zonaId));
    }

    /**
     * Estadísticas agregadas y públicas del sistema completo (hogares
     * conectados, dispositivos, mascotas cuidadas, % de actividad), para la
     * barra de la landing. No requiere autenticación: no expone datos de
     * ninguna vivienda en particular, solo conteos totales.
     *
     * @return un JSON (como texto) con las estadísticas.
     */
    @GetMapping(value = "/estadisticas-publicas", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> estadisticasPublicas() {
        return ResponseEntity.ok(repo.estadisticasPublicas());
    }

    /**
     * Devuelve el codigo de vinculacion de la vivienda (X-Device-Code que
     * manda el firmware). Solo el propietario o miembro de la casa puede verlo.
     *
     * @param casaId identificador de la vivienda.
     * @return el codigo UUID unico de la vivienda.
     */
    @GetMapping("/{casaId}/codigo-vinculacion")
    public ResponseEntity<?> codigoVinculacion(@PathVariable Long casaId) {
        if (!authContext.perteneceACasa(casaId)) return sinAcceso();
        var filas = jdbcTemplate.queryForList(
            "SELECT codigo_vinculacion FROM casa WHERE id = ? AND deleted_at IS NULL", casaId);
        if (filas.isEmpty()) {
            return ResponseEntity.status(404).body(Map.of("ok", false, "error", "Casa no encontrada"));
        }
        String codigo = (String) filas.get(0).get("codigo_vinculacion");
        return ResponseEntity.ok(Map.of("ok", true, "codigoVinculacion", codigo != null ? codigo : ""));
    }

    /**
     * Regenera el codigo de vinculacion de la vivienda por si se filtra.
     * Inmediatamente despues de esto, los ESP32 con el codigo viejo seran rechazados
     * hasta que se actualicen con el nuevo.
     *
     * @param casaId identificador de la vivienda.
     * @return el nuevo codigo UUID.
     */
    @PostMapping("/{casaId}/codigo-vinculacion/regenerar")
    public ResponseEntity<?> regenerarCodigoVinculacion(@PathVariable Long casaId) {
        if (!authContext.perteneceACasa(casaId)) return sinAcceso();
        String nuevoCodigo = java.util.UUID.randomUUID().toString();
        jdbcTemplate.update("UPDATE casa SET codigo_vinculacion = ? WHERE id = ?", nuevoCodigo, casaId);
        return ResponseEntity.ok(Map.of("ok", true, "codigoVinculacion", nuevoCodigo));
    }
}
