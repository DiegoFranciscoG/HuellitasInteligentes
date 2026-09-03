package com.huellitas.social;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

/**
 * Acceso a datos de las salas de chat grupal, delegando su gestión completa
 * (creación, membresía, mensajes) en funciones almacenadas de PostgreSQL.
 */
public interface ChatSalaRepository extends JpaRepository<Publicacion, Long> {

    /**
     * Lista las salas de chat a las que pertenece un usuario.
     *
     * @param usuarioId identificador del usuario.
     * @return un JSON (como texto) con las salas del usuario.
     */
    @Query(value = "SELECT fn_listar_salas_chat(:usuarioId)", nativeQuery = true)
    String listarSalas(@Param("usuarioId") Long usuarioId);

    /**
     * Crea una nueva sala de chat grupal.
     *
     * @param usuarioId identificador del usuario creador.
     * @param tema tema de la sala.
     * @param descripcion descripción de la sala.
     * @return los datos de la sala creada en formato JSON.
     */
    @Query(value = "SELECT fn_crear_sala_chat(:usuarioId, :tema, :descripcion)", nativeQuery = true)
    String crearSala(@Param("usuarioId") Long usuarioId, @Param("tema") String tema, @Param("descripcion") String descripcion);

    /**
     * Agrega a un usuario como miembro de una sala.
     *
     * @param salaId identificador de la sala.
     * @param usuarioId identificador del usuario.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_unirse_sala_chat(:salaId, :usuarioId)", nativeQuery = true)
    String unirseSala(@Param("salaId") Long salaId, @Param("usuarioId") Long usuarioId);

    /**
     * Obtiene el historial de mensajes de una sala.
     *
     * @param salaId identificador de la sala.
     * @param limite cantidad máxima de mensajes a devolver.
     * @return un JSON (como texto) con los mensajes de la sala.
     */
    @Query(value = "SELECT fn_mensajes_sala(:salaId, :limite)", nativeQuery = true)
    String mensajesSala(@Param("salaId") Long salaId, @Param("limite") Integer limite);

    /**
     * Guarda un mensaje nuevo en una sala de chat.
     *
     * @param salaId identificador de la sala.
     * @param emisorId identificador del usuario emisor.
     * @param contenido contenido del mensaje.
     * @return los datos del mensaje guardado (incluyendo su id) en formato JSON.
     */
    @Query(value = "SELECT fn_guardar_mensaje_sala(:salaId, :emisorId, :contenido)", nativeQuery = true)
    String guardarMensajeSala(@Param("salaId") Long salaId, @Param("emisorId") Long emisorId, @Param("contenido") String contenido);
}
