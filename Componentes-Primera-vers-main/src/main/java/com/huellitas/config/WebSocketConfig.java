package com.huellitas.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

/**
 * Habilita la mensajería en tiempo real (WebSocket/STOMP) usada por el chat,
 * las notificaciones instantáneas y la señalización de video WebRTC entre cámaras y visores.
 */
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    private final StompAuthChannelInterceptor stompAuthChannelInterceptor;

    public WebSocketConfig(StompAuthChannelInterceptor stompAuthChannelInterceptor) {
        this.stompAuthChannelInterceptor = stompAuthChannelInterceptor;
    }

    /**
     * Registra el interceptor que valida el JWT enviado al conectar (ver
     * {@link StompAuthChannelInterceptor}), dejando la identidad real del
     * usuario disponible para los {@code @MessageMapping} durante toda la sesión.
     *
     * @param registration registro de configuración del canal de entrada de mensajes STOMP.
     */
    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(stompAuthChannelInterceptor);
    }

    /**
     * Configura el broker de mensajes: habilita los destinos {@code /topic} y
     * {@code /queue} para difusión, {@code /app} como prefijo de los mensajes
     * entrantes de los clientes, y {@code /user} para mensajes dirigidos a un usuario concreto.
     *
     * @param config registro de configuración del broker de mensajes.
     */
    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.enableSimpleBroker("/topic", "/queue");
        config.setApplicationDestinationPrefixes("/app");
        config.setUserDestinationPrefix("/user");
    }

    /**
     * Registra el endpoint {@code /ws} por el que los clientes abren la
     * conexión WebSocket, con SockJS como respaldo para navegadores/redes que no soporten WebSocket nativo.
     *
     * @param registry registro de endpoints STOMP.
     */
    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws")
                .setAllowedOriginPatterns("*")
                .withSockJS();
    }
}
