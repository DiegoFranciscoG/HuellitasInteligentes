package com.huellitas.social;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * Acceso a datos de la red social de la comunidad (feed, comentarios,
 * reacciones, mensajería directa, grupos temáticos y moderación),
 * delegando toda la lógica en funciones almacenadas de PostgreSQL. Cada
 * método corresponde 1:1 con un endpoint de {@link SocialController}, donde
 * se documenta el significado de negocio de la operación.
 */
public interface SocialRepository extends JpaRepository<Publicacion, Long> {

    /** Calcula el feed principal de publicaciones, paginado. */
    @Query(value = "SELECT fn_feed_social(:usuarioId, :limite, :offset)", nativeQuery = true)
    String feedSocial(@Param("usuarioId") Long usuarioId, @Param("limite") Integer limite, @Param("offset") Integer offset);

    /** Lista los comentarios de una publicación. */
    @Query(value = "SELECT fn_listar_comentarios(:publicacionId, :usuarioId)", nativeQuery = true)
    String listarComentarios(@Param("publicacionId") Long publicacionId, @Param("usuarioId") Long usuarioId);

    /** Búsqueda por texto libre o hashtag; misma estructura que el feed. */
    @Query(value = "SELECT fn_buscar_publicaciones(:usuarioId, :q, :limite, :offset)", nativeQuery = true)
    String buscarPublicaciones(@Param("usuarioId") Long usuarioId, @Param("q") String q,
                               @Param("limite") Integer limite, @Param("offset") Integer offset);

    /** Hashtags más usados, para sugerir temas. */
    @Query(value = "SELECT fn_hashtags_populares(:limite)", nativeQuery = true)
    String hashtagsPopulares(@Param("limite") Integer limite);

    /** Crea una nueva publicación en el feed. */
    @Query(value = "SELECT fn_crear_publicacion(:usuarioId, :contenido, :imagenUrl, :mediaType)", nativeQuery = true)
    String crearPublicacion(@Param("usuarioId") Long usuarioId, @Param("contenido") String contenido,
                            @Param("imagenUrl") String imagenUrl, @Param("mediaType") String mediaType);

    /** Alterna el "me gusta" de un usuario sobre una publicación. */
    @Query(value = "SELECT fn_reaccionar_publicacion(:publicacionId, :usuarioId)", nativeQuery = true)
    Boolean reaccionar(@Param("publicacionId") Long publicacionId, @Param("usuarioId") Long usuarioId);

    /** Alterna la reacción de un usuario sobre una publicación de un grupo. */
    @Query(value = "SELECT fn_reaccionar_publicacion_grupo(:publicacionGrupoId, :usuarioId, :tipo)", nativeQuery = true)
    String reaccionarPublicacionGrupo(@Param("publicacionGrupoId") Long publicacionGrupoId, @Param("usuarioId") Long usuarioId, @Param("tipo") String tipo);

    /** Registra una denuncia simple sobre una publicación. */
    @Query(value = "SELECT fn_reportar_publicacion(:publicacionId, :usuarioId, :motivo)", nativeQuery = true)
    String reportar(@Param("publicacionId") Long publicacionId, @Param("usuarioId") Long usuarioId, @Param("motivo") String motivo);

    /** Agrega un comentario a una publicación. */
    @Query(value = "SELECT fn_comentar(:publicacionId, :usuarioId, :contenido)", nativeQuery = true)
    String comentar(@Param("publicacionId") Long publicacionId, @Param("usuarioId") Long usuarioId, @Param("contenido") String contenido);

    /** Obtiene el historial de mensajes directos entre dos usuarios. */
    @Query(value = "SELECT fn_conversacion(:usuarioId, :otroId, :limite)", nativeQuery = true)
    String conversacion(@Param("usuarioId") Long usuarioId, @Param("otroId") Long otroId, @Param("limite") Integer limite);

    /** Envía un mensaje directo de un usuario a otro. */
    @Query(value = "SELECT fn_enviar_mensaje(:emisorId, :receptorId, :contenido)", nativeQuery = true)
    String enviarMensaje(@Param("emisorId") Long emisorId, @Param("receptorId") Long receptorId, @Param("contenido") String contenido);

    /** Edita el contenido de un comentario propio. */
    @Query(value = "SELECT fn_editar_comentario(:comentarioId, :usuarioId, :contenido)", nativeQuery = true)
    String editarComentario(@Param("comentarioId") Long comentarioId, @Param("usuarioId") Long usuarioId, @Param("contenido") String contenido);

    /** Elimina un comentario propio. */
    @Query(value = "SELECT fn_eliminar_comentario(:comentarioId, :usuarioId)", nativeQuery = true)
    String eliminarComentario(@Param("comentarioId") Long comentarioId, @Param("usuarioId") Long usuarioId);

    /** Edita el contenido de una publicación propia. */
    @Query(value = "SELECT fn_editar_publicacion(:publicacionId, :usuarioId, :contenido)", nativeQuery = true)
    String editarPublicacion(@Param("publicacionId") Long publicacionId, @Param("usuarioId") Long usuarioId, @Param("contenido") String contenido);

    /** Elimina una publicación propia. */
    @Query(value = "SELECT fn_eliminar_publicacion(:publicacionId, :usuarioId)", nativeQuery = true)
    String eliminarPublicacion(@Param("publicacionId") Long publicacionId, @Param("usuarioId") Long usuarioId);

    /** Crea un nuevo grupo temático de la comunidad. */
    @Query(value = "SELECT fn_crear_grupo(:nombre, :descripcion, :creadoPor)", nativeQuery = true)
    String crearGrupo(@Param("nombre") String nombre, @Param("descripcion") String descripcion, @Param("creadoPor") Long creadoPor);

    /** Agrega a un usuario como miembro de un grupo temático. */
    @Query(value = "SELECT fn_unirse_grupo(:grupoId, :usuarioId)", nativeQuery = true)
    String unirseGrupo(@Param("grupoId") Long grupoId, @Param("usuarioId") Long usuarioId);

    /** Quita a un usuario de un grupo temático. */
    @Query(value = "SELECT fn_salir_grupo(:grupoId, :usuarioId)", nativeQuery = true)
    String salirGrupo(@Param("grupoId") Long grupoId, @Param("usuarioId") Long usuarioId);

    /** Lista los grupos temáticos existentes, indicando cuáles integra el usuario. */
    @Query(value = "SELECT fn_listar_grupos(:usuarioId)", nativeQuery = true)
    String listarGrupos(@Param("usuarioId") Long usuarioId);

    /** Lista las publicaciones del muro de un grupo temático. */
    @Query(value = "SELECT fn_mensajes_grupo(:grupoId, :usuarioId)", nativeQuery = true)
    String mensajesGrupo(@Param("grupoId") Long grupoId, @Param("usuarioId") Long usuarioId);

    /** Publica un mensaje en el muro de un grupo temático. */
    @Query(value = "SELECT fn_publicar_en_grupo(:grupoId, :usuarioId, :contenido, :imagenUrl)", nativeQuery = true)
    String publicarEnGrupo(@Param("grupoId") Long grupoId, @Param("usuarioId") Long usuarioId, @Param("contenido") String contenido, @Param("imagenUrl") String imagenUrl);

    /** Lista sugerencias de lenguaje inclusivo para redactar publicaciones. */
    @Query(value = "SELECT fn_listar_sugerencias_inclusivas()", nativeQuery = true)
    String listarSugerenciasInclusivas();

    /** Aplica manualmente un strike a un usuario (acción de un administrador). */
    @Query(value = "SELECT fn_admin_dar_strike(:adminId, :usuarioId)", nativeQuery = true)
    String darStrike(@Param("adminId") Long adminId, @Param("usuarioId") Long usuarioId);

    /** Aplica un strike a un usuario por decisión automática del sistema de moderación. */
    @Query(value = "SELECT fn_sistema_dar_strike(:usuarioId, :motivo)", nativeQuery = true)
    String sistemaDarStrike(@Param("usuarioId") Long usuarioId, @Param("motivo") String motivo);

    /** Edita el contenido de una publicación de un grupo temático. */
    @Query(value = "SELECT fn_editar_publicacion_grupo(:publicacionId, :usuarioId, :contenido)", nativeQuery = true)
    String editarPublicacionGrupo(@Param("publicacionId") Long publicacionId, @Param("usuarioId") Long usuarioId, @Param("contenido") String contenido);

    /** Elimina una publicación de un grupo temático. */
    @Query(value = "SELECT fn_eliminar_publicacion_grupo(:publicacionId, :usuarioId)", nativeQuery = true)
    String eliminarPublicacionGrupo(@Param("publicacionId") Long publicacionId, @Param("usuarioId") Long usuarioId);

    /** Transfiere la administración de un grupo temático a otro miembro. */
    @Query(value = "SELECT fn_transferir_admin_grupo(:grupoId, :adminId, :nuevoAdminId)", nativeQuery = true)
    String transferirAdminGrupo(@Param("grupoId") Long grupoId, @Param("adminId") Long adminId, @Param("nuevoAdminId") Long nuevoAdminId);

    /** Elimina un grupo temático. */
    @Query(value = "SELECT fn_eliminar_grupo(:grupoId, :adminId)", nativeQuery = true)
    String eliminarGrupo(@Param("grupoId") Long grupoId, @Param("adminId") Long adminId);

    /** Lista los miembros de un grupo temático, con su rol dentro del grupo. */
    @Query(value = "SELECT fn_miembros_grupo(:grupoId)", nativeQuery = true)
    String miembrosGrupo(@Param("grupoId") Long grupoId);

    /** Expulsa a un miembro de un grupo temático (solo el creador, un ADMIN del grupo, o un administrador de la plataforma). */
    @Query(value = "SELECT fn_expulsar_miembro_grupo(:grupoId, :adminId, :usuarioId)", nativeQuery = true)
    String expulsarMiembroGrupo(@Param("grupoId") Long grupoId, @Param("adminId") Long adminId, @Param("usuarioId") Long usuarioId);

    /** Registra una denuncia sobre una publicación de un grupo temático. */
    @Query(value = "SELECT fn_reportar_publicacion_grupo(:publicacionId, :usuarioId, :motivo)", nativeQuery = true)
    String reportarPublicacionGrupo(@Param("publicacionId") Long publicacionId, @Param("usuarioId") Long usuarioId, @Param("motivo") String motivo);

    /** Oculta un contenido (publicación, comentario o publicación de grupo) solo para quien lo pide — sigue visible para los demás. */
    @Query(value = "SELECT fn_ocultar_contenido(:usuarioId, :tipo, :contenidoId)", nativeQuery = true)
    String ocultarContenido(@Param("usuarioId") Long usuarioId, @Param("tipo") String tipo, @Param("contenidoId") Long contenidoId);
}