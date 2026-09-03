package com.huellitas.alerta;
import com.huellitas.config.AuthContext;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

/**
 * Permite consultar y gestionar las alertas generadas por el sistema para
 * una vivienda (por ejemplo, condiciones ambientales o de comportamiento
 * fuera de lo normal detectadas en una mascota).
 */
@RestController
@RequestMapping("/api/huellitas/alerta")
public class AlertaController {
    private final AlertaRepository repo;
    private final JdbcTemplate jdbcTemplate;
    private final AuthContext authContext;

    public AlertaController(AlertaRepository repo, JdbcTemplate jdbcTemplate, AuthContext authContext) {
        this.repo = repo;
        this.jdbcTemplate = jdbcTemplate;
        this.authContext = authContext;
    }

    private ResponseEntity<String> sinAcceso() {
        return ResponseEntity.status(403).body("{\"ok\":false,\"error\":\"No tienes acceso a esta alerta\",\"message\":\"No tienes acceso a esta alerta\"}");
    }

    /**
     * Busca las alertas de una vivienda, con filtros opcionales por
     * severidad y estado de lectura, y paginación.
     *
     * @param casaId identificador de la vivienda.
     * @param severidad severidad a filtrar (opcional).
     * @param soloNoLeidas si es {@code true} (por defecto), solo devuelve alertas no leídas.
     * @param limite cantidad máxima de resultados.
     * @param offset cantidad de resultados a saltar (paginación).
     * @return un JSON (como texto) con la lista de alertas encontradas.
     */
    @GetMapping(produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> buscarAlertas(@RequestParam Long casaId, @RequestParam(required = false) String severidad, @RequestParam(defaultValue = "true") Boolean soloNoLeidas, @RequestParam(defaultValue = "50") Integer limite, @RequestParam(defaultValue = "0") Integer offset) {
        if (!authContext.perteneceACasa(casaId)) return sinAcceso();
        if (severidad != null) {
            try {
                SeveridadAlerta.valueOf(severidad);
            } catch (IllegalArgumentException e) {
                return ResponseEntity.status(400).body("{\"ok\":false,\"error\":\"Severidad inválida\",\"message\":\"Severidad inválida\"}");
            }
        }
        int limiteSeguro = Math.max(1, Math.min(limite, 200));
        return ResponseEntity.ok(repo.buscarAlertas(casaId, severidad, soloNoLeidas, limiteSeguro, Math.max(0, offset)));
    }

    /**
     * Marca una alerta como leída.
     *
     * @param id identificador de la alerta.
     * @return una respuesta vacía con estado 200 al completar la operación.
     */
    @PostMapping(value = "/{id}/marcar-leida")
    public ResponseEntity<?> marcarAlertaLeida(@PathVariable Long id) {
        var filas = jdbcTemplate.queryForList("SELECT casa_id FROM alerta WHERE id = ?", id);
        if (filas.isEmpty()) return ResponseEntity.status(404).build();
        Long casaId = ((Number) filas.get(0).get("casa_id")).longValue();
        if (!authContext.perteneceACasa(casaId)) return sinAcceso();
        repo.marcarAlertaLeida(id);
        return ResponseEntity.ok().build();
    }
}
