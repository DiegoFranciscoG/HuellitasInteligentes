package com.huellitas.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.multipart.MultipartFile;
import com.huellitas.storage.S3AvatarService;
import com.huellitas.utils.ValidationUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;

/**
 * AuthController — maneja registro, login clásico y login Google OAuth2.
 *
 * NOTA SEGURIDAD: La auto-configuración de Spring Security OAuth2
 * (OAuth2ClientAutoConfiguration, UserDetailsServiceAutoConfiguration)
 * está EXCLUIDA en application.properties. Este controller implementa
 * el flujo OAuth2 de Google de forma COMPLETAMENTE MANUAL usando RestTemplate:
 *   GET  /auth/google/login    → redirige a Google
 *   GET  /auth/google/callback → intercambia code → llama fn_login_oauth → JWT
 *
 * Así NO se reactiva ningún filtro de Spring Security para OAuth2.
 */
@RestController
@RequestMapping("/api/huellitas/auth")
public class AuthController {

    private static final Logger log = LoggerFactory.getLogger(AuthController.class);

    private final AuthRepository repo;
    private final AuthMailService mailService;
    private final JwtUtil jwtUtil;
    private final S3AvatarService s3AvatarService;
    private final RestTemplate restTemplate = new RestTemplate();

    @Value("${google.oauth2.client-id:placeholder}")
    private String googleClientId;

    @Value("${google.oauth2.client-secret:}")
    private String googleClientSecret;

    @Value("${google.oauth2.redirect-uri:http://localhost:8087/api/huellitas/auth/google/callback}")
    private String googleRedirectUri;

    @Value("${app.frontend.url:http://localhost:4200}")
    private String frontendUrl;

    @Value("${facebook.oauth2.app-id:placeholder}")
    private String facebookAppId;

    @Value("${facebook.oauth2.app-secret:}")
    private String facebookClientSecret;

    @Value("${facebook.oauth2.redirect-uri:http://localhost:8087/api/huellitas/auth/facebook/callback}")
    private String facebookRedirectUri;

    private static final String GOOGLE_AUTH_URL  = "https://accounts.google.com/o/oauth2/v2/auth";
    private static final String GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
    private static final String GOOGLE_INFO_URL  = "https://www.googleapis.com/oauth2/v3/userinfo";

    private static final String FB_AUTH_URL  = "https://www.facebook.com/v19.0/dialog/oauth";
    private static final String FB_TOKEN_URL = "https://graph.facebook.com/v19.0/oauth/access_token";
    private static final String FB_INFO_URL  = "https://graph.facebook.com/me?fields=id,name,email,picture.type(large)";

    private final com.huellitas.config.AuthContext authContext;
    private final org.springframework.jdbc.core.JdbcTemplate jdbc;

    public AuthController(AuthRepository repo, AuthMailService mailService, JwtUtil jwtUtil, S3AvatarService s3AvatarService, com.huellitas.config.AuthContext authContext, org.springframework.jdbc.core.JdbcTemplate jdbc) {
        this.repo = repo;
        this.mailService = mailService;
        this.jwtUtil = jwtUtil;
        this.s3AvatarService = s3AvatarService;
        this.authContext = authContext;
        this.jdbc = jdbc;
    }

    /**
     * Nombre de la vivienda de la que el usuario autenticado fue dado de
     * baja como miembro, si la hay. Alimenta el aviso "Fuiste removido de
     * la casa X" que se muestra al llegar sin vivienda propia.
     *
     * <p>Consulta el {@code casa_anterior_id} del propio usuario autenticado
     * —nunca uno pasado por parámetro— para no exponer el nombre de una
     * vivienda ajena a quien no salió de ella.</p>
     *
     * @return {@code {"ok":true,"nombre":"..."}} si tiene una vivienda anterior registrada, o {@code {"ok":false}} si no.
     */
    @GetMapping(value = "/casa-anterior", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> casaAnterior() {
        Long usuarioId = authContext.usuarioIdActual();
        if (usuarioId == null) {
            return ResponseEntity.status(401).body("{\"ok\":false}");
        }
        java.util.List<java.util.Map<String, Object>> filas = jdbc.queryForList(
            "SELECT c.nombre FROM usuario u JOIN casa c ON c.id = u.casa_anterior_id " +
            "WHERE u.id = ? AND u.casa_anterior_id IS NOT NULL", usuarioId);
        if (filas.isEmpty()) {
            return ResponseEntity.ok("{\"ok\":false}");
        }
        String nombre = String.valueOf(filas.get(0).get("nombre")).replace("\"", "\\\"");
        return ResponseEntity.ok("{\"ok\":true,\"nombre\":\"" + nombre + "\"}");
    }

    // ─────────────────────────────────────────────────────────
    //  REGISTRO / LOGIN CLÁSICO
    // ─────────────────────────────────────────────────────────

    /**
     * Registra un nuevo usuario propietario junto con su vivienda inicial,
     * envía el código de verificación de correo y el correo de bienvenida,
     * y devuelve un JWT de sesión.
     *
     * @param payload datos de registro: email, password, nombre, casa_nombre, direccion, ciudad, latitud, longitud.
     * @return el token JWT y los datos del usuario creado, o un error 400 si el correo ya está registrado o los datos son inválidos.
     */
    @PostMapping(value = "/registro-propietario", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> registrarPropietario(@RequestBody Map<String, String> payload) {
        try {
            String email = ValidationUtils.validarEmail(payload.get("email"));
            ValidationUtils.validarPassword(payload.get("password"));
            String password = payload.get("password");
            String nombre = ValidationUtils.formatearYValidarNombrePersona(payload.get("nombre"));
            String casaNombre = ValidationUtils.validarNombreEntidad(payload.get("casa_nombre"));
            String direccion = payload.get("direccion");
            String ciudad = payload.get("ciudad");
            String latitudStr = payload.get("latitud");
            String longitudStr = payload.get("longitud");
            java.math.BigDecimal latitud = (latitudStr != null && !latitudStr.isEmpty()) ? new java.math.BigDecimal(latitudStr) : null;
            java.math.BigDecimal longitud = (longitudStr != null && !longitudStr.isEmpty()) ? new java.math.BigDecimal(longitudStr) : null;
            
            String userJson = repo.registrarPropietario(email, password, nombre, casaNombre, direccion, ciudad, latitud, longitud);
            
            // Extracción de usuario e ID para verificación
            String extractedUserJson = jwtUtil.extractUserJson(userJson);
            String codigo = String.format("%06d", new java.util.Random().nextInt(999999));
            Long userId = extractUserIdFromJson(extractedUserJson);
            if (userId != null) {
                repo.solicitarVerificacion(userId, codigo, 1440); // 24 horas
            }
            
            mailService.sendWelcomeEmail(email, nombre);
            mailService.sendVerificationEmail(email, nombre, codigo);
            
            String token = jwtUtil.generateTokenFromJsonUser(userJson);
            return ResponseEntity.ok("{\"token\":\"" + token + "\", \"usuario\":" + extractedUserJson + "}");
        } catch (org.springframework.dao.DataIntegrityViolationException e) {
            return ResponseEntity.status(400).body("{\"ok\":false, \"error\":\"Usuario ya registrado con ese correo.\"}");
        } catch (Exception e) {
            String msg = e.getMessage() != null ? e.getMessage() : "Error";
            if (msg.contains("EMAIL_YA_REGISTRADO")) msg = "Usuario ya registrado con ese correo.";
            return ResponseEntity.status(400).body("{\"ok\":false, \"error\":\"" + msg + "\"}");
        }
    }

    /**
     * Autentica a un usuario por correo y contraseña.
     *
     * @param payload debe contener {@code email} y la contraseña bajo la clave {@code contrasena} o {@code password}.
     * @return el token JWT y los datos del usuario si las credenciales son correctas, o un error 401 en caso contrario.
     */
    @PostMapping(value = "/login", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> login(@RequestBody Map<String, String> payload) {
        try {
            String email = ValidationUtils.validarEmail(payload.get("email"));
            String password = payload.get("contrasena");
            if (password == null) password = payload.get("password");

            String userJson = repo.login(email, password);
            String token = jwtUtil.generateTokenFromJsonUser(userJson);
            return ResponseEntity.ok("{\"token\":\"" + token + "\", \"usuario\":" + jwtUtil.extractUserJson(userJson) + "}");
        } catch (Exception e) {
            // fn_login distingue el motivo del rechazo (ver V32__login_mensaje_sancion.sql):
            // antes cualquier fallo —contraseña mala o cuenta sancionada por 3 strikes—
            // mostraba el mismo "Credenciales inválidas", así que quien perdía su cuenta
            // por reportes de la comunidad no se enteraba de qué había pasado.
            String motivo = e.getMessage() != null ? e.getMessage() : "";
            if (motivo.contains("CUENTA_SANCIONADA")) {
                return ResponseEntity.status(403).body("{\"message\":\"Tu cuenta fue suspendida por acumular 3 reportes de la comunidad. Si crees que es un error, contacta a soporte.\", \"codigo\":\"CUENTA_SANCIONADA\"}");
            }
            if (motivo.contains("CUENTA_BLOQUEADA")) {
                return ResponseEntity.status(403).body("{\"message\":\"Tu cuenta está bloqueada. Contacta al propietario de tu vivienda o a soporte.\", \"codigo\":\"CUENTA_BLOQUEADA\"}");
            }
            return ResponseEntity.status(401).body("{\"message\":\"Credenciales inválidas\"}");
        }
    }

    /**
     * Valida el código de 6 dígitos enviado al correo del usuario para
     * confirmar su cuenta y, de ser correcto, entrega un JWT de sesión.
     *
     * @param payload debe contener {@code email} y {@code codigo}.
     * @return el token JWT y los datos del usuario si el código es válido, o un error 400 en caso contrario.
     */
    @PostMapping(value = "/verificar-codigo", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> verificarCodigo(@RequestBody Map<String, String> payload) {
        try {
            String email = payload.get("email");
            String codigo = payload.get("codigo");
            String userJson = repo.verificarCodigo(email, codigo);
            String token = jwtUtil.generateTokenFromJsonUser(userJson);
            return ResponseEntity.ok("{\"token\":\"" + token + "\", \"usuario\":" + jwtUtil.extractUserJson(userJson) + "}");
        } catch (Exception e) {
            String msg = e.getMessage() != null ? e.getMessage() : "Error de verificación";
            return ResponseEntity.status(400).body("{\"ok\":false, \"message\":\"" + msg + "\"}");
        }
    }

    /**
     * Genera un nuevo código de verificación y lo reenvía por correo, para
     * cuando el usuario no recibió o dejó expirar el código original.
     *
     * @param payload debe contener {@code email}.
     * @return confirmación de reenvío, o un error 400 si falta el correo.
     */
    @PostMapping(value = "/reenviar-codigo", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> reenviarCodigo(@RequestBody Map<String, String> payload) {
        try {
            String email = payload.get("email");
            if (email == null || email.isBlank()) {
                return ResponseEntity.status(400).body("{\"message\":\"Email requerido\"}");
            }
            String codigo = String.format("%06d", new java.util.Random().nextInt(999999));
            repo.solicitarVerificacionPorEmail(email, codigo, 1440);
            mailService.sendVerificationEmail(email, "Usuario", codigo);
            System.out.println("[SMTP VERIFICACION] Código generado y enviado a " + email + ": " + codigo);
            return ResponseEntity.ok("{\"ok\":true, \"message\":\"Código reenviado a tu correo\"}");
        } catch (Exception e) {
            return ResponseEntity.status(400).body("{\"message\":\"" + e.getMessage() + "\"}");
        }
    }

    /**
     * Crea una cuenta de miembro asociada a una vivienda existente, invitado
     * por el propietario de la casa.
     *
     * @param payload debe contener {@code casaId}, {@code email}, {@code password} y {@code nombre}.
     * @return los datos del miembro creado, o un error 400 si los datos son inválidos.
     */
    @PostMapping(value = "/invitar-miembro", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> invitarMiembro(@RequestBody Map<String, String> payload) {
        try {
            Long casaId = Long.valueOf(payload.get("casaId"));
            if (!authContext.perteneceACasa(casaId)) {
                return ResponseEntity.status(403).body("{\"message\":\"No tienes permiso para invitar miembros a esta casa\"}");
            }
            String email = ValidationUtils.validarEmail(payload.get("email"));
            ValidationUtils.validarPassword(payload.get("password"));
            String password = payload.get("password");
            String nombre = ValidationUtils.formatearYValidarNombrePersona(payload.get("nombre"));
            
            String userJson = repo.invitarMiembro(casaId, email, password, nombre);
            return ResponseEntity.ok("{\"usuario\":" + jwtUtil.extractUserJson(userJson) + "}");
        } catch (Exception e) {
            return ResponseEntity.status(400).body("{\"message\":\"" + e.getMessage() + "\"}");
        }
    }

    /**
     * Completa el registro de un usuario que inició sesión por primera vez
     * mediante OAuth (Google/Facebook), registrando su nombre y la vivienda inicial.
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado.
     * @param payload datos de onboarding: nombre, casa_nombre, direccion, ciudad, latitud, longitud.
     * @return un nuevo token JWT y los datos actualizados del usuario, o un error 401/400 según el caso.
     */
    @PostMapping(value = "/completar-onboarding", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> completarOnboarding(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody Map<String, String> payload) {
        Long usuarioId = authContext.usuarioIdActual();
        if (usuarioId == null) {
            return ResponseEntity.status(401).body("{\"message\":\"No autorizado\"}");
        }
        try {
            String nombre = ValidationUtils.formatearYValidarNombrePersona(payload.get("nombre"));
            String casaNombre = ValidationUtils.validarNombreEntidad(payload.get("casa_nombre"));
            String direccion = payload.get("direccion");
            String ciudad = payload.get("ciudad");
            String latitudStr = payload.get("latitud");
            String longitudStr = payload.get("longitud");
            java.math.BigDecimal latitud = (latitudStr != null && !latitudStr.isEmpty()) ? new java.math.BigDecimal(latitudStr) : null;
            java.math.BigDecimal longitud = (longitudStr != null && !longitudStr.isEmpty()) ? new java.math.BigDecimal(longitudStr) : null;

            String userJson = repo.completarOnboarding(usuarioId, nombre, casaNombre, direccion, ciudad, latitud, longitud);
            String token = jwtUtil.generateTokenFromJsonUser(userJson);
            return ResponseEntity.ok("{\"token\":\"" + token + "\", \"usuario\":" + jwtUtil.extractUserJson(userJson) + "}");
        } catch (Exception e) {
            return ResponseEntity.status(400).body("{\"message\":\"" + e.getMessage() + "\"}");
        }
    }

    // ─────────────────────────────────────────────────────────
    //  GOOGLE OAUTH2 — FLUJO MANUAL (sin Spring OAuth2 auto-config)
    // ─────────────────────────────────────────────────────────

    /**
     * Paso 1: redirige al usuario a la pantalla de consentimiento de Google.
     * El frontend llama: window.location.href = '/api/huellitas/auth/google/login'
     */
    @GetMapping("/google/login")
    public void googleLogin(HttpServletResponse response) throws IOException {
        String url = GOOGLE_AUTH_URL
            + "?client_id=" + encode(googleClientId)
            + "&redirect_uri=" + encode(googleRedirectUri)
            + "&response_type=code"
            + "&scope=" + encode("openid email profile")
            + "&access_type=offline"
            + "&prompt=consent";
        response.sendRedirect(url);
    }

    /**
     * Paso 2: Google redirige aquí con ?code=...
     * Intercambiamos el code por access_token, obtenemos userinfo,
     * llamamos fn_login_oauth y redirigimos al frontend con el JWT.
     * Esta ruta es pública (anyRequest().permitAll() en SecurityConfig).
     */
    @GetMapping("/google/callback")
    public void googleCallback(@RequestParam(required = false) String code,
                               @RequestParam(required = false) String error,
                               HttpServletResponse response) throws IOException {
        log.info("[GOOGLE CALLBACK] code={}, error={}", code != null ? code.substring(0, Math.min(10, code.length())) + "..." : "NO CODE", error);

        if (code == null || error != null) {
            String redirectTo = frontendUrl + "/auth/login?error=google_denied";
            log.info("[GOOGLE CALLBACK] Redirigiendo a (sin code): {}", redirectTo);
            response.sendRedirect(redirectTo);
            return;
        }

        try {
            // Intercambiar code → access_token
            log.info("[GOOGLE CALLBACK] Intercambiando code por access_token...");
            MultiValueMap<String, String> tokenBody = new LinkedMultiValueMap<>();
            tokenBody.add("code",          code);
            tokenBody.add("client_id",     googleClientId);
            tokenBody.add("client_secret", googleClientSecret);
            tokenBody.add("redirect_uri",  googleRedirectUri);
            tokenBody.add("grant_type",    "authorization_code");

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
            @SuppressWarnings("rawtypes")
            Map tokenResp = restTemplate.postForObject(
                GOOGLE_TOKEN_URL,
                new HttpEntity<>(tokenBody, headers),
                Map.class
            );

            String accessToken = tokenResp != null ? (String) tokenResp.get("access_token") : null;
            if (accessToken == null) {
                String redirectTo = frontendUrl + "/auth/login?error=google_token";
                log.warn("[GOOGLE CALLBACK] access_token null. tokenResp={} → redirigiendo a: {}", tokenResp, redirectTo);
                response.sendRedirect(redirectTo);
                return;
            }
            log.info("[GOOGLE CALLBACK] access_token obtenido OK. Obteniendo userinfo...");

            // Obtener info del usuario de Google
            HttpHeaders infoHeaders = new HttpHeaders();
            infoHeaders.setBearerAuth(accessToken);
            @SuppressWarnings("rawtypes")
            Map userInfo = restTemplate.exchange(
                GOOGLE_INFO_URL,
                HttpMethod.GET,
                new HttpEntity<>(infoHeaders),
                Map.class
            ).getBody();

            if (userInfo == null) {
                String redirectTo = frontendUrl + "/auth/login?error=google_userinfo";
                log.warn("[GOOGLE CALLBACK] userInfo null → redirigiendo a: {}", redirectTo);
                response.sendRedirect(redirectTo);
                return;
            }

            String sub    = (String) userInfo.get("sub");
            String email  = (String) userInfo.get("email");
            String nombre = (String) userInfo.get("name");
            String picture = (String) userInfo.get("picture");
            log.info("[GOOGLE CALLBACK] userInfo: sub={}, email={}, nombre={}", sub, email, nombre);

            // Llamar fn_login_oauth
            log.info("[GOOGLE CALLBACK] Llamando fn_login_oauth...");
            String userJson = repo.loginOauth("GOOGLE", sub, email, nombre, picture);
            log.info("[GOOGLE CALLBACK] fn_login_oauth OK. userJson={}", userJson);

            // Generar JWT
            log.info("[GOOGLE CALLBACK] Generando JWT...");
            String jwt = jwtUtil.generateTokenFromJsonUser(userJson);
            if (jwt == null || jwt.isEmpty()) {
                String redirectTo = frontendUrl + "/auth/login?error=google_oauth_fn";
                log.error("[GOOGLE CALLBACK] JWT null/vacío. userJson={} → redirigiendo a: {}", userJson, redirectTo);
                response.sendRedirect(redirectTo);
                return;
            }

            // Redirigir al frontend con el token
            String redirectTo = frontendUrl + "/oauth/callback?token=" + encode(jwt);
            log.info("[GOOGLE CALLBACK] JWT generado OK. Redirigiendo a: {}", redirectTo);
            response.sendRedirect(redirectTo);

        } catch (Exception ex) {
            String redirectTo = frontendUrl + "/auth/login?error=google_exception&msg=" + encode(ex.getMessage() != null ? ex.getMessage() : "unknown");
            log.error("[GOOGLE CALLBACK] EXCEPCIÓN: {} | Redirigiendo a: {}", ex.getMessage(), redirectTo, ex);
            response.sendRedirect(redirectTo);
        }
    }

    /**
     * Variante del login con Google pensada para clientes nativos (la app
     * Flutter): recibe el {@code id_token} obtenido por el SDK de Google en
     * el dispositivo y lo valida contra el endpoint de Google, sin pasar por
     * el flujo de redirección web.
     *
     * @param body debe contener {@code id_token}, el token de identidad emitido por Google.
     * @return el token JWT y los datos del usuario si el token de Google es válido, o un error 400/401 en caso contrario.
     */
    @PostMapping(value = "/google/token", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> googleTokenLogin(@RequestBody Map<String, String> body) {
        String idToken = body != null ? body.get("id_token") : null;
        if (idToken == null || idToken.isBlank()) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "Token de Google no proporcionado"));
        }
        try {
            String tokenInfoUrl = "https://oauth2.googleapis.com/tokeninfo?id_token=" + encode(idToken.trim());
            @SuppressWarnings("rawtypes")
            Map tokenInfo = restTemplate.getForObject(tokenInfoUrl, Map.class);
            if (tokenInfo == null || tokenInfo.get("email") == null) {
                return ResponseEntity.status(401).body(Map.of("ok", false, "error", "Token de Google inválido o expirado"));
            }

            String sub = (String) tokenInfo.get("sub");
            String email = (String) tokenInfo.get("email");
            String nombre = (String) tokenInfo.get("name");
            String picture = (String) tokenInfo.get("picture");

            String userJson = repo.loginOauth("GOOGLE", sub, email, nombre != null ? nombre : "Usuario Google", picture);
            String token = jwtUtil.generateTokenFromJsonUser(userJson);

            return ResponseEntity.ok(Map.of("ok", true, "token", token, "usuario", jwtUtil.extractUserJson(userJson)));
        } catch (Exception e) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "Fallo al validar credenciales de Google: " + e.getMessage()));
        }
    }

    // ─────────────────────────────────────────────────────────
    //  FACEBOOK OAUTH2 — FLUJO MANUAL
    // ─────────────────────────────────────────────────────────

    /**
     * Paso 1: redirige al usuario a Facebook.
     * El frontend llama: window.location.href = '/api/huellitas/auth/facebook/login'
     */
    /**
     * @param platform {@code "app"} cuando quien inicia el flujo es la aplicación móvil, para que
     *                 {@link #facebookCallback} sepa devolver el token por un enlace propio
     *                 ({@code huellitas://oauth-callback}) en vez de a la web. Cualquier otro
     *                 valor (u omitirlo) mantiene el comportamiento de siempre.
     */
    @GetMapping("/facebook/login")
    public void facebookLogin(@RequestParam(required = false) String platform, HttpServletResponse response) throws IOException {
        String url = FB_AUTH_URL
            + "?client_id="    + encode(facebookAppId)
            + "&redirect_uri=" + encode(facebookRedirectUri)
            + "&scope="        + encode("public_profile,email")
            + "&response_type=code"
            + "&state="        + encode("app".equals(platform) ? "app" : "web");
        response.sendRedirect(url);
    }

    /**
     * Paso 2: Facebook redirige aquí con ?code=...
     * URI exacta para el panel de Facebook Developers:
     *   http://localhost:8087/api/huellitas/auth/facebook/callback
     */
    @GetMapping("/facebook/callback")
    public void facebookCallback(@RequestParam(required = false) String code,
                                  @RequestParam(required = false) String error,
                                  @RequestParam(required = false) String state,
                                  HttpServletResponse response) throws IOException {
        log.info("[FACEBOOK CALLBACK] code={}, error={}, state={}", code != null ? code.substring(0, Math.min(10, code.length())) + "..." : "NO CODE", error, state);

        // La app manda platform=app al iniciar el flujo (ver facebookLogin), y
        // Facebook devuelve ese mismo valor en `state` sin tocarlo. Sirve para
        // saber a dónde entregar el resultado: la app no tiene forma de leer
        // localStorage de la web, así que necesita un enlace propio.
        boolean esApp = "app".equals(state);

        if (code == null || error != null) {
            String redirectTo = esApp
                ? "huellitas://oauth-callback?error=facebook_denied"
                : frontendUrl + "/auth/login?error=facebook_denied";
            log.info("[FACEBOOK CALLBACK] Redirigiendo a (sin code): {}", redirectTo);
            response.sendRedirect(redirectTo);
            return;
        }
        try {
            // Intercambiar code → access_token (UriComponentsBuilder para evitar doble-encoding de redirect_uri)
            log.info("[FACEBOOK CALLBACK] Intercambiando code por access_token...");
            String tokenUrl = org.springframework.web.util.UriComponentsBuilder
                .fromUriString(FB_TOKEN_URL)
                .queryParam("client_id", facebookAppId)
                .queryParam("client_secret", facebookClientSecret)
                .queryParam("redirect_uri", facebookRedirectUri)
                .queryParam("code", code)
                .toUriString();

            @SuppressWarnings("rawtypes")
            Map tokenResp = restTemplate.getForObject(tokenUrl, Map.class);
            String accessToken = tokenResp != null ? (String) tokenResp.get("access_token") : null;
            if (accessToken == null) {
                String redirectTo = esApp ? "huellitas://oauth-callback?error=facebook_token" : frontendUrl + "/auth/login?error=facebook_token";
                log.warn("[FACEBOOK CALLBACK] access_token null. tokenResp={} → redirigiendo a: {}", tokenResp, redirectTo);
                response.sendRedirect(redirectTo);
                return;
            }
            log.info("[FACEBOOK CALLBACK] access_token obtenido OK. Obteniendo userinfo...");

            // Obtener info del usuario de Facebook Graph API
            String infoUrl = FB_INFO_URL + "&access_token=" + encode(accessToken);
            @SuppressWarnings("rawtypes")
            Map userInfo = restTemplate.getForObject(infoUrl, Map.class);
            if (userInfo == null) {
                String redirectTo = esApp ? "huellitas://oauth-callback?error=facebook_userinfo" : frontendUrl + "/auth/login?error=facebook_userinfo";
                log.warn("[FACEBOOK CALLBACK] userInfo null → redirigiendo a: {}", redirectTo);
                response.sendRedirect(redirectTo);
                return;
            }

            String fbId   = String.valueOf(userInfo.get("id"));
            String email  = userInfo.get("email") != null
                            ? (String) userInfo.get("email")
                            : fbId + "@facebook.com";
            String nombre = (String) userInfo.get("name");
            log.info("[FACEBOOK CALLBACK] userInfo: fbId={}, email={}, nombre={}", fbId, email, nombre);

            String pictureUrl = null;
            if (userInfo.get("picture") instanceof Map pictureMap) {
                if (pictureMap.get("data") instanceof Map dataMap) {
                    pictureUrl = (String) dataMap.get("url");
                }
            }

            // Llamar fn_login_oauth
            log.info("[FACEBOOK CALLBACK] Llamando fn_login_oauth...");
            String userJson = repo.loginOauth("FACEBOOK", fbId, email, nombre, pictureUrl);
            log.info("[FACEBOOK CALLBACK] fn_login_oauth OK. userJson={}", userJson);

            // Generar JWT
            log.info("[FACEBOOK CALLBACK] Generando JWT...");
            String jwt = jwtUtil.generateTokenFromJsonUser(userJson);

            if (jwt == null || jwt.isEmpty()) {
                String redirectTo = esApp ? "huellitas://oauth-callback?error=facebook_oauth_fn" : frontendUrl + "/auth/login?error=facebook_oauth_fn";
                log.error("[FACEBOOK CALLBACK] JWT null/vacío. userJson={} → redirigiendo a: {}", userJson, redirectTo);
                response.sendRedirect(redirectTo);
                return;
            }

            String redirectTo = esApp
                ? "huellitas://oauth-callback?token=" + encode(jwt)
                : frontendUrl + "/oauth/callback?token=" + encode(jwt);
            log.info("[FACEBOOK CALLBACK] JWT generado OK. Redirigiendo a: {}", redirectTo);
            response.sendRedirect(redirectTo);

        } catch (Exception ex) {
            String redirectTo = esApp
                ? "huellitas://oauth-callback?error=facebook_exception"
                : frontendUrl + "/auth/login?error=facebook_exception&msg=" + encode(ex.getMessage() != null ? ex.getMessage() : "unknown");
            log.error("[FACEBOOK CALLBACK] EXCEPCIÓN: {} | Redirigiendo a: {}", ex.getMessage(), redirectTo, ex);
            response.sendRedirect(redirectTo);
        }
    }

    // ─────────────────────────────────────────────────────────
    //  PERFIL
    // ─────────────────────────────────────────────────────────

    /** Datos de perfil (nombre y/o foto) enviados como JSON en lugar de multipart. */
    public static class PerfilDTO {
        public String nombre;
        public String fotoUrl;
        public String getNombre() { return nombre; }
        public String getFotoUrl() { return fotoUrl; }
    }

    /**
     * Actualiza el nombre y/o la foto de perfil del usuario autenticado,
     * subiendo la imagen recibida como archivo a Backblaze B2.
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado.
     * @param nombre nuevo nombre del usuario (opcional).
     * @param file nueva foto de perfil como archivo multipart (opcional).
     * @return los datos actualizados del usuario, o un error 401/500 según el caso.
     */
    @PutMapping(value = "/perfil", consumes = {MediaType.MULTIPART_FORM_DATA_VALUE}, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> actualizarPerfil(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestParam(required = false) String nombre,
            @RequestParam(value = "file", required = false) MultipartFile file) {
        Long usuarioId = authContext.usuarioIdActual();
        if (usuarioId == null) {
            return ResponseEntity.status(401).body("{\"ok\":false, \"error\":\"No autorizado o token inválido\"}");
        }
        
        if (nombre != null) {
            nombre = ValidationUtils.formatearYValidarNombrePersona(nombre);
        }
        
        String fotoUrl = null;
        if (file != null && !file.isEmpty()) {
            try {
                fotoUrl = s3AvatarService.uploadFile(file);
            } catch (IllegalArgumentException e) {
                return ResponseEntity.status(400).body("{\"ok\": false, \"error\": \"" + e.getMessage() + "\"}");
            } catch (Exception e) {
                return ResponseEntity.status(500).body("{\"error\": \"Error subiendo la imagen a Backblaze B2\"}");
            }
        }

        return ResponseEntity.ok(repo.actualizarPerfil(usuarioId, nombre, fotoUrl));
    }

    /**
     * Variante de actualización de perfil para clientes que envían los datos
     * como JSON o parámetros de formulario en lugar de un archivo multipart
     * (por ejemplo, cuando la foto ya fue subida antes y solo se referencia por URL).
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado.
     * @param dto datos de perfil enviados como JSON (opcional).
     * @param nombre nuevo nombre del usuario, si se envía como parámetro de formulario.
     * @param fotoUrl nueva URL de foto de perfil, si se envía como parámetro de formulario.
     * @return los datos actualizados del usuario, o un error 401 si no está autenticado.
     */
    @PutMapping(value = "/perfil", consumes = {MediaType.APPLICATION_JSON_VALUE, MediaType.APPLICATION_FORM_URLENCODED_VALUE}, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> actualizarPerfil(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody(required = false) PerfilDTO dto,
            @RequestParam(required = false) String nombre,
            @RequestParam(required = false) String fotoUrl) {
        Long usuarioId = authContext.usuarioIdActual();
        if (usuarioId == null) {
            return ResponseEntity.status(401).body("{\"ok\":false, \"error\":\"No autorizado o token inválido\"}");
        }
        
        String finalNombre = (dto != null && dto.getNombre() != null) ? dto.getNombre() : nombre;
        if (finalNombre != null) {
            finalNombre = ValidationUtils.formatearYValidarNombrePersona(finalNombre);
        }
        String finalFotoUrl = (dto != null && dto.getFotoUrl() != null) ? dto.getFotoUrl() : fotoUrl;
        
        return ResponseEntity.ok(repo.actualizarPerfil(usuarioId, finalNombre, finalFotoUrl));
    }

    /**
     * Devuelve los datos actuales del usuario autenticado.
     * La web guardaba el usuario en localStorage al iniciar sesión y no lo
     * volvía a consultar, así que un cambio de foto hecho desde la app nunca
     * se reflejaba en la web. Con este endpoint ambos clientes pueden
     * refrescar la sesión contra la base de datos.
     */
    @GetMapping(value = "/me", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> usuarioActual(
            @RequestHeader(value = "Authorization", required = false) String authHeader) {
        Long usuarioId = authContext.usuarioIdActual();
        if (usuarioId == null) {
            return ResponseEntity.status(401).body("{\"ok\":false, \"error\":\"No autorizado\"}");
        }
        String usuario = repo.obtenerUsuarioPorId(usuarioId);
        if (usuario == null) {
            return ResponseEntity.status(404).body("{\"ok\":false, \"error\":\"Usuario no encontrado\"}");
        }
        return ResponseEntity.ok(usuario);
    }

    /**
     * Indica si el usuario autenticado ya tiene una contraseña local
     * configurada (útil para usuarios que iniciaron con OAuth y aún no
     * establecen contraseña propia).
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado.
     * @return {@code {"tiene_password": true|false}}, o un error 401 si no está autenticado.
     */
    @GetMapping(value = "/tiene-password", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> tienePassword(
            @RequestHeader(value = "Authorization", required = false) String authHeader) {
        Long usuarioId = authContext.usuarioIdActual();
        if (usuarioId == null) {
            return ResponseEntity.status(401).body("{\"ok\":false, \"error\":\"No autorizado\"}");
        }
        Boolean tiene = repo.tienePassword(usuarioId);
        return ResponseEntity.ok("{\"tiene_password\":" + (tiene != null && tiene) + "}");
    }

    /**
     * Establece por primera vez la contraseña local del usuario autenticado
     * (por ejemplo, tras registrarse vía OAuth).
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado.
     * @param nuevaPassword la nueva contraseña a establecer.
     * @return confirmación de la operación, o un error 401/400 según el caso.
     */
    @PostMapping(value = "/establecer-password", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> establecerPassword(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestParam String nuevaPassword) {
        Long usuarioId = authContext.usuarioIdActual();
        if (usuarioId == null) {
            return ResponseEntity.status(401).body("{\"ok\":false, \"error\":\"No autorizado\"}");
        }
        try {
            ValidationUtils.validarPassword(nuevaPassword);
            return ResponseEntity.ok(repo.establecerPasswordInicial(usuarioId, nuevaPassword));
        } catch (Exception e) {
            return ResponseEntity.status(400).body("{\"ok\":false, \"error\":\"Error al establecer contraseña o ya existe\"}");
        }
    }

    /**
     * Inicia el flujo de recuperación de contraseña: genera un token
     * aleatorio, guarda su hash en la base de datos y envía por correo un
     * enlace (válido por 30 minutos) para que el usuario defina una nueva contraseña.
     *
     * @param email correo del usuario, como parámetro de consulta (opcional si viene en {@code body}).
     * @param body cuerpo JSON alternativo que puede contener {@code email}.
     * @return confirmación de envío, o un error si el correo no fue proporcionado.
     */
    @PostMapping(value = "/solicitar-reset", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> solicitarReset(
            @RequestParam(required = false) String email,
            @RequestBody(required = false) Map<String, String> body) {
        String mail = email != null ? email : (body != null ? body.get("email") : null);
        if (mail == null || mail.trim().isEmpty()) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "Correo electrónico no proporcionado"));
        }

        try {
            mail = ValidationUtils.validarEmail(mail);
            
            String rawToken = java.util.UUID.randomUUID().toString().replace("-", "");
            String tokenHash = sha256(rawToken);

            repo.solicitarReset(mail, tokenHash);

            String resetLink = frontendUrl + "/auth/reset-password?token=" + rawToken;
            String mensajeMail = String.format(
                "Hola!\n\nHemos recibido una solicitud para restablecer tu contraseña en Huellitas Inteligentes.\n\nHaz clic en el siguiente enlace para ingresar tu nueva contraseña (válido por 30 minutos):\n\n%s\n\nSi no realizaste esta solicitud, puedes ignorar este mensaje.",
                resetLink
            );

            try {
                mailService.sendPasswordResetEmail(mail.trim(), rawToken);
            } catch (Exception e) {
                log.error("[SOLICITAR RESET] Error al enviar email a " + mail, e);
            }

            return ResponseEntity.ok(Map.of("ok", true, "message", "Se han enviado las instrucciones a tu correo electrónico."));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("ok", false, "error", e.getMessage()));
        }
    }

    /**
     * Completa el flujo de recuperación de contraseña validando el token
     * recibido por correo y asignando la nueva contraseña.
     *
     * @param token token de restablecimiento recibido en el enlace de correo (opcional si viene en {@code body}).
     * @param nuevaPassword nueva contraseña a asignar (opcional si viene en {@code body}).
     * @param body cuerpo JSON alternativo que puede contener {@code token} y {@code nuevaPassword}.
     * @return confirmación del cambio, o un error si el token es inválido/expiró o la contraseña no cumple los requisitos mínimos.
     */
    @PostMapping(value = "/resetear-password", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> resetearPassword(
            @RequestParam(required = false) String token,
            @RequestParam(required = false) String nuevaPassword,
            @RequestBody(required = false) Map<String, String> body) {
        String tok = token != null ? token : (body != null ? body.get("token") : null);
        String pass = nuevaPassword != null ? nuevaPassword : (body != null ? body.get("nuevaPassword") : null);

        if (tok == null || pass == null) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "Token inválido o contraseña vacía"));
        }
        
        try {
            ValidationUtils.validarPassword(pass.trim());
        } catch (Exception e) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "Token inválido o contraseña menor a 6 caracteres"));
        }

        try {
            String tokenHash = sha256(tok.trim());
            String resJson = repo.resetearPassword(tokenHash, pass.trim());
            return ResponseEntity.ok(Map.of("ok", true, "message", "Contraseña restablecida con éxito.", "data", resJson));
        } catch (Exception e) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "El enlace de recuperación es inválido o ya expiro."));
        }
    }

    // ─────────────────────────────────────────────────────────
    //  HELPERS
    // ─────────────────────────────────────────────────────────

    private String encode(String s) {
        return URLEncoder.encode(s != null ? s : "", StandardCharsets.UTF_8);
    }

    private String sha256(String input) {
        return CryptoUtils.sha256(input);
    }

    private Long extractUserIdFromAuthHeader(String authHeader) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) return null;
        try {
            String token = authHeader.replace("Bearer ", "");
            String[] parts = token.split("\\.");
            String payload = new String(java.util.Base64.getUrlDecoder().decode(parts[1]));
            if (payload.contains("\"usuario_id\":")) {
                return Long.parseLong(payload.split("\"usuario_id\":")[1].split("[,}]")[0].replaceAll("[^0-9]", ""));
            } else if (payload.contains("\"id\":")) {
                return Long.parseLong(payload.split("\"id\":")[1].split("[,}]")[0].replaceAll("[^0-9]", ""));
            } else if (payload.contains("\"sub\":")) {
                return Long.parseLong(payload.split("\"sub\":")[1].split("[,}]")[0].replaceAll("[^0-9]", ""));
            }
        } catch (Exception ignored) {}
        return null;
    }

    private Long extractUserIdFromJson(String json) {
        if (json == null) return null;
        String key = "\"id\":";
        int start = json.indexOf(key);
        if (start < 0) return null;
        start += key.length();
        int end = json.indexOf(",", start);
        if (end < 0) end = json.indexOf("}", start);
        if (end > start) {
            try {
                return Long.parseLong(json.substring(start, end).trim());
            } catch (Exception e) {
                return null;
            }
        }
        return null;
    }
}
