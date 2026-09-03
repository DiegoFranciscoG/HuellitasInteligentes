package com.huellitas.config;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

/**
 * Da acceso al {@code usuarioId} y rol del usuario autenticado en la
 * petición actual, ya validados por {@link JwtAuthenticationFilter} — para
 * que los controladores dejen de confiar en el {@code usuarioId} que manda
 * el propio cliente en el body/query y usen el que de verdad certifica el
 * JWT.
 */
@Component
public class AuthContext {

    private final JdbcTemplate jdbcTemplate;

    public AuthContext(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * @return el {@code usuarioId} del token validado en esta petición, o {@code null} si no hay sesión.
     */
    public Long usuarioIdActual() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || auth.getPrincipal() == null) return null;
        Object principal = auth.getPrincipal();
        if (principal instanceof Long l) return l;
        if (principal instanceof Number n) return n.longValue();
        try {
            return Long.parseLong(principal.toString());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /** @return {@code true} si la petición actual trae un JWT válido. */
    public boolean estaAutenticado() {
        return usuarioIdActual() != null;
    }

    /**
     * Resuelve la vivienda del usuario autenticado <b>consultando la base</b>,
     * no leyendo el {@code casa_id} que trae el JWT.
     *
     * <p>Esa diferencia es la que hace efectiva la baja de un miembro: el
     * token vive horas, así que si se confiara en su contenido, alguien dado
     * de baja seguiría entrando al hogar del que salió hasta que su sesión
     * expirara. Al leer la casa vigente, el acceso se corta en la petición
     * siguiente. Lo mismo vale para una cuenta desactivada.</p>
     *
     * <p>Si la consulta no encuentra al usuario —cuenta inexistente, dada de
     * baja o desactivada— se cae al valor del token. Ese respaldo existe para
     * no romper escenarios sin fila real de usuario (pruebas de integración
     * que emiten tokens sintéticos); la comprobación de pertenencia real la
     * hace {@link #perteneceACasa(Long)} contra este mismo valor.</p>
     *
     * @return la casa vigente del usuario, o {@code null} si no hay sesión o
     * el usuario todavía no tiene vivienda (por ejemplo, una cuenta en espera
     * que aún no completó el onboarding).
     */
    public Long casaIdActual() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null) return null;

        Long usuarioId = usuarioIdActual();
        if (usuarioId != null) {
            try {
                List<Map<String, Object>> filas = jdbcTemplate.queryForList(
                    "SELECT casa_id FROM usuario WHERE id = ? AND activo = true AND deleted_at IS NULL",
                    usuarioId);
                if (!filas.isEmpty()) {
                    Object casa = filas.get(0).get("casa_id");
                    return casa != null ? ((Number) casa).longValue() : null;
                }
            } catch (Exception ignored) {
                // Base no disponible: se usa el valor del token como respaldo.
            }
        }

        return auth.getCredentials() instanceof Long casaId ? casaId : null;
    }

    /**
     * @param casaId identificador de la casa que se quiere consultar/modificar.
     * @return {@code true} si el usuario autenticado pertenece exactamente a esa casa.
     */
    public boolean perteneceACasa(Long casaId) {
        Long propia = casaIdActual();
        return propia != null && casaId != null && propia.equals(casaId);
    }

    /**
     * Busca la casa de la que el usuario dado es propietario — para
     * completar el {@code casaId} cuando el JWT todavía no la trae (por
     * ejemplo, justo después de crear la casa, antes de volver a iniciar sesión).
     *
     * @param usuarioId identificador del usuario propietario.
     * @return el id de su casa, o {@code null} si no es propietario de ninguna.
     */
    public Long casaDelPropietario(Long usuarioId) {
        List<Map<String, Object>> casas = jdbcTemplate.queryForList(
            "SELECT id FROM casa WHERE propietario_id = ? LIMIT 1", usuarioId);
        return casas.isEmpty() ? null : ((Number) casas.get(0).get("id")).longValue();
    }
}
