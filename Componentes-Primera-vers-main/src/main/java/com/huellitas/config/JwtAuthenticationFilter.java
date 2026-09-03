package com.huellitas.config;

import com.huellitas.auth.JwtUtil;
import io.jsonwebtoken.Claims;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * Valida (con firma) el JWT enviado en el encabezado {@code Authorization},
 * y si es genuino, registra al usuario autenticado en el contexto de
 * seguridad de Spring con su rol como authority ({@code ROLE_<rol>}) — así
 * {@code @PreAuthorize}/{@code hasRole(...)} pueden usarlo.
 *
 * <p>La identidad y el rol salen del token, que va firmado. La vivienda, en
 * cambio, se resuelve contra la base en {@link AuthContext#casaIdActual()} y
 * no se toma de aquí: un JWT dura horas, así que confiar en el
 * {@code casa_id} que lleva dentro dejaba una ventana en la que un miembro
 * dado de baja seguía entrando al hogar del que ya había salido.</p>
 *
 * <p>Si el token falta o es inválido, la petición sigue sin autenticar: la
 * mayoría de rutas de la API siguen siendo públicas hoy (ver
 * {@link SecurityConfig}), este filtro solo prepara la identidad para las
 * rutas que sí la exigen.</p>
 */
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtUtil jwtUtil;

    public JwtAuthenticationFilter(JwtUtil jwtUtil) {
        this.jwtUtil = jwtUtil;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String authHeader = request.getHeader("Authorization");
        Claims claims = jwtUtil.validarYObtenerClaims(authHeader);

        // Diagnóstico temporal: cuando una ruta /auth/** que exige sesión
        // recibe un token que no pasa la validación, no había forma de saber
        // si el problema era "no llegó cabecera" o "llegó pero es inválido".
        // No imprime el token completo, solo si estaba presente y su prefijo.
        if (claims == null && request.getRequestURI().contains("/api/huellitas/auth/")) {
            String prefijo = authHeader == null ? "(sin cabecera)"
                : authHeader.length() > 20 ? authHeader.substring(0, 20) + "..." : authHeader;
            System.out.println("🔒 JWT rechazado en " + request.getMethod() + " " + request.getRequestURI() + " · Authorization=" + prefijo);
        }

        if (claims != null && SecurityContextHolder.getContext().getAuthentication() == null) {
            Object usuarioId = claims.get("usuario_id");
            String rol = claims.get("rol", String.class);
            Number casaIdClaim = claims.get("casa_id", Number.class);
            Long casaId = casaIdClaim != null ? casaIdClaim.longValue() : null;
            List<SimpleGrantedAuthority> authorities = rol != null
                ? List.of(new SimpleGrantedAuthority("ROLE_" + rol))
                : List.of();

            var authentication = new UsernamePasswordAuthenticationToken(usuarioId, casaId, authorities);
            SecurityContextHolder.getContext().setAuthentication(authentication);
        }

        filterChain.doFilter(request, response);
    }
}
