package com.huellitas.admin;

import com.huellitas.config.AuthContext;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Vista de planes de suscripción orientada al propietario final: consultar
 * los planes disponibles, ver el plan vigente de su vivienda y cambiarse de
 * plan (los planes de pago quedan supeditados a la confirmación de pago en
 * {@link com.huellitas.pago.PagoController}).
 */
@RestController
@RequestMapping("/api/huellitas/planes")
public class PlanUsuarioController {

    private final JdbcTemplate jdbcTemplate;
    private final AuthContext authContext;

    public PlanUsuarioController(JdbcTemplate jdbcTemplate, AuthContext authContext) {
        this.jdbcTemplate = jdbcTemplate;
        this.authContext = authContext;
    }

    /** Plan al que el usuario desea cambiarse. */
    public static class CambiarPlanDTO {
        public Long planId;
    }

    /**
     * Lista los planes de suscripción actualmente activos, disponibles para contratar.
     * El resultado se cachea bajo {@code planesActivos} hasta que un administrador
     * modifique algún plan.
     *
     * @return un JSON (como texto) con la lista de planes activos; lista vacía si ocurre un error.
     */
    @org.springframework.cache.annotation.Cacheable("planesActivos")
    @GetMapping(value = "/activos", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarPlanesActivos() {
        try {
            String json = jdbcTemplate.queryForObject(
                "SELECT COALESCE(json_agg(t), '[]'::json) FROM (" +
                "SELECT id, nombre, precio_mensual, precio_oferta, descuento_porcentaje, descripcion, limite_dispositivos, limite_mascotas, limite_almacenamiento_mb " +
                "FROM plan WHERE activo = true ORDER BY id ASC) t",
                String.class
            );
            return ResponseEntity.ok(json != null ? json : "[]");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("[]");
        }
    }

    /**
     * Obtiene el plan de suscripción vigente de la vivienda del usuario
     * autenticado. Si no tiene ninguna suscripción activa registrada, se
     * asume el plan gratuito por defecto (id 1).
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado.
     * @return los datos del plan vigente, o un error 401/500 según el caso.
     */
    @GetMapping(value = "/mi-plan", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> miPlan(
            @RequestHeader(value = "Authorization", required = false) String authHeader) {
        Long usuarioId = authContext.usuarioIdActual();
        Long casaId = authContext.casaIdActual();

        if (usuarioId == null && casaId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "No autorizado"));
        }

        try {
            List<Map<String, Object>> rows = jdbcTemplate.queryForList(
                "SELECT s.id as suscripcion_id, s.plan_id, p.nombre as plan_nombre, p.precio_mensual, p.precio_oferta, p.descripcion, s.estado, s.created_at " +
                "FROM suscripcion s " +
                "JOIN plan p ON s.plan_id = p.id " +
                "JOIN casa c ON s.casa_id = c.id " +
                "WHERE (c.propietario_id = ? OR c.id = ?) AND s.estado::text IN ('ACTIVA', 'ACTIVO') " +
                "ORDER BY s.id DESC LIMIT 1",
                usuarioId, casaId
            );

            if (rows.isEmpty()) {
                List<Map<String, Object>> defaultPlan = jdbcTemplate.queryForList(
                    "SELECT 1 as plan_id, nombre as plan_nombre, precio_mensual, precio_oferta, descripcion FROM plan WHERE id = 1"
                );
                Map<String, Object> res = defaultPlan.isEmpty() ? Map.of("plan_id", 1, "plan_nombre", "FREE") : defaultPlan.get(0);
                return ResponseEntity.ok(res);
            }

            return ResponseEntity.ok(rows.get(0));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("ok", false, "error", e.getMessage()));
        }
    }

    /**
     * Cambia el plan de suscripción de la vivienda del usuario autenticado.
     * Los planes gratuitos se activan de inmediato; los planes de pago
     * devuelven un código 402 indicando que se requiere completar el pago
     * primero (ver {@link com.huellitas.pago.PagoController}), para evitar
     * que un usuario se autoasigne un plan premium sin pagarlo.
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado.
     * @param dto identificador del plan deseado.
     * @return confirmación del cambio si el plan es gratuito, una indicación de pago requerido (402) si es de pago, o un error 401/400/404/500 según el caso.
     */
    @PostMapping(value = "/cambiar", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> cambiarPlan(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody CambiarPlanDTO dto) {
        Long usuarioId = authContext.usuarioIdActual();
        Long casaId = authContext.casaIdActual();

        if (usuarioId == null && casaId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "No autorizado"));
        }

        if (dto == null || dto.planId == null) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "ID de plan no proporcionado"));
        }

        try {
            // Un plan de pago SOLO puede activarse tras un cobro verificado con
            // Stripe (POST /pagos/confirmar). Sin esta comprobación cualquiera
            // podía pasarse a PREMIUM llamando directamente a este endpoint.
            // El precio se lee de la base: es el que fije el administrador,
            // incluyendo el precio de oferta si lo hay.
            List<Map<String, Object>> planes = jdbcTemplate.queryForList(
                    "SELECT nombre, COALESCE(precio_oferta, precio_mensual) AS precio FROM plan WHERE id = ? AND activo = true",
                    dto.planId);
            if (planes.isEmpty()) {
                return ResponseEntity.status(404).body(Map.of("ok", false, "error", "Plan no encontrado o inactivo"));
            }
            double precio = ((Number) planes.get(0).get("precio")).doubleValue();
            if (precio > 0) {
                return ResponseEntity.status(402).body(Map.of(
                        "ok", false,
                        "requierePago", true,
                        "planId", dto.planId,
                        "precio", precio,
                        "error", "Este plan requiere pago. Completa el pago para activarlo."));
            }

            if (casaId == null) {
                casaId = authContext.casaDelPropietario(usuarioId);
            }

            if (casaId == null) {
                return ResponseEntity.status(400).body(Map.of("ok", false, "error", "El usuario no tiene una casa registrada"));
            }

            jdbcTemplate.queryForObject("SELECT fn_cambiar_plan_casa(?, ?)", String.class, casaId, dto.planId);

            return ResponseEntity.ok(Map.of(
                "ok", true,
                "message", "Plan actualizado exitosamente en el sistema.",
                "planId", dto.planId
            ));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("ok", false, "error", e.getMessage()));
        }
    }
}
