package com.huellitas.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.bucket4j.Bandwidth;
import io.github.bucket4j.Bucket;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Limita cuántas peticiones por minuto puede hacer una misma IP a las rutas
 * más sensibles a abuso: el login (fuerza bruta de contraseñas) y los
 * endpoints que disparan llamadas pagadas a APIs externas de IA
 * (moderación de contenido y entrenamiento RAG). El resto de la API no pasa
 * por este filtro.
 *
 * <p>El conteo vive en memoria del proceso (adecuado para una sola
 * instancia, igual que el caché de {@link CacheConfig}); si el backend
 * llega a correr en más de una instancia detrás de un balanceador, este
 * límite tendría que moverse a un almacén compartido (Redis).</p>
 */
@Component
public class RateLimitFilter extends OncePerRequestFilter {

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final Map<String, Bucket> buckets = new ConcurrentHashMap<>();

    /** Prefijo de ruta → cuántas peticiones por minuto se permiten por IP. */
    private static final Map<String, Integer> LIMITES_POR_MINUTO = new LinkedHashMap<>();
    static {
        LIMITES_POR_MINUTO.put("/api/huellitas/auth/login", 10);
        LIMITES_POR_MINUTO.put("/api/huellitas/auth/registro", 10);
        LIMITES_POR_MINUTO.put("/api/huellitas/admin/rag/", 6);
        LIMITES_POR_MINUTO.put("/api/huellitas/social/publicacion", 30);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String path = request.getRequestURI();
        Integer limite = LIMITES_POR_MINUTO.entrySet().stream()
            .filter(e -> path.startsWith(e.getKey()))
            .map(Map.Entry::getValue)
            .findFirst()
            .orElse(null);

        if (limite == null) {
            filterChain.doFilter(request, response);
            return;
        }

        String clave = clienteIp(request) + "|" + path;
        Bucket bucket = buckets.computeIfAbsent(clave, k -> Bucket.builder()
            .addLimit(Bandwidth.builder().capacity(limite).refillIntervally(limite, Duration.ofMinutes(1)).build())
            .build());

        if (bucket.tryConsume(1)) {
            filterChain.doFilter(request, response);
        } else {
            response.setStatus(429);
            response.setContentType("application/json;charset=UTF-8");
            String mensaje = "Demasiados intentos. Espera un momento antes de volver a intentarlo.";
            response.getWriter().write(objectMapper.writeValueAsString(Map.of(
                "ok", false,
                "error", mensaje,
                "message", mensaje
            )));
        }
    }

    private String clienteIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }
}
