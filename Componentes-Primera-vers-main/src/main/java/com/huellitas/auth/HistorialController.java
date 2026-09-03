package com.huellitas.auth;

import com.huellitas.config.AuthContext;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Expone el historial de actividad de un usuario dentro del sistema
 * (acciones sobre dispositivos, mascotas, etc.), delegando el cálculo a una
 * función almacenada en la base de datos.
 */
@RestController
@RequestMapping("/api/huellitas/historial")
public class HistorialController {

    private final JdbcTemplate jdbc;
    private final AuthContext authContext;

    public HistorialController(JdbcTemplate jdbc, AuthContext authContext) {
        this.jdbc = jdbc;
        this.authContext = authContext;
    }

    /**
     * Obtiene el historial de actividad del usuario autenticado.
     *
     * @param usuarioId identificador del usuario (ignorado; se usa el del token).
     * @return un JSON (como texto) con la lista de eventos del historial; {@code "[]"} si no hay datos.
     */
    @GetMapping(produces = "application/json")
    public ResponseEntity<String> obtenerHistorialUsuario(@RequestParam(required = false) Long usuarioId) {
        String sql = "SELECT fn_historial_usuario(?)";
        String json = jdbc.queryForObject(sql, String.class, authContext.usuarioIdActual());
        return ResponseEntity.ok(json != null ? json : "[]");
    }

    /**
     * Obtiene el historial de actividad de todos los miembros de la casa
     * del usuario autenticado. Solo accesible para quien es el propietario
     * real de esa casa (columna {@code casa.propietario_id}), no basta con
     * tener el rol PROPIETARIO en el token.
     *
     * @return un JSON (como texto) con los eventos de todo el hogar, o 403 si no eres el propietario.
     */
    @GetMapping(value = "/casa", produces = "application/json")
    public ResponseEntity<String> obtenerHistorialCasa() {
        Long casaId = authContext.casaIdActual();

        // Una cuenta en espera —por ejemplo, un miembro dado de baja que
        // todavía no creó su vivienda— no tiene casa que consultar.
        if (casaId == null) {
            return ResponseEntity.status(403).body("{\"ok\":false,\"error\":\"Tu cuenta no tiene una vivienda asociada\"}");
        }

        var duenos = jdbc.queryForList("SELECT propietario_id FROM casa WHERE id = ?", casaId);
        Long propietarioId = duenos.isEmpty() || duenos.get(0).get("propietario_id") == null
            ? null
            : ((Number) duenos.get(0).get("propietario_id")).longValue();
        if (propietarioId == null || !propietarioId.equals(authContext.usuarioIdActual())) {
            return ResponseEntity.status(403).body("{\"ok\":false,\"error\":\"Solo el propietario de la casa puede ver esta actividad\"}");
        }
        String json = jdbc.queryForObject("SELECT fn_historial_casa(?)", String.class, casaId);
        return ResponseEntity.ok(json != null ? json : "[]");
    }
}
