package com.huellitas.alerta;

import com.huellitas.config.AuthContext;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Expone la campanita de notificaciones de un usuario: consultar sus
 * notificaciones (avisos del sistema, respuestas a reportes, cambios de
 * plan, etc.) y marcarlas como leídas.
 */
@RestController
@RequestMapping("/api/huellitas/notificaciones")
public class NotificacionController {

    private final JdbcTemplate jdbc;
    private final AuthContext authContext;

    public NotificacionController(JdbcTemplate jdbc, AuthContext authContext) {
        this.jdbc = jdbc;
        this.authContext = authContext;
    }

    /**
     * Obtiene las notificaciones del usuario autenticado.
     *
     * @param usuarioId identificador del usuario (ignorado; se usa el del token).
     * @return un JSON (como texto) con la lista de notificaciones; {@code "[]"} si no hay datos.
     */
    @GetMapping(produces = "application/json")
    public ResponseEntity<String> obtenerNotificaciones(@RequestParam(required = false) Long usuarioId) {
        String sql = "SELECT fn_listar_notificaciones(?)";
        String json = jdbc.queryForObject(sql, String.class, authContext.usuarioIdActual());
        return ResponseEntity.ok(json != null ? json : "[]");
    }

    /**
     * Marca todas las notificaciones del usuario autenticado como leídas.
     *
     * @param usuarioId identificador del usuario (ignorado; se usa el del token).
     * @return el resultado de la operación en formato JSON.
     */
    @PostMapping(value = "/leidas", produces = "application/json")
    public ResponseEntity<String> marcarLeidas(@RequestParam(required = false) Long usuarioId) {
        String sql = "SELECT fn_marcar_notificaciones_leidas(?)";
        String json = jdbc.queryForObject(sql, String.class, authContext.usuarioIdActual());
        return ResponseEntity.ok(json != null ? json : "{\"status\":\"OK\"}");
    }
}
