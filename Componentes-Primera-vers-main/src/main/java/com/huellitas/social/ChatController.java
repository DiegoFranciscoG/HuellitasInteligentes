package com.huellitas.social;

import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;
import com.huellitas.ia.ModeracionService;
import com.huellitas.social.SocialRepository;

import java.security.Principal;

/**
 * Maneja mensajes WebSocket STOMP del chat.
 * Canal global: /app/chat-global → broadcast a /topic/chat-global
 * Todos los usuarios suscritos reciben el mensaje.
 */
@Controller
public class ChatController {

    private final SimpMessagingTemplate messagingTemplate;
    private final ModeracionService moderacionService;
    private final SocialRepository socialRepo;

    public ChatController(SimpMessagingTemplate messagingTemplate, ModeracionService moderacionService, SocialRepository socialRepo) {
        this.messagingTemplate = messagingTemplate;
        this.moderacionService = moderacionService;
        this.socialRepo = socialRepo;
    }

    /**
     * Payload que llega desde el cliente Angular.
     */
    public static class ChatMessage {
        public Long emisorId;
        public String emisorNombre;
        public String contenido;
        public String fecha;
    }

    /**
     * Canal global de chat de comunidad.
     * Frontend publica a: /app/chat-global
     * Backend rebroadcast a: /topic/chat-global
     * Todos los clientes suscritos a /topic/chat-global reciben el mensaje.
     */
    @MessageMapping("/chat-global")
    public void chatGlobal(@Payload ChatMessage chatMessage, Principal principal) {
        // Si el cliente autenticó el WebSocket (envio el JWT al conectar),
        // la identidad real del token manda sobre lo que diga el payload —
        // evita que alguien publique haciendose pasar por otro usuario.
        // Los clientes que todavia no envian el token (ver StompAuthChannelInterceptor)
        // siguen funcionando con el emisorId que ya mandaban antes de este cambio.
        if (principal != null) {
            try {
                chatMessage.emisorId = Long.valueOf(principal.getName());
            } catch (NumberFormatException ignored) {
                // Principal con formato inesperado: se mantiene el emisorId del payload.
            }
        }

        // Enrich: asegurar que tenga fecha
        if (chatMessage.fecha == null || chatMessage.fecha.isEmpty()) {
            chatMessage.fecha = java.time.Instant.now().toString();
        }

        // Moderación IA
        var modRes = moderacionService.moderarContenido(chatMessage.contenido, null);
        if (modRes.bloquear()) {
            socialRepo.sistemaDarStrike(chatMessage.emisorId, "Chat Global bloqueado: " + modRes.motivo());
            System.err.println("[Moderación] Mensaje bloqueado en Chat Global por usuario " + chatMessage.emisorId);
            return;
        }

        // Broadcast a todos los suscriptores del canal global
        messagingTemplate.convertAndSend("/topic/chat-global", chatMessage);
    }
}
