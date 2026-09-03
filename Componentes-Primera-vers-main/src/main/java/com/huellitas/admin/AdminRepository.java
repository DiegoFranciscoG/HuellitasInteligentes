package com.huellitas.admin;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * Acceso a datos usado por el panel administrativo: agrega consultas de
 * solo lectura sobre distintas entidades (usuarios, casas, planes,
 * suscripciones, reportes, RAG, dispositivos) devueltas como JSON, más
 * algunas operaciones de escritura delegadas a funciones de PostgreSQL.
 */
public interface AdminRepository extends JpaRepository<Plan, Long> {

    /**
     * Calcula las métricas generales del panel administrativo.
     *
     * @return un JSON (como texto) con el resumen de métricas.
     */
    @Query(value = "SELECT fn_admin_dashboard()", nativeQuery = true)
    String adminDashboard();

    /**
     * Busca viviendas por texto libre, con paginación.
     *
     * @param texto texto de búsqueda.
     * @param limite cantidad máxima de resultados.
     * @param offset cantidad de resultados a saltar.
     * @return un JSON (como texto) con las viviendas encontradas.
     */
    @Query(value = "SELECT fn_admin_buscar_casas(:texto, :limite, :offset)", nativeQuery = true)
    String adminBuscarCasas(@Param("texto") String texto, @Param("limite") Integer limite, @Param("offset") Integer offset);

    /**
     * Lista todos los planes de suscripción junto con su cantidad de suscriptores activos.
     *
     * @return un JSON (como texto) con la lista de planes.
     */
    @Query(value = "SELECT COALESCE(json_agg(t), '[]'::json) FROM (SELECT p.*, (SELECT COUNT(DISTINCT s.casa_id) FROM suscripcion s WHERE s.plan_id = p.id AND (s.estado::text = 'ACTIVO' OR s.estado::text = 'ACTIVA')) as suscriptores FROM plan p ORDER BY p.id ASC) t", nativeQuery = true)
    String listarPlanes();

    /**
     * Cambia el plan de suscripción activo de una vivienda.
     *
     * @param casaId identificador de la vivienda.
     * @param planId identificador del nuevo plan.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_cambiar_plan_casa(:casaId, :planId)", nativeQuery = true)
    String cambiarPlanCasa(@Param("casaId") Long casaId, @Param("planId") Long planId);

    /**
     * Lista las suscripciones de las viviendas con datos del propietario y del plan.
     *
     * @param adminId identificador del administrador que consulta (sin uso en la consulta actual).
     * @param estado estado de suscripción a filtrar (sin uso en la consulta actual).
     * @return un JSON (como texto) con la lista de suscripciones.
     */
    @Query(value = "SELECT COALESCE(json_agg(t), '[]'::json) FROM (SELECT s.id, s.estado, s.fecha_inicio, s.fecha_fin, s.created_at, u.nombre as usuario_nombre, u.email as usuario_email, p.nombre as plan_nombre FROM suscripcion s LEFT JOIN casa c ON s.casa_id = c.id LEFT JOIN usuario u ON c.propietario_id = u.id LEFT JOIN plan p ON s.plan_id = p.id ORDER BY s.created_at DESC) t", nativeQuery = true)
    String listarSuscripciones(@Param("adminId") Long adminId, @Param("estado") String estado);

    /**
     * Lista los usuarios del sistema con su estado y strikes acumulados,
     * más recientes primero. Acepta un límite y desplazamiento opcionales
     * (con un valor por defecto generoso) para no traer la tabla completa
     * a medida que crezca.
     *
     * @param adminId identificador del administrador que consulta (sin uso en la consulta actual).
     * @param limite cantidad máxima de usuarios a devolver.
     * @param offset cantidad de usuarios a saltar (paginación).
     * @return un JSON (como texto) con la lista de usuarios.
     */
    @Query(value = "SELECT COALESCE(json_agg(t), '[]'::json) FROM (SELECT u.id, u.nombre, u.email, u.rol, u.activo, u.created_at, u.strikes, u.baneado_comunidad FROM usuario u ORDER BY u.created_at DESC LIMIT :limite OFFSET :offset) t", nativeQuery = true)
    String listarUsuarios(@Param("adminId") Long adminId, @Param("limite") Integer limite, @Param("offset") Integer offset);

    /**
     * Registra un aviso masivo del administrador para los usuarios del sistema.
     *
     * @param adminId identificador del administrador que crea el aviso.
     * @param titulo título del aviso.
     * @param mensaje contenido del aviso.
     * @param tipo tipo de aviso.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_crear_notificacion_admin(:adminId, :titulo, :mensaje, :tipo)", nativeQuery = true)
    String crearNotificacionAdmin(@Param("adminId") Long adminId, @Param("titulo") String titulo, @Param("mensaje") String mensaje, @Param("tipo") String tipo);

    /**
     * Lista el historial de avisos masivos enviados por administradores.
     *
     * @return un JSON (como texto) con el historial de avisos.
     */
    @Query(value = "SELECT fn_listar_notificaciones_admin()", nativeQuery = true)
    String listarNotificacionesAdmin();

    /**
     * Calcula los datos para las gráficas de actividad del sistema.
     *
     * @return un JSON (como texto) con las series de actividad.
     */
    @Query(value = "SELECT fn_admin_graficas_actividad()", nativeQuery = true)
    String graficasActividad();

    /**
     * Calcula el conteo de usuarios nuevos agrupados por mes de registro.
     *
     * @return un JSON (como texto) con la serie mensual de altas de usuarios.
     */
    @Query(value = "SELECT COALESCE(json_agg(t), '[]'::json) FROM (SELECT TO_CHAR(created_at, 'Mon YYYY') as mes, COUNT(*) as total FROM usuario GROUP BY TO_CHAR(created_at, 'Mon YYYY'), DATE_TRUNC('month', created_at) ORDER BY DATE_TRUNC('month', created_at) ASC) t", nativeQuery = true)
    String usuariosPorMes();

    /**
     * Lista los reportes de contenido (moderación) con los datos del denunciante, el reportado y el contenido denunciado.
     *
     * @return un JSON (como texto) con la lista de reportes.
     */
    @Query(value = "SELECT COALESCE(json_agg(t), '[]'::json) FROM (SELECT r.id, r.casa_id, r.reportador_id, r.reportado_id, r.motivo, r.estado, r.created_at, r.decidido_por, r.motivo_ia, r.confianza_ia, r.revertido, u.nombre as denunciante_nombre, u2.nombre as reportado_nombre, u2.nombre as autor_publicacion_nombre, COALESCE((SELECT p.contenido FROM publicacion p WHERE p.id = NULLIF(regexp_replace(r.motivo, '.*#([0-9]+).*', '\\1'), r.motivo)::bigint), r.motivo) as contenido_denunciado FROM reporte_moderacion r LEFT JOIN usuario u ON r.reportador_id = u.id LEFT JOIN usuario u2 ON r.reportado_id = u2.id ORDER BY r.created_at DESC) t", nativeQuery = true)
    String listarReportes();

    /**
     * Aplica la decisión del administrador sobre un reporte de contenido pendiente.
     *
     * @param reporteId identificador del reporte.
     * @param decision decisión tomada ({@code STRIKE}, {@code ELIMINAR_SIN_STRIKE} o {@code DESCARTADO}).
     * @param adminId identificador del administrador que resuelve.
     * @param comentario justificación de la decisión.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_resolver_denuncia(:reporteId, :decision, :adminId, :comentario)::text", nativeQuery = true)
    String resolverDenuncia(@Param("reporteId") Long reporteId, @Param("decision") String decision, @Param("adminId") Long adminId, @Param("comentario") String comentario);

    /**
     * Lista las fuentes confiables registradas para la base de conocimiento del asistente IA.
     *
     * @return un JSON (como texto) con la lista de fuentes confiables.
     */
    @Query(value = "SELECT COALESCE(json_agg(t), '[]'::json) FROM (SELECT fc.*, u.nombre as creado_por_nombre FROM fuente_confiable fc LEFT JOIN usuario u ON fc.creado_por = u.id ORDER BY fc.created_at DESC) t", nativeQuery = true)
    String listarFuentesConfiables();

    /**
     * Lista los documentos PDF con los que está entrenada la IA. Se calcula a
     * partir de los fragmentos realmente indexados en rag_fragmento (no de
     * rag_documento, que solo registra las subidas hechas desde este panel)
     * para que también aparezcan los PDFs ingeridos por el script de carga
     * inicial y el conteo de fragmentos sea siempre el real.
     *
     * @return un JSON (como texto) con la lista de documentos con los que está entrenada la IA.
     */
    @Query(value = "SELECT COALESCE(json_agg(t), '[]'::json) FROM (" +
        "SELECT f.fuente AS nombre_archivo, COUNT(*) AS total_chunks, MIN(f.created_at) AS created_at, MAX(u.nombre) AS creado_por_nombre " +
        "FROM rag_fragmento f " +
        "LEFT JOIN rag_documento rd ON rd.nombre_archivo = f.fuente " +
        "LEFT JOIN usuario u ON rd.creado_por = u.id " +
        "WHERE f.fuente NOT ILIKE 'http%' " +
        "GROUP BY f.fuente ORDER BY MIN(f.created_at) DESC" +
        ") t", nativeQuery = true)
    String listarDocumentosRag();

    /**
     * Lista, en modo de solo lectura, los dispositivos IoT de todas las viviendas
     * junto con su zona, casa y propietario, para que el panel de administración
     * pueda agruparlos por usuario en vez de mostrar una tabla plana sin dueño.
     *
     * <p>{@code problema} señala con qué criterio real se marca un dispositivo
     * para revisar: nunca dio señal, lleva más de 24 horas sin dar señal, o su
     * columna {@code estado} quedó en {@code ERROR}. Es {@code null} —conforme—
     * en cualquier otro caso. {@code en_linea} usa una ventana mucho más corta
     * (60 s) porque responde una pregunta distinta: si está prendido ahora
     * mismo, no si hay algo que atender.</p>
     *
     * @return un JSON (como texto) con la lista de dispositivos.
     */
    @Query(value = "SELECT COALESCE(json_agg(t), '[]'::json) FROM (SELECT d.id, d.mac_address, d.tipo, d.categoria, d.modelo, d.estado, d.ultima_conexion, d.created_at, z.nombre as zona_nombre, c.id as casa_id, c.nombre as casa_nombre, u.nombre as propietario_nombre, u.email as propietario_email, (d.ultima_conexion IS NOT NULL AND d.ultima_conexion > now() - interval '60 seconds') as en_linea, CASE WHEN d.estado = 'ERROR' THEN 'Estado de error' WHEN d.ultima_conexion IS NULL THEN 'Nunca ha dado señal' WHEN d.ultima_conexion < now() - interval '24 hours' THEN 'Sin señal hace más de 24 horas' ELSE NULL END as problema FROM dispositivo d JOIN zona z ON d.zona_id = z.id JOIN casa c ON z.casa_id = c.id LEFT JOIN usuario u ON u.id = c.propietario_id WHERE d.deleted_at IS NULL ORDER BY c.id, d.id) t", nativeQuery = true)
    String listarDispositivosIoT();
}