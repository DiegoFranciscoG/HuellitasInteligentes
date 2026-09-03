package com.huellitas.config;

import com.huellitas.auth.JwtUtil;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Set;

/**
 * Protege los 14 endpoints del firmware ESP32 exigiendo que la peticion
 * lleve un X-Device-Code valido (el codigo de vivienda generado en la app).
 *
 * Modo transicion: si la columna codigo_vinculacion no existe aun o el
 * X-Device-Code que manda el firmware no coincide con ninguna casa, el filtro
 * deja pasar en lugar de rechazar, para mantener la compatibilidad con el
 * firmware que todavia no manda el codigo.
 *
 * Jerarquia:
 * 1. Ruta que no es del firmware -> pasa sin comprobacion.
 * 2. Usuario con JWT valido (panel web/app) -> pasa siempre.
 * 3. X-Device-Code valido (coincide con casa.codigo_vinculacion) -> pasa.
 * 4. X-Device-Code ausente o incorrecto -> pasa en modo transicion (log de aviso).
 *    Cuando Fernando actualice el firmware, cambiar a 401.
 */
@Component
public class DeviceTokenFilter extends OncePerRequestFilter {

    private static final Set<String> RUTAS_FIRMWARE = Set.of(
        "/api/led", "/api/pump", "/api/fan",
        "/api/servo", "/api/servo2", "/api/servo3",
        "/api/stepper", "/api/dht", "/api/mq135",
        "/api/motion", "/api/water", "/api/ultrasonic",
        "/api/devices", "/api/automatic-mode"
    );

    private final JwtUtil jwtUtil;
    private final JdbcTemplate jdbc;

    public DeviceTokenFilter(JwtUtil jwtUtil, JdbcTemplate jdbc) {
        this.jwtUtil = jwtUtil;
        this.jdbc = jdbc;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {

        String path = request.getServletPath();

        // 1. Si la ruta no es del firmware, este filtro no actua.
        if (!esFirmware(path)) {
            filterChain.doFilter(request, response);
            return;
        }

        // 2. JWT valido: usuario del panel web/app -> pasa siempre.
        String authHeader = request.getHeader("Authorization");
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            try {
                jwtUtil.validarYObtenerClaims(authHeader);
                filterChain.doFilter(request, response);
                return;
            } catch (Exception ignored) { }
        }

        // 3. X-Device-Code: validar contra casa.codigo_vinculacion en la BD.
        String deviceCode = request.getHeader("X-Device-Code");
        if (deviceCode != null && !deviceCode.isBlank()) {
            try {
                Integer count = jdbc.queryForObject(
                    "SELECT COUNT(*) FROM casa WHERE codigo_vinculacion = ? AND deleted_at IS NULL",
                    Integer.class, deviceCode);
                if (count != null && count > 0) {
                    filterChain.doFilter(request, response);
                    return;
                }
                // Codigo invalido: log de aviso pero pasa (modo transicion).
                logger.warn("[DeviceTokenFilter] X-Device-Code desconocido en " + path + ": " + deviceCode);
            } catch (Exception e) {
                // Si la columna todavia no existe (antes de V50), pasa sin bloquear.
                logger.warn("[DeviceTokenFilter] No se pudo validar X-Device-Code: " + e.getMessage());
            }
        } else {
            // Sin cabecera -> modo transicion, pasa con aviso.
            logger.debug("[DeviceTokenFilter] Peticion sin X-Device-Code en " + path + " (modo transicion)");
        }

        // 4. Modo transicion: deja pasar pero log para que Diego sepa cuando activar el bloqueo.
        filterChain.doFilter(request, response);
    }

    private boolean esFirmware(String path) {
        return RUTAS_FIRMWARE.stream().anyMatch(path::startsWith);
    }
}
