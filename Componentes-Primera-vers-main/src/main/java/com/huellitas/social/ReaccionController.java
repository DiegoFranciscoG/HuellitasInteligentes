package com.huellitas.social;

import com.huellitas.config.AuthContext;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * Gestiona las reacciones (por ejemplo, "me gusta") que los usuarios dejan
 * sobre publicaciones, comentarios, mensajes de chat directo y mensajes de
 * salas de chat grupales.
 */
@RestController
@RequestMapping("/api/huellitas/reacciones")
@CrossOrigin("*")
public class ReaccionController {

    private final ReaccionService reaccionService;
    private final AuthContext authContext;
    private final JdbcTemplate jdbcTemplate;

    public ReaccionController(ReaccionService reaccionService, AuthContext authContext, JdbcTemplate jdbcTemplate) {
        this.reaccionService = reaccionService;
        this.authContext = authContext;
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * Agrega o quita una reacción de un usuario sobre una publicación.
     *
     * @param id identificador de la publicación.
     * @param usuarioId identificador del usuario que reacciona.
     * @param tipo tipo de reacción (por ejemplo, "like").
     * @param quitar si es {@code true}, quita la reacción en vez de agregarla.
     * @return confirmación de la operación.
     */
    @PostMapping("/publicacion/{id}")
    public ResponseEntity<?> reaccionarPublicacion(
            @PathVariable Long id,
            @RequestParam(required = false) Long usuarioId,
            @RequestParam String tipo,
            @RequestParam(defaultValue = "false") boolean quitar) {
        usuarioId = authContext.usuarioIdActual();
        if (quitar) {
            reaccionService.quitarReaccionPublicacion(id, usuarioId, tipo);
        } else {
            reaccionService.reaccionarPublicacion(id, usuarioId, tipo);
        }
        return ResponseEntity.ok(Map.of("ok", true));
    }

    /**
     * Agrega o quita una reacción de un usuario sobre un comentario.
     *
     * @param id identificador del comentario.
     * @param usuarioId identificador del usuario que reacciona.
     * @param tipo tipo de reacción.
     * @param quitar si es {@code true}, quita la reacción en vez de agregarla.
     * @return confirmación de la operación.
     */
    @PostMapping("/comentario/{id}")
    public ResponseEntity<?> reaccionarComentario(
            @PathVariable Long id,
            @RequestParam(required = false) Long usuarioId,
            @RequestParam String tipo,
            @RequestParam(defaultValue = "false") boolean quitar) {
        usuarioId = authContext.usuarioIdActual();
        if (quitar) {
            reaccionService.quitarReaccionComentario(id, usuarioId, tipo);
        } else {
            reaccionService.reaccionarComentario(id, usuarioId, tipo);
        }
        return ResponseEntity.ok(Map.of("ok", true));
    }

    /**
     * Agrega o quita una reacción de un usuario sobre un mensaje de chat directo.
     *
     * @param id identificador del mensaje.
     * @param usuarioId identificador del usuario que reacciona.
     * @param tipo tipo de reacción.
     * @param quitar si es {@code true}, quita la reacción en vez de agregarla.
     * @return confirmación de la operación.
     */
    @PostMapping("/chat/{id}")
    public ResponseEntity<?> reaccionarChat(
            @PathVariable Long id,
            @RequestParam(required = false) Long usuarioId,
            @RequestParam String tipo,
            @RequestParam(defaultValue = "false") boolean quitar) {
        usuarioId = authContext.usuarioIdActual();
        Boolean esParte = jdbcTemplate.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM mensaje WHERE id = ? AND (emisor_id = ? OR receptor_id = ?))",
            Boolean.class, id, usuarioId, usuarioId);
        if (esParte == null || !esParte) {
            return ResponseEntity.status(403).body(Map.of("ok", false, "error", "No tienes acceso a este mensaje"));
        }
        if (quitar) {
            reaccionService.quitarReaccionChat(id, usuarioId, tipo);
        } else {
            reaccionService.reaccionarChat(id, usuarioId, tipo);
        }
        return ResponseEntity.ok(Map.of("ok", true));
    }

    /**
     * Agrega o quita una reacción de un usuario sobre un mensaje de una sala de chat grupal.
     *
     * @param id identificador del mensaje de la sala.
     * @param usuarioId identificador del usuario que reacciona.
     * @param tipo tipo de reacción.
     * @param quitar si es {@code true}, quita la reacción en vez de agregarla.
     * @return confirmación de la operación.
     */
    @PostMapping("/chat-sala/{id}")
    public ResponseEntity<?> reaccionarChatSala(
            @PathVariable Long id,
            @RequestParam(required = false) Long usuarioId,
            @RequestParam String tipo,
            @RequestParam(defaultValue = "false") boolean quitar) {
        usuarioId = authContext.usuarioIdActual();
        Boolean esMiembro = jdbcTemplate.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM chat_sala_mensaje m JOIN chat_sala_miembro csm ON csm.sala_id = m.sala_id " +
            "WHERE m.id = ? AND csm.usuario_id = ?)",
            Boolean.class, id, usuarioId);
        if (esMiembro == null || !esMiembro) {
            return ResponseEntity.status(403).body(Map.of("ok", false, "error", "No eres miembro de esta sala"));
        }
        if (quitar) {
            reaccionService.quitarReaccionChatSala(id, usuarioId, tipo);
        } else {
            reaccionService.reaccionarChatSala(id, usuarioId, tipo);
        }
        return ResponseEntity.ok(Map.of("ok", true));
    }
}
