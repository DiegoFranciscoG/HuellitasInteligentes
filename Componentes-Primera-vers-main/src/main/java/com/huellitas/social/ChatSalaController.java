package com.huellitas.social;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.*;
import com.huellitas.config.AuthContext;
import com.huellitas.ia.ModeracionService;
import com.huellitas.social.SocialRepository;

/**
 * Maneja REST para CRUD de salas y WebSocket para mensajes por sala.
 * Canal WebSocket por sala: /app/sala/{salaId} → /topic/sala/{salaId}
 */
@Controller
@RestController
@RequestMapping("/api/huellitas/chat")
public class ChatSalaController {
    private final ChatSalaRepository salaRepo;
    private final SimpMessagingTemplate messaging;
    private final ModeracionService moderacionService;
    private final SocialRepository socialRepo;
    private final org.springframework.jdbc.core.JdbcTemplate jdbcTemplate;
    private final AuthContext authContext;

    public ChatSalaController(ChatSalaRepository salaRepo, SimpMessagingTemplate messaging, ModeracionService moderacionService, SocialRepository socialRepo, org.springframework.jdbc.core.JdbcTemplate jdbcTemplate, AuthContext authContext) {
        this.salaRepo = salaRepo;
        this.messaging = messaging;
        this.moderacionService = moderacionService;
        this.socialRepo = socialRepo;
        this.jdbcTemplate = jdbcTemplate;
        this.authContext = authContext;
    }

    // ── REST ──────────────────────────────────────────────────────────────

    /**
     * Lista las salas de chat grupal a las que pertenece un usuario.
     *
     * @param usuarioId identificador del usuario.
     * @return un JSON (como texto) con las salas del usuario.
     */
    @GetMapping(value = "/salas", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarSalas(@RequestParam(required = false) Long usuarioId) {
        return ResponseEntity.ok(salaRepo.listarSalas(authContext.usuarioIdActual()));
    }

    /**
     * Crea una nueva sala de chat grupal sobre un tema.
     *
     * @param usuarioId identificador del usuario creador.
     * @param tema tema de la sala.
     * @param descripcion descripción de la sala (opcional).
     * @return los datos de la sala creada en formato JSON.
     */
    @PostMapping(value = "/salas", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> crearSala(
            @RequestParam(required = false) Long usuarioId,
            @RequestParam String tema,
            @RequestParam(required = false) String descripcion) {
        return ResponseEntity.ok(salaRepo.crearSala(authContext.usuarioIdActual(), tema, descripcion));
    }

    /**
     * Agrega a un usuario como miembro de una sala de chat grupal.
     *
     * @param salaId identificador de la sala.
     * @param usuarioId identificador del usuario que se une.
     * @return el resultado de la operación en formato JSON.
     */
    @PostMapping(value = "/salas/{salaId}/unirse", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> unirseSala(
            @PathVariable Long salaId,
            @RequestParam(required = false) Long usuarioId) {
        return ResponseEntity.ok(salaRepo.unirseSala(salaId, authContext.usuarioIdActual()));
    }

    /**
     * Obtiene el historial de mensajes de una sala de chat grupal. Solo
     * accesible para quien ya es miembro de esa sala.
     *
     * @param salaId identificador de la sala.
     * @param limite cantidad máxima de mensajes a devolver.
     * @return un JSON (como texto) con los mensajes de la sala, o 403 si el usuario no es miembro.
     */
    @GetMapping(value = "/salas/{salaId}/mensajes", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> mensajesSala(
            @PathVariable Long salaId,
            @RequestParam(defaultValue = "50") Integer limite) {
        Boolean esMiembro = jdbcTemplate.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM chat_sala_miembro WHERE sala_id = ? AND usuario_id = ?)",
            Boolean.class, salaId, authContext.usuarioIdActual());
        if (esMiembro == null || !esMiembro) {
            return ResponseEntity.status(403).body("{\"ok\":false,\"error\":\"No eres miembro de esta sala\"}");
        }
        return ResponseEntity.ok(salaRepo.mensajesSala(salaId, limite));
    }

    // ── WebSocket ─────────────────────────────────────────────────────────

    /** Mensaje enviado o recibido en el canal WebSocket de una sala de chat grupal. */
    public static class SalaMensaje {
        public Long id;
        public Long salaId;
        public Long emisorId;
        public String emisorNombre;
        public String contenido;
        public String fecha;
    }

    /** Mensaje de señalización WebRTC para las videollamadas dentro de una sala de chat. */
    public static class WebRTCSignal {
        public Long salaId;
        public Long emisorId;
        public String tipo; // "offer", "answer", "ice-candidate", "join-call", "leave-call"
        public Object payload; // El objeto SDP o ICE Candidate real
    }

    /**
     * Frontend publica a /app/sala/{salaId}
     * Backend rebroadcast a /topic/sala/{salaId} — solo miembros suscritos reciben.
     * El mensaje se persiste primero para poder difundirlo con su id
     * definitivo, y luego se evalúa de forma asíncrona con
     * {@link ModeracionService}: si se bloquea, se borra retroactivamente y
     * se avisa al autor y a los suscriptores.
     *
     * @param salaId identificador de la sala (tomado de la ruta del destino).
     * @param msg mensaje enviado por el cliente.
     */
    @MessageMapping("/sala/{salaId}")
    public void mensajeSala(@DestinationVariable Long salaId, @Payload SalaMensaje msg, java.security.Principal principal) {
        msg.salaId = salaId;
        // Si el cliente autenticó el WebSocket (envio el JWT al conectar),
        // la identidad real del token manda sobre lo que diga el payload.
        // Los clientes que todavia no envian el token siguen funcionando
        // con el emisorId que ya mandaban antes de este cambio.
        if (principal != null) {
            try {
                msg.emisorId = Long.valueOf(principal.getName());
            } catch (NumberFormatException ignored) {
                // Principal con formato inesperado: se mantiene el emisorId del payload.
            }
        }
        if (msg.fecha == null) {
            msg.fecha = java.time.Instant.now().toString();
        }

        // Persistir en BD primero para envío inmediato
        try {
            String result = salaRepo.guardarMensajeSala(salaId, msg.emisorId, msg.contenido);
            if (result != null && result.contains("\"id\":")) {
                int idIdx = result.indexOf("\"id\":") + 5;
                int endIdx = result.indexOf(",", idIdx);
                if (endIdx == -1) endIdx = result.indexOf("}", idIdx);
                if (endIdx != -1) {
                    msg.id = Long.parseLong(result.substring(idIdx, endIdx).trim());
                }
            }
        } catch (Exception e) {
            System.err.println("[Chat] Error guardando mensaje en sala " + salaId + ": " + e.getMessage());
            // No transmitir un mensaje que no se pudo guardar: aparecería como
            // enviado para todos en la sala pero desaparecería al recargar,
            // porque nunca quedó en la base de datos.
            return;
        }

        // Broadcast solo a miembros suscritos al canal de esta sala
        messaging.convertAndSend("/topic/sala/" + salaId, msg);

        // Moderación Asíncrona en background
        if (msg.id != null) {
            java.util.concurrent.CompletableFuture.runAsync(() -> {
                var modRes = moderacionService.moderarContenido(msg.contenido, null);
                if (modRes.bloquear()) {
                    socialRepo.sistemaDarStrike(msg.emisorId, "Chat bloqueado: " + modRes.motivo());
                    try {
                        // Eliminar retroactivamente el mensaje de la BD
                        jdbcTemplate.update("DELETE FROM mensaje_sala WHERE id = ?", msg.id);
                        
                        // Notificar al usuario por qué se borró
                        String aviso = "Tu mensaje en el chat fue eliminado por incumplir las normas de la comunidad: " + modRes.motivo();
                        jdbcTemplate.update(
                            "INSERT INTO notificacion (usuario_id, canal, contenido, estado, enviado_at) VALUES (?, 'INAPP'::canal_notificacion, ?, 'PENDIENTE'::estado_notificacion, NOW())",
                            msg.emisorId, aviso
                        );
                        
                        // Enviar señal especial por WS para que el frontend quite el mensaje si quiere
                        msg.contenido = "[Mensaje eliminado por moderación]";
                        messaging.convertAndSend("/topic/sala/" + salaId + "/deleted", msg.id);
                    } catch (Exception e) {
                        System.err.println("[Moderación] Error eliminando mensaje bloqueado retroactivamente: " + e.getMessage());
                    }
                }
            });
        }
    }

    /**
     * Señalización WebRTC para videollamadas 1:1 en la sala.
     * No se persiste en base de datos, solo se retransmite.
     *
     * @param salaId identificador de la sala (tomado de la ruta del destino).
     * @param signal señal WebRTC (oferta, respuesta, candidato ICE, unión o salida de la llamada).
     */
    @MessageMapping("/sala/{salaId}/webrtc")
    public void senalizacionWebRTC(@DestinationVariable Long salaId, @Payload WebRTCSignal signal) {
        signal.salaId = salaId;
        // Retransmitir la señal al canal WebRTC de la sala
        messaging.convertAndSend("/topic/sala/" + salaId + "/webrtc", signal);
    }
}
