package com.huellitas.pago;

import com.huellitas.config.AuthContext;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

import java.util.List;
import java.util.Map;

/**
 * Pagos de suscripción con Stripe Checkout.
 *
 * Se usa la API REST de Stripe directamente (con el RestTemplate de Spring) en
 * lugar del SDK: evita sumar una dependencia nueva al proyecto y el contrato
 * de estos dos endpoints de Stripe es estable.
 *
 * Flujo seguro:
 *   1. El cliente pide una sesión de pago para un plan  → /pagos/checkout
 *   2. Stripe cobra en su propia página (nunca pasamos por aquí la tarjeta)
 *   3. Al volver, el cliente manda el id de sesión      → /pagos/confirmar
 *   4. El servidor le PREGUNTA A STRIPE si está pagada y recién ahí cambia el
 *      plan. Nunca se confía en lo que diga el cliente.
 */
@RestController
@RequestMapping("/api/huellitas/pagos")
public class PagoController {

    private static final String STRIPE_API = "https://api.stripe.com/v1";

    private final JdbcTemplate jdbcTemplate;
    private final AuthContext authContext;
    private final RestTemplate restTemplate = new RestTemplate();

    @Value("${stripe.secret-key:}")
    private String stripeSecretKey;

    @Value("${app.web-url:http://localhost:4200}")
    private String webUrl;

    public PagoController(JdbcTemplate jdbcTemplate, AuthContext authContext) {
        this.jdbcTemplate = jdbcTemplate;
        this.authContext = authContext;
    }

    /**
     * Crea la sesión de pago y devuelve la URL de Stripe a la que ir. Si el
     * plan solicitado es gratuito, no se crea sesión de pago y se indica
     * para que el cliente lo active directamente.
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado.
     * @param planId identificador del plan que se desea contratar.
     * @return la URL de checkout de Stripe (o {@code gratuito: true} si el plan no requiere pago), o un error 401/404/502/503 según el caso.
     */
    @PostMapping(value = "/checkout", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> crearCheckout(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestParam Long planId) {

        if (stripeSecretKey == null || stripeSecretKey.isBlank()) {
            return ResponseEntity.status(503)
                    .body(Map.of("ok", false, "error", "Pagos no configurados en el servidor"));
        }

        Long usuarioId = authContext.usuarioIdActual();
        if (usuarioId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "No autorizado"));
        }

        List<Map<String, Object>> planes = jdbcTemplate.queryForList(
                "SELECT id, nombre, COALESCE(precio_oferta, precio_mensual) AS precio FROM plan WHERE id = ? AND activo = true",
                planId);
        if (planes.isEmpty()) {
            return ResponseEntity.status(404).body(Map.of("ok", false, "error", "Plan no encontrado o inactivo"));
        }

        Map<String, Object> plan = planes.get(0);
        double precio = ((Number) plan.get("precio")).doubleValue();

        // Un plan gratuito no pasa por Stripe: se cambia directamente.
        if (precio <= 0) {
            return ResponseEntity.ok(Map.of("ok", true, "gratuito", true));
        }

        long centavos = Math.round(precio * 100);
        String nombrePlan = String.valueOf(plan.get("nombre"));

        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("mode", "payment");
        form.add("success_url", webUrl + "/planes?pago=ok&session_id={CHECKOUT_SESSION_ID}");
        form.add("cancel_url", webUrl + "/planes?pago=cancelado");
        form.add("client_reference_id", String.valueOf(usuarioId));
        form.add("metadata[planId]", String.valueOf(planId));
        form.add("metadata[usuarioId]", String.valueOf(usuarioId));
        form.add("line_items[0][quantity]", "1");
        form.add("line_items[0][price_data][currency]", "usd");
        form.add("line_items[0][price_data][unit_amount]", String.valueOf(centavos));
        form.add("line_items[0][price_data][product_data][name]", "Plan " + nombrePlan + " - Huellitas Inteligentes");

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setBearerAuth(stripeSecretKey);
            headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);

            ResponseEntity<Map> res = restTemplate.exchange(
                    STRIPE_API + "/checkout/sessions", HttpMethod.POST,
                    new HttpEntity<>(form, headers), Map.class);

            Map body = res.getBody();
            if (body == null || body.get("url") == null) {
                return ResponseEntity.status(502).body(Map.of("ok", false, "error", "Stripe no devolvió la sesión de pago"));
            }

            return ResponseEntity.ok(Map.of(
                    "ok", true,
                    "gratuito", false,
                    "url", body.get("url"),
                    "sessionId", body.get("id")));
        } catch (Exception e) {
            return ResponseEntity.status(502).body(Map.of("ok", false, "error", "Error creando el pago: " + e.getMessage()));
        }
    }

    /**
     * Verifica contra Stripe que la sesión esté realmente pagada y solo
     * entonces activa el plan. Es el paso que impide que alguien active un
     * plan simplemente llamando a la URL de éxito.
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado.
     * @param sessionId identificador de la sesión de pago de Stripe a confirmar.
     * @return confirmación con el plan activado, o un error 400/401/402/403/502 según el caso.
     */
    @PostMapping(value = "/confirmar", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> confirmarPago(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestParam String sessionId) {

        Long usuarioId = authContext.usuarioIdActual();
        Long casaId = authContext.casaIdActual();
        if (usuarioId == null && casaId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "No autorizado"));
        }
        // Las sesiones de checkout de Stripe siempre empiezan con "cs_"; sin
        // este chequeo, un sessionId con "/" viajaría tal cual dentro de la
        // URL de la llamada saliente a la API de Stripe.
        if (sessionId == null || !sessionId.matches("cs_[a-zA-Z0-9_]+")) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "sessionId inválido"));
        }

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setBearerAuth(stripeSecretKey);

            ResponseEntity<Map> res = restTemplate.exchange(
                    STRIPE_API + "/checkout/sessions/" + sessionId, HttpMethod.GET,
                    new HttpEntity<>(headers), Map.class);

            Map sesion = res.getBody();
            if (sesion == null) {
                return ResponseEntity.status(502).body(Map.of("ok", false, "error", "Sesión de pago no encontrada"));
            }

            String estadoPago = String.valueOf(sesion.get("payment_status"));
            if (!"paid".equals(estadoPago)) {
                return ResponseEntity.status(402)
                        .body(Map.of("ok", false, "error", "El pago no se completó (estado: " + estadoPago + ")"));
            }

            Map<String, Object> metadata = (Map<String, Object>) sesion.get("metadata");
            Long planId = metadata != null && metadata.get("planId") != null
                    ? Long.valueOf(String.valueOf(metadata.get("planId"))) : null;
            if (planId == null) {
                return ResponseEntity.status(400).body(Map.of("ok", false, "error", "La sesión no indica el plan"));
            }

            // La sesión debe pertenecer a quien la está confirmando.
            String duenoSesion = String.valueOf(sesion.get("client_reference_id"));
            if (usuarioId != null && !String.valueOf(usuarioId).equals(duenoSesion)) {
                return ResponseEntity.status(403).body(Map.of("ok", false, "error", "Este pago pertenece a otro usuario"));
            }

            Long casaFinal = casaId != null ? casaId : authContext.casaDelPropietario(usuarioId);
            if (casaFinal == null) {
                return ResponseEntity.status(400).body(Map.of("ok", false, "error", "El usuario no tiene casa registrada"));
            }

            jdbcTemplate.queryForObject("SELECT fn_cambiar_plan_casa(?, ?)", String.class, casaFinal, planId);

            return ResponseEntity.ok(Map.of("ok", true, "planId", planId, "message", "Pago confirmado y plan activado"));
        } catch (Exception e) {
            return ResponseEntity.status(502).body(Map.of("ok", false, "error", "Error verificando el pago: " + e.getMessage()));
        }
    }
}
