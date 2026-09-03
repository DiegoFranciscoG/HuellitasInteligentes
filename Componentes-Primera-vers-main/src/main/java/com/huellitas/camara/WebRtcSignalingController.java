package com.huellitas.camara;

import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;

import java.security.Principal;

/**
 * Retransmite los mensajes de señalización WebRTC entre el visor de video y
 * la cámara emisora a través de STOMP, sin intervenir en el contenido del
 * mensaje: simplemente lo enruta al destinatario indicado.
 */
@Controller
public class WebRtcSignalingController {

    private final SimpMessagingTemplate messagingTemplate;

    public WebRtcSignalingController(SimpMessagingTemplate messagingTemplate) {
        this.messagingTemplate = messagingTemplate;
    }

    /**
     * Reenvía un mensaje de señalización WebRTC al tópico STOMP del destinatario indicado.
     *
     * @param message mensaje de señalización con el destinatario ({@code target}), el emisor ({@code from}) y el contenido (oferta/respuesta/candidato).
     */
    @MessageMapping("/webrtc/signal")
    public void handleWebRtcSignal(@Payload WebRtcMessage message) {
        if (message.getTarget() == null || message.getFrom() == null) {
            return;
        }

        // Route the STOMP message to the specific target user's topic
        // STOMP destination: /topic/webrtc/{target}
        messagingTemplate.convertAndSend(
                "/topic/webrtc/" + message.getTarget(),
                message
        );
    }
}
