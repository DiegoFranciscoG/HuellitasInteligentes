package com.huellitas.social;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * Registra y retira las reacciones de los usuarios sobre publicaciones,
 * comentarios y mensajes de chat (directo y en salas grupales). Cada
 * usuario solo puede tener una reacción activa por elemento: al reaccionar
 * de nuevo se reemplaza la anterior.
 */
@Service
public class ReaccionService {

    private final JdbcTemplate jdbcTemplate;

    public ReaccionService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * Reemplaza la reacción del usuario sobre una publicación por una nueva.
     *
     * @param publicacionId identificador de la publicación.
     * @param usuarioId identificador del usuario que reacciona.
     * @param tipo tipo de reacción.
     */
    public void reaccionarPublicacion(Long publicacionId, Long usuarioId, String tipo) {
        jdbcTemplate.update("DELETE FROM publicacion_reaccion WHERE publicacion_id = ? AND usuario_id = ?", publicacionId, usuarioId);
        jdbcTemplate.update(
            "INSERT INTO publicacion_reaccion (publicacion_id, usuario_id, tipo) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
            publicacionId, usuarioId, tipo);
    }

    /**
     * Quita la reacción de un usuario sobre una publicación.
     *
     * @param publicacionId identificador de la publicación.
     * @param usuarioId identificador del usuario.
     * @param tipo tipo de reacción a quitar.
     */
    public void quitarReaccionPublicacion(Long publicacionId, Long usuarioId, String tipo) {
        jdbcTemplate.update(
            "DELETE FROM publicacion_reaccion WHERE publicacion_id = ? AND usuario_id = ? AND tipo = ?",
            publicacionId, usuarioId, tipo);
    }

    /**
     * Reemplaza la reacción del usuario sobre un comentario por una nueva.
     *
     * @param comentarioId identificador del comentario.
     * @param usuarioId identificador del usuario que reacciona.
     * @param tipo tipo de reacción.
     */
    public void reaccionarComentario(Long comentarioId, Long usuarioId, String tipo) {
        jdbcTemplate.update("DELETE FROM comentario_reaccion WHERE comentario_id = ? AND usuario_id = ?", comentarioId, usuarioId);
        jdbcTemplate.update(
            "INSERT INTO comentario_reaccion (comentario_id, usuario_id, tipo) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
            comentarioId, usuarioId, tipo);
    }

    /**
     * Quita la reacción de un usuario sobre un comentario.
     *
     * @param comentarioId identificador del comentario.
     * @param usuarioId identificador del usuario.
     * @param tipo tipo de reacción a quitar.
     */
    public void quitarReaccionComentario(Long comentarioId, Long usuarioId, String tipo) {
        jdbcTemplate.update(
            "DELETE FROM comentario_reaccion WHERE comentario_id = ? AND usuario_id = ? AND tipo = ?",
            comentarioId, usuarioId, tipo);
    }

    /**
     * Reemplaza la reacción del usuario sobre un mensaje de chat directo por una nueva.
     *
     * @param mensajeId identificador del mensaje.
     * @param usuarioId identificador del usuario que reacciona.
     * @param tipo tipo de reacción.
     */
    // Chat directo - tabla real: "mensaje"
    public void reaccionarChat(Long mensajeId, Long usuarioId, String tipo) {
        jdbcTemplate.update("DELETE FROM mensaje_reaccion WHERE mensaje_id = ? AND usuario_id = ?", mensajeId, usuarioId);
        jdbcTemplate.update(
            "INSERT INTO mensaje_reaccion (mensaje_id, usuario_id, tipo) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
            mensajeId, usuarioId, tipo);
    }

    /**
     * Quita la reacción de un usuario sobre un mensaje de chat directo.
     *
     * @param mensajeId identificador del mensaje.
     * @param usuarioId identificador del usuario.
     * @param tipo tipo de reacción a quitar.
     */
    public void quitarReaccionChat(Long mensajeId, Long usuarioId, String tipo) {
        jdbcTemplate.update(
            "DELETE FROM mensaje_reaccion WHERE mensaje_id = ? AND usuario_id = ? AND tipo = ?",
            mensajeId, usuarioId, tipo);
    }

    /**
     * Reemplaza la reacción del usuario sobre un mensaje de una sala de chat grupal por una nueva.
     *
     * @param mensajeId identificador del mensaje de la sala.
     * @param usuarioId identificador del usuario que reacciona.
     * @param tipo tipo de reacción.
     */
    // Grupos - tabla real: "publicacion_grupo"
    public void reaccionarChatSala(Long mensajeId, Long usuarioId, String tipo) {
        jdbcTemplate.update("DELETE FROM publicacion_grupo_reaccion WHERE publicacion_grupo_id = ? AND usuario_id = ?", mensajeId, usuarioId);
        jdbcTemplate.update(
            "INSERT INTO publicacion_grupo_reaccion (publicacion_grupo_id, usuario_id, tipo) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
            mensajeId, usuarioId, tipo);
    }

    /**
     * Quita la reacción de un usuario sobre un mensaje de una sala de chat grupal.
     *
     * @param mensajeId identificador del mensaje de la sala.
     * @param usuarioId identificador del usuario.
     * @param tipo tipo de reacción a quitar.
     */
    public void quitarReaccionChatSala(Long mensajeId, Long usuarioId, String tipo) {
        jdbcTemplate.update(
            "DELETE FROM publicacion_grupo_reaccion WHERE publicacion_grupo_id = ? AND usuario_id = ? AND tipo = ?",
            mensajeId, usuarioId, tipo);
    }
}
