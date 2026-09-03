package com.huellitas.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

/**
 * Configuración de seguridad única — OAuth2 auto-configuración está excluida
 * en application.properties, así que esta es la ÚNICA cadena activa.
 *
 * <p>Casi toda la API exige ahora un JWT válido (firma verificada, no solo
 * decodificado) y cada controlador toma la identidad del usuario/casa desde
 * el token (vía {@link AuthContext}), nunca de un {@code usuarioId}/{@code casaId}
 * que mande el propio cliente — antes cualquiera podía publicar, editar o
 * borrar contenido "como" otro usuario con solo cambiar ese valor en la
 * petición. Las rutas administrativas y algunas sub-rutas puntuales
 * ({@code /social/strike}, {@code /ia/admin/**}, {@code /moderacion/admin/**})
 * exigen además el rol {@code ADMINISTRADOR}.</p>
 *
 * <p>Quedan públicas, por diseño, solo las rutas que deben poder llamarse
 * sin sesión: login/registro/OAuth/recuperación de contraseña, el canje de
 * QR de acceso, la vinculación de una cámara nueva desde el propio
 * dispositivo, las estadísticas agregadas de la landing y los endpoints de
 * dispositivos ESP32 (que viven bajo {@code /api/devices}, {@code /api/dht},
 * etc. — un prefijo totalmente distinto, fuera del alcance de esta clase).
 * Las señales WebSocket de chat/videollamada (STOMP) todavía no pasan por
 * este filtro HTTP — es un mecanismo de seguridad aparte, pendiente.</p>
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Value("${app.cors.allowed-origins:http://localhost:4200,http://localhost:4000}")
    private String allowedOrigins;

    private final RateLimitFilter rateLimitFilter;
    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final DeviceTokenFilter deviceTokenFilter;

    public SecurityConfig(RateLimitFilter rateLimitFilter,
                          JwtAuthenticationFilter jwtAuthenticationFilter,
                          DeviceTokenFilter deviceTokenFilter) {
        this.rateLimitFilter = rateLimitFilter;
        this.jwtAuthenticationFilter = jwtAuthenticationFilter;
        this.deviceTokenFilter = deviceTokenFilter;
    }

    /**
     * Define qué orígenes, métodos y encabezados HTTP puede usar el frontend
     * (web/app) al llamar a la API, según la lista configurada en {@code app.cors.allowed-origins}.
     *
     * @return la configuración CORS aplicada a todas las rutas.
     */
    @Bean
    CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        List<String> origins = Arrays.asList(allowedOrigins.split(","));
        config.setAllowedOrigins(origins);
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("*"));
        config.setAllowCredentials(true);
        config.setMaxAge(3600L);
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }

    /**
     * Configura la cadena de filtros de seguridad HTTP: aplica CORS, desactiva CSRF (API sin sesiones de navegador),
     * exige un JWT válido con rol ADMINISTRADOR para las rutas de administración y permite el resto sin
     * autenticación de Spring Security por ahora, y desactiva sesiones de servidor y los formularios de login
     * por defecto.
     *
     * @param http constructor de configuración de seguridad HTTP de Spring.
     * @return la cadena de filtros de seguridad resultante.
     * @throws Exception si ocurre un error al construir la configuración.
     */
    @Bean
    SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .csrf(csrf -> csrf.disable())
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/huellitas/admin/**").hasRole("ADMINISTRADOR")
                .requestMatchers("/api/huellitas/social/testimonios-publicos").permitAll()
                .requestMatchers("/api/huellitas/social/strike").hasRole("ADMINISTRADOR")
                .requestMatchers("/api/huellitas/social/**").authenticated()
                .requestMatchers("/api/huellitas/reacciones/**").authenticated()
                .requestMatchers("/api/huellitas/chat/**").authenticated()
                .requestMatchers("/api/huellitas/camaras/vincular").permitAll()
                .requestMatchers("/api/huellitas/camaras/**").authenticated()
                .requestMatchers("/api/huellitas/casa/estadisticas-publicas").permitAll()
                .requestMatchers("/api/huellitas/casa/**").authenticated()
                .requestMatchers("/api/huellitas/pagos/**").authenticated()
                .requestMatchers("/api/huellitas/planes/**").authenticated()
                // El latido lo manda el firmware del ESP32, que no tiene
                // sesión de usuario. Va antes de la regla general para que no
                // quede detrás de authenticated().
                .requestMatchers("/api/huellitas/dispositivo/latido").permitAll()
                // El endpoint de subida de foto por parte de la camara no lleva
                // JWT — lo protege el X-Device-Code validado por DeviceTokenFilter.
                .requestMatchers("/api/huellitas/camara/momento/**", "/api/huellitas/camara/momento").permitAll()
                .requestMatchers("/api/huellitas/dispositivo/**").authenticated()
                .requestMatchers("/api/huellitas/alerta/**").authenticated()
                .requestMatchers("/api/huellitas/notificaciones/**").authenticated()
                .requestMatchers("/api/huellitas/historial/**").authenticated()
                .requestMatchers("/api/huellitas/perro/**").authenticated()
                .requestMatchers("/api/huellitas/ia/admin/**").hasRole("ADMINISTRADOR")
                .requestMatchers("/api/huellitas/ia/**").authenticated()
                .requestMatchers("/api/huellitas/moderacion/admin/**").hasRole("ADMINISTRADOR")
                .requestMatchers("/api/huellitas/moderacion/**").authenticated()
                // Momentos: lectura y guardado requieren sesión.
                .requestMatchers("/api/huellitas/momentos/**").authenticated()
                // Media: las imágenes se cargan desde <img> sin JWT — deben ser públicas.
                .requestMatchers("/api/huellitas/media/**").permitAll()
                .requestMatchers(
                    "/api/huellitas/auth/registro-propietario",
                    "/api/huellitas/auth/login",
                    "/api/huellitas/auth/verificar-codigo",
                    "/api/huellitas/auth/reenviar-codigo",
                    "/api/huellitas/auth/google/**",
                    "/api/huellitas/auth/facebook/**",
                    "/api/huellitas/auth/solicitar-reset",
                    "/api/huellitas/auth/resetear-password",
                    "/api/huellitas/auth/qr/validar"
                ).permitAll()
                .requestMatchers("/api/huellitas/auth/**").authenticated()
                .requestMatchers("/api/huellitas/_debug/**").hasRole("ADMINISTRADOR")
                // Rutas del firmware ESP32 (prefijo /api/ sin /api/huellitas/).
                // El DeviceTokenFilter las protege con X-Device-Token; aquí solo
                // se declaran como permitidas para que denyAll() no las bloquee.
                .requestMatchers("/api/**").permitAll()
                // Recursos estaticos servidos por Spring Boot (Angular, APK, etc.)
                .requestMatchers(
                    "/",
                    "/index.html",
                    "/*.js",
                    "/*.css",
                    "/*.ico",
                    "/*.txt",
                    "/assets/**",
                    "/media/**",
                    "/huellitas.apk"
                ).permitAll()
                // Permitir cualquier ruta del frontend Angular para que caiga en index.html
                // (excepto las que empiezan con /api/ o /actuator/)
                .requestMatchers(request -> {
                    String path = request.getServletPath();
                    return !path.startsWith("/api/") && !path.startsWith("/actuator/");
                }).permitAll()
                // Actuator de salud
                .requestMatchers("/actuator/health").permitAll()
                // Cualquier otra ruta nace CERRADA. Así una ruta nueva no queda
                // accesible por accidente si se olvida declararla aquí.
                .anyRequest().denyAll())
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .formLogin(f -> f.disable())
            .httpBasic(b -> b.disable())
            .exceptionHandling(e -> e
                .authenticationEntryPoint((request, response, ex) -> escribirErrorJson(response, 401, "Debes iniciar sesión para acceder a este recurso."))
                .accessDeniedHandler((request, response, ex) -> escribirErrorJson(response, 403, "No cuentas con permisos suficientes para acceder a este recurso.")))
            .addFilterBefore(rateLimitFilter, UsernamePasswordAuthenticationFilter.class)
            .addFilterAfter(jwtAuthenticationFilter, RateLimitFilter.class)
            .addFilterAfter(deviceTokenFilter, JwtAuthenticationFilter.class);
        return http.build();
    }

    private static void escribirErrorJson(jakarta.servlet.http.HttpServletResponse response, int status, String mensaje) throws IOException {
        response.setStatus(status);
        response.setContentType("application/json;charset=UTF-8");
        response.getWriter().write(new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(Map.of(
            "ok", false,
            "error", mensaje,
            "message", mensaje
        )));
    }
}
