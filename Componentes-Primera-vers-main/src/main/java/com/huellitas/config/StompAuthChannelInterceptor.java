package com.huellitas.config;

import com.huellitas.auth.JwtUtil;
import io.jsonwebtoken.Claims;
import org.springframework.lang.NonNull;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.stereotype.Component;

/**
 * Valida (con firma) el JWT enviado en la cabecera STOMP {@code Authorization}
 * al conectar, y si es genuino, deja la identidad real del usuario disponible
 * como {@link java.security.Principal} para los métodos {@code @MessageMapping}
 * durante toda la sesión WebSocket — así dejan de tener que confiar en el
 * {@code emisorId}/{@code from} que manda el propio cliente en el payload.
 *
 * <p>Deliberadamente NO rechaza la conexión si falta el token o es inválido:
 * el cliente sigue conectando sin identidad verificada (como antes de este
 * cambio), y cada {@code @MessageMapping} decide si exige esa identidad o
 * sigue aceptando el valor del payload como respaldo. Esto evita romper
 * clientes (por ejemplo, la app Flutter) que todavía no envían el token en
 * el CONNECT.</p>
 */
@Component
public class StompAuthChannelInterceptor implements ChannelInterceptor {

    private final JwtUtil jwtUtil;

    public StompAuthChannelInterceptor(JwtUtil jwtUtil) {
        this.jwtUtil = jwtUtil;
    }

    @Override
    public Message<?> preSend(@NonNull Message<?> message, @NonNull MessageChannel channel) {
        StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);
        if (accessor != null && StompCommand.CONNECT.equals(accessor.getCommand())) {
            String authHeader = accessor.getFirstNativeHeader("Authorization");
            Claims claims = jwtUtil.validarYObtenerClaims(authHeader);
            if (claims != null) {
                Object usuarioId = claims.get("usuario_id");
                if (usuarioId != null) {
                    String usuarioIdStr = String.valueOf(usuarioId);
                    accessor.setUser(() -> usuarioIdStr);
                }
            }
        }
        return message;
    }
}
