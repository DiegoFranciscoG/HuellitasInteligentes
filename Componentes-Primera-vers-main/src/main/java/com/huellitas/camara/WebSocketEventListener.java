package com.huellitas.camara;

import org.springframework.context.event.EventListener;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.messaging.SessionDisconnectEvent;
import org.springframework.web.socket.messaging.SessionSubscribeEvent;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Mantiene actualizado el estado "conectada" de cada {@link Camara} en la
 * base de datos según las suscripciones y desconexiones WebSocket a su
 * tópico de streaming, para que la interfaz sepa en tiempo real si una
 * cámara está transmitiendo.
 */
@Component
public class WebSocketEventListener {

    private final CamaraRepository camaraRepository;

    // session_id -> urlStream
    private final Map<String, String> sessionCameraMap = new ConcurrentHashMap<>();

    public WebSocketEventListener(CamaraRepository camaraRepository) {
        this.camaraRepository = camaraRepository;
    }

    /**
     * Marca como conectada a la cámara correspondiente cuando alguien se
     * suscribe a su tópico de señalización WebRTC ({@code /topic/webrtc/webrtc:...}).
     *
     * @param event evento de suscripción STOMP.
     */
    @EventListener
    @Transactional
    public void handleSessionSubscribeEvent(SessionSubscribeEvent event) {
        StompHeaderAccessor headerAccessor = StompHeaderAccessor.wrap(event.getMessage());
        String sessionId = headerAccessor.getSessionId();
        String destination = headerAccessor.getDestination();

        if (sessionId != null && destination != null && destination.startsWith("/topic/webrtc/webrtc:")) {
            String urlStream = destination.substring("/topic/webrtc/".length());
            
            // Only mark as connected if a camera actually matches this urlStream
            List<Camara> camaras = camaraRepository.findByUrlStream(urlStream);
            if (!camaras.isEmpty()) {
                sessionCameraMap.put(sessionId, urlStream);
                for (Camara c : camaras) {
                    c.setConectada(true);
                    camaraRepository.save(c);
                }
            }
        }
    }

    /**
     * Marca como desconectada a la cámara correspondiente cuando la sesión
     * WebSocket que la transmitía se cierra.
     *
     * @param event evento de desconexión WebSocket.
     */
    @EventListener
    @Transactional
    public void handleSessionDisconnectEvent(SessionDisconnectEvent event) {
        StompHeaderAccessor headerAccessor = StompHeaderAccessor.wrap(event.getMessage());
        String sessionId = headerAccessor.getSessionId();

        if (sessionId != null && sessionCameraMap.containsKey(sessionId)) {
            String urlStream = sessionCameraMap.remove(sessionId);
            List<Camara> camaras = camaraRepository.findByUrlStream(urlStream);
            for (Camara c : camaras) {
                c.setConectada(false);
                camaraRepository.save(c);
            }
        }
    }
}
