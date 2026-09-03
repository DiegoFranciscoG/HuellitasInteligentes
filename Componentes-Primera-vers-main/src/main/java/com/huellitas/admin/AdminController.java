package com.huellitas.admin;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import com.huellitas.auth.AuthMailService;
import com.huellitas.auth.RolUsuario;
import com.huellitas.config.AuthContext;
import com.huellitas.ia.RagService;
import com.huellitas.utils.ValidationUtils;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

/**
 * Panel administrativo del sistema: métricas generales, gestión de planes de
 * suscripción, usuarios, moderación de reportes de contenido, avisos
 * masivos, la base documental del asistente IA (RAG) y una vista de solo
 * lectura del parque de dispositivos IoT. Pensado para el rol
 * {@code ADMINISTRADOR}, no para propietarios ni miembros comunes.
 */
@RestController
@RequestMapping("/api/huellitas/admin")
public class AdminController {
    private final AdminRepository repo;
    private final JdbcTemplate jdbcTemplate;
    private final AuthMailService mailService;
    private final RagService ragService;
    private final AuthContext authContext;

    public AdminController(AdminRepository repo, JdbcTemplate jdbcTemplate, AuthMailService mailService, RagService ragService, AuthContext authContext) {
        this.repo = repo;
        this.jdbcTemplate = jdbcTemplate;
        this.mailService = mailService;
        this.ragService = ragService;
        this.authContext = authContext;
    }

    /** Decisión del administrador sobre un reporte de contenido pendiente. */
    public static class ResolverDTO {
        public Long adminId;
        public String decision; // 'STRIKE', 'ELIMINAR_SIN_STRIKE', 'DESCARTADO'
        public String comentarioAdmin;
    }

    /**
     * Datos de un plan de suscripción a crear o editar.
     *
     * {@code limiteDispositivos} queda en desuso: nunca se valida al crear un
     * dispositivo o cámara (el usuario registra los que quiera), solo se
     * guarda por compatibilidad con el esquema. El límite que sí aplica —
     * comprobado en {@code fn_registrar_mascota}, que rechaza el alta con
     * {@code LIMITE_MASCOTAS_ALCANZADO} — es {@code limiteMascotas}.
     */
    public static class PlanDTO {
        public Long adminId;
        public String nombre;
        public BigDecimal precioMensual;
        public BigDecimal precioOferta;
        public BigDecimal descuentoPorcentaje;
        public Integer limiteDispositivos;
        public Integer limiteMascotas;
        public Integer limiteAlmacenamientoMb;
        public String descripcion;
    }

    /** Fuente confiable (URL) que alimenta la base de conocimiento del asistente IA. */
    public static class FuenteDTO {
        public Long adminId;
        public String url;
        public String descripcion;
    }

    /**
     * Obtiene las métricas generales del panel administrativo (totales de
     * usuarios, casas, dispositivos, suscripciones, etc.).
     *
     * @return un JSON (como texto) con el resumen de métricas.
     */
    @GetMapping(value = "/dashboard", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> adminDashboard() {
        return ResponseEntity.ok(repo.adminDashboard());
    }

    /**
     * Obtiene los datos para las gráficas de actividad del sistema.
     *
     * @return un JSON (como texto) con las series de actividad.
     */
    @GetMapping(value = "/graficas-actividad", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> graficasActividad() {
        return ResponseEntity.ok(repo.graficasActividad());
    }

    /**
     * Obtiene el conteo de usuarios nuevos registrados por mes.
     *
     * @return un JSON (como texto) con la serie mensual de altas de usuarios.
     */
    @GetMapping(value = "/usuarios-por-mes", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> usuariosPorMes() {
        return ResponseEntity.ok(repo.usuariosPorMes());
    }

    /**
     * Busca viviendas registradas en el sistema, con paginación y filtro de texto libre.
     *
     * @param texto texto de búsqueda libre (nombre, dirección, etc.), opcional.
     * @param limite cantidad máxima de resultados a devolver.
     * @param offset cantidad de resultados a saltar (paginación).
     * @return un JSON (como texto) con la lista de viviendas encontradas.
     */
    @GetMapping(value = "/casas", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> adminBuscarCasas(
            @RequestParam(required = false) String texto,
            @RequestParam(defaultValue = "20") Integer limite,
            @RequestParam(defaultValue = "0") Integer offset) {
        return ResponseEntity.ok(repo.adminBuscarCasas(texto, limite, offset));
    }

    // ── Planes ────────────────────────────────────────────────────────────

    /**
     * Lista todos los planes de suscripción, activos e inactivos.
     *
     * @return un JSON (como texto) con la lista de planes.
     */
    @GetMapping(value = "/planes", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarPlanes() {
        return ResponseEntity.ok(repo.listarPlanes());
    }

    /**
     * Crea un nuevo plan de suscripción y limpia la caché de planes activos.
     *
     * @param dto datos del plan a crear.
     * @return confirmación de creación, o un error 500 si falla la inserción.
     */
    @org.springframework.cache.annotation.CacheEvict(value = "planesActivos", allEntries = true)
    @PostMapping(value = "/planes", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> crearPlanJson(@RequestBody PlanDTO dto) {
        try {
            jdbcTemplate.update(
                "INSERT INTO plan (nombre, precio_mensual, precio_oferta, descuento_porcentaje, limite_dispositivos, limite_mascotas, limite_almacenamiento_mb, descripcion, activo, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, true, NOW(), NOW())",
                dto.nombre, dto.precioMensual, dto.precioOferta, dto.descuentoPorcentaje != null ? dto.descuentoPorcentaje : BigDecimal.ZERO,
                dto.limiteDispositivos != null ? dto.limiteDispositivos : 5, dto.limiteMascotas != null ? dto.limiteMascotas : 2,
                dto.limiteAlmacenamientoMb != null ? dto.limiteAlmacenamientoMb : 1000,
                dto.descripcion
            );
            return ResponseEntity.ok("{\"ok\": true, \"message\": \"Plan creado exitosamente.\"}");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    /**
     * Edita un plan de suscripción existente y notifica por la campanita de
     * notificaciones a todos los propietarios suscritos a ese plan sobre el cambio de precio.
     *
     * @param planId identificador del plan a editar.
     * @param dto nuevos datos del plan.
     * @return confirmación de la actualización, o un error 500 si falla.
     */
    @org.springframework.cache.annotation.CacheEvict(value = "planesActivos", allEntries = true)
    @PutMapping(value = "/planes/{planId}", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> editarPlanJson(@PathVariable Long planId, @RequestBody PlanDTO dto) {
        try {
            jdbcTemplate.update(
                "UPDATE plan SET nombre = COALESCE(?, nombre), precio_mensual = ?, precio_oferta = ?, descuento_porcentaje = ?, " +
                "limite_mascotas = COALESCE(?, limite_mascotas), descripcion = COALESCE(?, descripcion), updated_at = NOW() WHERE id = ?",
                dto.nombre, dto.precioMensual, dto.precioOferta, dto.descuentoPorcentaje, dto.limiteMascotas, dto.descripcion, planId
            );

            String contenidoAviso = "Actualización de Plan " + (dto.nombre != null ? dto.nombre : "") + ": el precio, la oferta o el límite de mascotas de tu plan ha cambiado.";
            jdbcTemplate.update(
                "INSERT INTO notificacion (usuario_id, canal, contenido, estado, enviado_at) " +
                "SELECT DISTINCT c.propietario_id, 'WEBSOCKET'::canal_notificacion, ?, 'PENDIENTE'::estado_notificacion, NOW() " +
                "FROM suscripcion s JOIN casa c ON s.casa_id = c.id WHERE s.plan_id = ?",
                contenidoAviso, planId
            );

            return ResponseEntity.ok("{\"ok\": true, \"message\": \"Plan actualizado y usuarios notificados.\"}");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    /**
     * Activa o desactiva un plan de suscripción (alterna su estado actual).
     *
     * @param planId identificador del plan.
     * @return confirmación del cambio de estado, o un error 500 si falla.
     */
    @org.springframework.cache.annotation.CacheEvict(value = "planesActivos", allEntries = true)
    @PutMapping(value = "/planes/{planId}/toggle", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> togglePlan(@PathVariable Long planId) {
        try {
            jdbcTemplate.update("UPDATE plan SET activo = NOT activo, updated_at = NOW() WHERE id = ?", planId);
            return ResponseEntity.ok("{\"ok\": true, \"message\": \"Estado del plan alternado.\"}");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    /**
     * Descontinúa un plan de suscripción (desactivación lógica) y notifica a
     * los propietarios suscritos a él.
     *
     * @param planId identificador del plan a descontinuar.
     * @return confirmación de la desactivación, o un error 500 si falla.
     */
    @org.springframework.cache.annotation.CacheEvict(value = "planesActivos", allEntries = true)
    @DeleteMapping(value = "/planes/{planId}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> eliminarPlan(@PathVariable Long planId) {
        try {
            String contenidoAviso = "⚠️ Plan Descontinuado: El plan al que estabas suscrito ha sido descontinuado por el administrador.";
            jdbcTemplate.update(
                "INSERT INTO notificacion (usuario_id, canal, contenido, estado, enviado_at) " +
                "SELECT DISTINCT c.propietario_id, 'WEBSOCKET'::canal_notificacion, ?, 'PENDIENTE'::estado_notificacion, NOW() " +
                "FROM suscripcion s JOIN casa c ON s.casa_id = c.id WHERE s.plan_id = ?",
                contenidoAviso, planId
            );
            jdbcTemplate.update("UPDATE plan SET activo = false, updated_at = NOW() WHERE id = ?", planId);
            return ResponseEntity.ok("{\"ok\": true, \"message\": \"Plan desactivado y usuarios notificados.\"}");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    // ── Usuarios & Suscripciones ─────────────────────────────────────────

    /**
     * Lista los usuarios registrados en el sistema, más recientes primero.
     * Sin parámetros de paginación se comporta igual que antes (hasta 500
     * usuarios); {@code limite}/{@code offset} quedan disponibles para
     * cuando la tabla crezca lo suficiente como para necesitarlos de verdad.
     *
     * @param adminId identificador del administrador que consulta (opcional, para auditoría).
     * @param limite cantidad máxima de usuarios a devolver (por defecto 500).
     * @param offset cantidad de usuarios a saltar (por defecto 0).
     * @return un JSON (como texto) con la lista de usuarios.
     */
    @GetMapping(value = "/usuarios", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarUsuarios(
            @RequestParam(required = false) Long adminId,
            @RequestParam(defaultValue = "500") Integer limite,
            @RequestParam(defaultValue = "0") Integer offset) {
        Long aid = authContext.usuarioIdActual();
        return ResponseEntity.ok(repo.listarUsuarios(aid, limite, offset));
    }

    /** Datos para crear un usuario directamente desde el panel administrativo. */
    public static class CrearUsuarioAdminDTO {
        public String email;
        public String password;
        public String nombre;
        public String rol;
    }

    /**
     * Crea un usuario directamente desde el panel administrativo, ya
     * verificado y activo, sin pasar por el flujo normal de registro.
     *
     * @param dto datos del usuario: email, password, nombre y rol (por defecto {@code PROPIETARIO}).
     * @return confirmación de creación, o un error 400 si los datos están incompletos o inválidos.
     */
    @PostMapping(value = "/usuarios", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> crearUsuarioAdmin(@RequestBody CrearUsuarioAdminDTO dto) {
        if (dto == null || dto.email == null || dto.password == null || dto.nombre == null) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "Datos incompletos"));
        }
        try {
            String email = ValidationUtils.validarEmail(dto.email);
            ValidationUtils.validarPassword(dto.password.trim());
            String rolUpper = dto.rol != null ? dto.rol.toUpperCase() : "PROPIETARIO";
            try {
                RolUsuario.valueOf(rolUpper);
            } catch (IllegalArgumentException e) {
                return ResponseEntity.status(400).body(Map.of("ok", false, "error", "Rol inválido"));
            }
            jdbcTemplate.update(
                "INSERT INTO usuario (email, password_hash, nombre, rol, activo, email_verificado, created_at, updated_at) " +
                "VALUES (?, crypt(?, gen_salt('bf')), ?, ?::rol_usuario, true, true, NOW(), NOW())",
                email, dto.password.trim(), dto.nombre.trim(), rolUpper
            );
            return ResponseEntity.ok(Map.of("ok", true, "message", "Usuario creado exitosamente desde el panel admin."));
        } catch (Exception e) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", e.getMessage()));
        }
    }

    /**
     * Elimina permanentemente a un usuario y todos sus datos dependientes
     * (tokens de sesión, mensajes de chat, salas creadas, resoluciones de
     * moderación y reportes en los que participó).
     *
     * @param id identificador del usuario a eliminar.
     * @return confirmación de eliminación, o un error 500 si falla.
     */
    @DeleteMapping(value = "/usuarios/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> eliminarUsuarioAdmin(@PathVariable Long id) {
        try {
            jdbcTemplate.update("DELETE FROM qr_login_token WHERE usuario_id = ?", id);
            jdbcTemplate.update("DELETE FROM password_reset_token WHERE usuario_id = ?", id);
            jdbcTemplate.update("DELETE FROM refresh_token WHERE usuario_id = ?", id);
            jdbcTemplate.update("DELETE FROM chat_sala_mensaje WHERE emisor_id = ?", id);
            jdbcTemplate.update("DELETE FROM chat_sala_miembro WHERE usuario_id = ?", id);
            jdbcTemplate.update("DELETE FROM chat_sala WHERE creado_por = ?", id);
            jdbcTemplate.update("DELETE FROM reporte_resolucion WHERE admin_id = ?", id);
            jdbcTemplate.update("DELETE FROM reporte_video WHERE reportado_id = ? OR denunciante_id = ?", id, id);
            jdbcTemplate.update("DELETE FROM usuario WHERE id = ?", id);

            return ResponseEntity.ok(Map.of("ok", true, "message", "Usuario eliminado exitosamente."));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("ok", false, "error", e.getMessage()));
        }
    }

    /**
     * Obtiene un resumen de actividad de un usuario: sus últimas
     * publicaciones, las resoluciones de moderación en las que fue
     * reportado y el historial de suscripciones de su vivienda.
     *
     * @param id identificador del usuario.
     * @return un mapa con las listas de publicaciones, resoluciones y suscripciones; listas vacías si ocurre un error.
     */
    @GetMapping(value = "/usuarios/{id}/actividad", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> actividadUsuario(@PathVariable Long id) {
        try {
            List<Map<String, Object>> publicaciones = jdbcTemplate.queryForList(
                "SELECT id, contenido, created_at FROM publicacion WHERE usuario_id = ? ORDER BY created_at DESC LIMIT 10", id
            );
            List<Map<String, Object>> resoluciones = jdbcTemplate.queryForList(
                "SELECT rr.decision, rr.comentario_admin, rr.fecha_resolucion FROM reporte_resolucion rr JOIN reporte_moderacion rm ON rr.reporte_id = rm.id WHERE rm.reportado_id = ? ORDER BY rr.fecha_resolucion DESC LIMIT 10", id
            );
            List<Map<String, Object>> suscripciones = jdbcTemplate.queryForList(
                "SELECT s.id, p.nombre as plan_nombre, s.estado, s.created_at FROM suscripcion s JOIN casa c ON s.casa_id = c.id JOIN plan p ON s.plan_id = p.id WHERE c.propietario_id = ? ORDER BY s.created_at DESC", id
            );
            return ResponseEntity.ok(Map.of("publicaciones", publicaciones, "resoluciones", resoluciones, "suscripciones", suscripciones));
        } catch (Exception e) {
            System.err.println("[Admin] Error obteniendo actividad del usuario " + id + ": " + e.getMessage());
            return ResponseEntity.ok(Map.of("publicaciones", List.of(), "resoluciones", List.of(), "suscripciones", List.of()));
        }
    }

    /**
     * Lista las suscripciones de las viviendas, con filtro opcional por estado.
     *
     * @param adminId identificador del administrador que consulta (opcional, para auditoría).
     * @param estado estado de suscripción a filtrar (opcional).
     * @return un JSON (como texto) con la lista de suscripciones.
     */
    @GetMapping(value = "/suscripciones", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarSuscripciones(
            @RequestParam(required = false) Long adminId,
            @RequestParam(required = false) String estado) {
        Long aid = authContext.usuarioIdActual();
        return ResponseEntity.ok(repo.listarSuscripciones(aid, estado));
    }

    // ── Moderación y Reportes ─────────────────────────────────────────────

    /**
     * Lista los reportes de contenido (publicaciones, comentarios, videollamadas) pendientes de moderación.
     *
     * @return un JSON (como texto) con la lista de reportes.
     */
    @GetMapping(value = "/reportes", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarReportes() {
        return ResponseEntity.ok(repo.listarReportes());
    }

    /**
     * Resuelve un reporte de contenido según la decisión del administrador
     * (aplicar strike, eliminar sin strike, o descartar) y notifica al usuario reportado cuando corresponde.
     *
     * @param id identificador del reporte a resolver.
     * @param dto decisión del administrador y comentario justificativo.
     * @return el resultado de la resolución, o un error 500 si falla.
     */
    @PostMapping(value = "/reportes/{id}/resolver", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> resolverReporte(@PathVariable Long id, @RequestBody ResolverDTO dto) {
        try {
            String decision = dto.decision != null ? dto.decision.toUpperCase() : "DESCARTADO";
            String comentario = dto.comentarioAdmin != null ? dto.comentarioAdmin : "Sin justificación.";

            // 1) Llamar a la función de base de datos
            String resJson = repo.resolverDenuncia(
                id, decision, authContext.usuarioIdActual(), comentario
            );

            // 2) Obtener el reportado para notificarle
            Map<String, Object> rep = jdbcTemplate.queryForMap("SELECT reportador_id, reportado_id FROM reporte_moderacion WHERE id = ?", id);
            Long reportadoId = rep.get("reportado_id") != null ? ((Number) rep.get("reportado_id")).longValue() : null;

            String notifSql = "INSERT INTO notificacion (usuario_id, canal, contenido, estado, tipo, enviado_at) VALUES (?, 'WEBSOCKET'::canal_notificacion, ?, 'PENDIENTE'::estado_notificacion, ?, NOW())";

            if ("STRIKE".equals(decision) && reportadoId != null) {
                jdbcTemplate.update(notifSql, reportadoId, "⚠️ Strike Recibido: " + comentario, "ADVERTENCIA");
            } else if ("ELIMINAR_SIN_STRIKE".equals(decision) && reportadoId != null) {
                jdbcTemplate.update(notifSql, reportadoId, "⚠️ Contenido Removido: " + comentario, "ADVERTENCIA");
            }

            return ResponseEntity.ok(resJson != null ? resJson : "{\"ok\": true}");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    /**
     * Revierte una decisión de moderación tomada automáticamente por la IA,
     * devolviendo el reporte a la cola de revisión manual y restituyendo el
     * strike aplicado al usuario reportado, si correspondía.
     *
     * @param id identificador del reporte cuya decisión automática se revierte.
     * @return confirmación de la reversión, o un error 500 si falla.
     */
    @PostMapping(value = "/reportes/{id}/revertir", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> revertirDecisionIa(@PathVariable Long id) {
        try {
            Map<String, Object> rep = jdbcTemplate.queryForMap("SELECT reportado_id, decidido_por, estado FROM reporte_moderacion WHERE id = ?", id);
            Long reportadoId = rep.get("reportado_id") != null ? ((Number) rep.get("reportado_id")).longValue() : null;
            String estado = (String) rep.get("estado");

            if ("RESUELTO".equals(estado) && reportadoId != null) {
                jdbcTemplate.update("UPDATE usuario SET strikes = GREATEST(0, COALESCE(strikes, 0) - 1) WHERE id = ?", reportadoId);
            }

            jdbcTemplate.update("UPDATE reporte_moderacion SET estado = 'PENDIENTE', revertido = true WHERE id = ?", id);

            return ResponseEntity.ok("{\"ok\": true, \"message\": \"Decisión de la IA revertida con éxito y devuelta a cola manual.\"}");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    // ── Avisos Masivos a la Campanita de Usuarios ─────────────────────────

    /**
     * Lista los avisos masivos enviados previamente a los usuarios.
     *
     * @return un JSON (como texto) con el historial de avisos.
     */
    @GetMapping(value = "/anuncios", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarNotificacionesAdmin() {
        return ResponseEntity.ok(repo.listarNotificacionesAdmin());
    }

    /**
     * Envía un aviso a la campanita de notificaciones de todos los usuarios activos del sistema.
     *
     * @param adminId identificador del administrador que envía el aviso (opcional, para auditoría).
     * @param titulo título del aviso.
     * @param mensaje contenido del aviso.
     * @param tipo tipo de aviso (por defecto {@code INFO}).
     * @return el resultado del registro del aviso.
     */
    @PostMapping(value = "/anuncios", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> crearNotificacionAdmin(
            @RequestParam(required = false) Long adminId,
            @RequestParam String titulo,
            @RequestParam String mensaje,
            @RequestParam(defaultValue = "INFO") String tipo) {
        Long aid = authContext.usuarioIdActual();
        String res = repo.crearNotificacionAdmin(aid, titulo, mensaje, tipo);

        try {
            String contenidoAviso = "📢 " + titulo + ": " + mensaje;
            jdbcTemplate.update(
                "INSERT INTO notificacion (usuario_id, canal, contenido, estado, tipo, enviado_at) " +
                "SELECT id, 'WEBSOCKET'::canal_notificacion, ?, 'PENDIENTE'::estado_notificacion, ?, NOW() FROM usuario WHERE activo = true",
                contenidoAviso, tipo
            );
        } catch (Exception ignored) {}

        return ResponseEntity.ok(res);
    }

    // ── Grupos Detalle ────────────────────────────────────────────────────

    /**
     * Obtiene el detalle de un grupo social (comunidad) para su supervisión:
     * la lista de miembros y sus últimas publicaciones.
     *
     * @param id identificador del grupo.
     * @return un mapa con las listas de miembros y mensajes del grupo; listas vacías si ocurre un error.
     */
    @GetMapping(value = "/grupos/{id}/detalle", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> detalleGrupo(@PathVariable Long id) {
        try {
            List<Map<String, Object>> miembros = jdbcTemplate.queryForList(
                "SELECT gm.grupo_id, gm.usuario_id, gm.rol_en_grupo as rol, gm.joined_at as created_at, u.nombre, u.email FROM grupo_miembro gm JOIN usuario u ON gm.usuario_id = u.id WHERE gm.grupo_id = ?", id
            );
            List<Map<String, Object>> mensajes = jdbcTemplate.queryForList(
                "SELECT pg.id, pg.contenido, pg.imagen_url, pg.created_at, u.nombre as autor_nombre FROM publicacion_grupo pg JOIN usuario u ON pg.usuario_id = u.id WHERE pg.grupo_id = ? ORDER BY pg.created_at DESC LIMIT 50", id
            );
            return ResponseEntity.ok(Map.of("miembros", miembros, "mensajes", mensajes));
        } catch (Exception e) {
            System.err.println("[Admin] Error obteniendo detalle del grupo " + id + ": " + e.getMessage());
            return ResponseEntity.ok(Map.of("miembros", List.of(), "mensajes", List.of()));
        }
    }

    // ── RAG Fuentes & Documentos ──────────────────────────────────────────

    /**
     * Lista las fuentes confiables (URLs) registradas para alimentar la base de conocimiento del asistente IA.
     *
     * @return un JSON (como texto) con la lista de fuentes confiables.
     */
    @GetMapping(value = "/rag/fuentes", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarFuentes() {
        return ResponseEntity.ok(repo.listarFuentesConfiables());
    }

    /**
     * Registra (o actualiza si ya existe) una fuente confiable para el
     * asistente IA y la ingiere de inmediato: la scrapea, la trocea, genera
     * los embeddings reales y los guarda en la base de conocimiento — antes
     * esto solo guardaba la URL en una tabla de registro sin que la IA
     * llegara a leerla nunca.
     *
     * @param dto URL y descripción de la fuente.
     * @return confirmación de registro con la cantidad real de fragmentos ingeridos, o un error 500 si falla.
     */
    @PostMapping(value = "/rag/fuentes", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> agregarFuente(@RequestBody FuenteDTO dto) {
        try {
            jdbcTemplate.update(
                "INSERT INTO fuente_confiable (url, descripcion, creado_por) VALUES (?, ?, ?) ON CONFLICT (url) DO UPDATE SET descripcion = EXCLUDED.descripcion",
                dto.url, dto.descripcion, authContext.usuarioIdActual()
            );
            int fragmentos = ragService.ingestarUrl(dto.url);
            if (fragmentos == 0) {
                return ResponseEntity.ok("{\"ok\": true, \"message\": \"Fuente registrada, pero no se pudo extraer texto útil de esa URL — revisa que sea accesible y tenga contenido real.\", \"fragmentos\": 0}");
            }
            return ResponseEntity.ok("{\"ok\": true, \"message\": \"Fuente registrada e ingerida: " + fragmentos + " fragmentos reales agregados al conocimiento de la IA.\", \"fragmentos\": " + fragmentos + "}");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    /**
     * Reprocesa una fuente confiable ya registrada (por si su contenido
     * cambió): borra sus fragmentos actuales y vuelve a scrapear/ingerir la URL.
     *
     * @param url la URL a reprocesar.
     * @return confirmación con la nueva cantidad real de fragmentos, o un error 500 si falla.
     */
    @PostMapping(value = "/rag/fuentes/reprocesar", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> reprocesarFuente(@RequestParam String url) {
        try {
            int fragmentos = ragService.ingestarUrl(url);
            return ResponseEntity.ok("{\"ok\": true, \"message\": \"Fuente reprocesada: " + fragmentos + " fragmentos reales.\", \"fragmentos\": " + fragmentos + "}");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    /**
     * Lista los documentos PDF registrados en la base de conocimiento del asistente IA.
     *
     * @return un JSON (como texto) con la lista de documentos RAG.
     */
    @GetMapping(value = "/rag/documentos", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarDocumentosRag() {
        return ResponseEntity.ok(repo.listarDocumentosRag());
    }

    /**
     * Devuelve el contenido real (los fragmentos de texto) con el que quedó
     * entrenada la IA para una fuente (PDF o URL) específica, para que el
     * admin pueda ver exactamente qué se extrajo e indexó.
     *
     * @param fuente nombre de archivo o URL, tal como aparece en rag_fragmento.fuente.
     * @return los fragmentos de texto de esa fuente, en orden.
     */
    @GetMapping(value = "/rag/documentos/contenido", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> verContenidoDocumento(@RequestParam String fuente) {
        List<String> fragmentos = jdbcTemplate.queryForList(
            "SELECT contenido FROM rag_fragmento WHERE fuente = ? ORDER BY id", String.class, fuente
        );
        return ResponseEntity.ok(Map.of("fuente", fuente, "total", fragmentos.size(), "fragmentos", fragmentos));
    }

    /**
     * Registra un documento PDF en la base de conocimiento del asistente IA
     * y lo ingiere de inmediato: extrae su texto, lo trocea, genera los
     * embeddings reales y los guarda — antes esto solo guardaba el nombre
     * del archivo con un conteo de fragmentos inventado ("15" fijo) y
     * descartaba el PDF sin leerlo nunca.
     *
     * @param file archivo PDF a registrar.
     * @param adminId identificador del administrador que sube el documento (opcional, para auditoría).
     * @return confirmación de registro con la cantidad real de fragmentos ingeridos, o un error 500 si falla.
     */
    @PostMapping(value = "/rag/subir-pdf", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> registrarDocumentoRag(@RequestParam("file") MultipartFile file, @RequestParam(required = false) Long adminId) {
        try {
            String filename = file.getOriginalFilename() != null ? file.getOriginalFilename() : "documento.pdf";
            int fragmentos = ragService.ingestarPdfBytes(filename, file.getBytes());
            jdbcTemplate.update(
                "INSERT INTO rag_documento (nombre_archivo, total_chunks, creado_por) VALUES (?, ?, ?)",
                filename, fragmentos, authContext.usuarioIdActual()
            );
            if (fragmentos == 0) {
                return ResponseEntity.ok("{\"ok\": true, \"message\": \"El PDF se registró, pero no se pudo extraer texto útil (¿está escaneado como imagen, o vacío?).\", \"fragmentos\": 0}");
            }
            return ResponseEntity.ok("{\"ok\": true, \"message\": \"PDF ingerido: " + fragmentos + " fragmentos reales agregados al conocimiento de la IA.\", \"fragmentos\": " + fragmentos + "}");
        } catch (Exception e) {
            return ResponseEntity.status(500).body("{\"error\": \"" + e.getMessage() + "\"}");
        }
    }

    // ── IoT Monitoreo Solo Lectura ────────────────────────────────────────

    /**
     * Lista, en modo de solo lectura, los dispositivos IoT registrados en todas las viviendas del sistema.
     *
     * @return un JSON (como texto) con la lista de dispositivos.
     */
    @GetMapping(value = "/iot/dispositivos", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarDispositivosIoT() {
        return ResponseEntity.ok(repo.listarDispositivosIoT());
    }

    /** Cuerpo del diagnóstico manual que el admin le manda al dueño de un dispositivo. */
    public record AvisoDispositivoDTO(String mensaje) {}

    /**
     * Manda un mensaje del administrador al propietario de un dispositivo IoT
     * concreto — el camino para los casos que el monitoreo automático no
     * puede redactar solo (por ejemplo, "tu cámara cambió de IP, vuelve a
     * vincularla"): el admin ve el problema, escribe qué hacer, y este
     * endpoint lo entrega por el mismo canal que ya usan los avisos masivos.
     *
     * @param dispositivoId dispositivo sobre el que se está avisando.
     * @param body el mensaje a entregar.
     * @return 404 si el dispositivo no existe o no tiene vivienda asociada.
     */
    @PostMapping(value = "/iot/dispositivos/{dispositivoId}/avisar", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> avisarDuenioDispositivo(@PathVariable Long dispositivoId, @RequestBody AvisoDispositivoDTO body) {
        if (body == null || body.mensaje() == null || body.mensaje().isBlank()) {
            return ResponseEntity.badRequest().body("{\"ok\":false,\"error\":\"El mensaje no puede estar vacío\"}");
        }
        List<Map<String, Object>> filas = jdbcTemplate.queryForList(
            "SELECT c.propietario_id, d.mac_address FROM dispositivo d " +
            "JOIN zona z ON z.id = d.zona_id JOIN casa c ON c.id = z.casa_id " +
            "WHERE d.id = ? AND d.deleted_at IS NULL", dispositivoId);
        if (filas.isEmpty()) {
            return ResponseEntity.status(404).body("{\"ok\":false,\"error\":\"Dispositivo no encontrado\"}");
        }
        Long propietarioId = ((Number) filas.get(0).get("propietario_id")).longValue();
        String mac = String.valueOf(filas.get(0).get("mac_address"));

        jdbcTemplate.update(
            "INSERT INTO notificacion (usuario_id, canal, contenido, estado, tipo, enviado_at) " +
            "VALUES (?, 'WEBSOCKET'::canal_notificacion, ?, 'PENDIENTE'::estado_notificacion, 'MANUAL_DIAGNOSTIC', NOW())",
            propietarioId, "🔧 " + mac + ": " + body.mensaje().trim());

        return ResponseEntity.ok("{\"ok\":true}");
    }

    // ── Exportar Datos (CSV) ────────────────────────────────────────────────

    /**
     * Categorías de exportación disponibles y la consulta real que alimenta
     * cada una. Todas leen directamente de las tablas reales: nada de datos
     * de ejemplo ni de relleno.
     */
    private static final Map<String, String> EXPORT_QUERIES = Map.ofEntries(
        Map.entry("usuarios_activos",
            "SELECT id, nombre, email, rol, casa_id, created_at AS fecha_registro FROM usuario " +
            "WHERE activo = true AND deleted_at IS NULL ORDER BY id"),
        Map.entry("usuarios_eliminados",
            "SELECT id, nombre, email, rol, casa_id, deleted_at FROM usuario " +
            "WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC"),
        Map.entry("usuarios_bloqueados",
            "SELECT id, nombre, email, rol, casa_id, updated_at FROM usuario " +
            "WHERE activo = false AND deleted_at IS NULL ORDER BY id"),
        Map.entry("usuarios_sancionados",
            "SELECT id, nombre, email, rol, strikes FROM usuario " +
            "WHERE strikes > 0 AND deleted_at IS NULL ORDER BY strikes DESC"),
        Map.entry("usuarios_baneados",
            "SELECT id, nombre, email, rol FROM usuario " +
            "WHERE baneado_comunidad = true AND deleted_at IS NULL ORDER BY id"),
        Map.entry("miembros",
            "SELECT id, nombre, email, casa_id, activo, created_at AS fecha_registro FROM usuario " +
            "WHERE rol = 'MIEMBRO' AND deleted_at IS NULL ORDER BY id"),
        Map.entry("por_plan",
            "SELECT c.id AS casa_id, c.nombre AS casa, p.nombre AS plan, s.estado, s.created_at AS suscrito_desde " +
            "FROM suscripcion s JOIN casa c ON c.id = s.casa_id JOIN plan p ON p.id = s.plan_id " +
            "ORDER BY p.nombre, c.id"),
        Map.entry("dispositivos_iot",
            // Antes solo traía casa_id en crudo: con varias viviendas que
            // repiten las mismas categorías de dispositivo (todas tienen un
            // LED_ROOM1, un SERVO_VENTANA...), el CSV mostraba filas que
            // parecían duplicadas sin decir de qué vivienda era cada una.
            "SELECT d.id, d.mac_address, d.tipo, d.categoria, d.estado, d.ultima_conexion, " +
            "c.id AS casa_id, c.nombre AS casa, u.nombre AS propietario, u.email AS propietario_email " +
            "FROM dispositivo d JOIN zona z ON z.id = d.zona_id JOIN casa c ON c.id = z.casa_id " +
            "LEFT JOIN usuario u ON u.id = c.propietario_id " +
            "WHERE d.deleted_at IS NULL ORDER BY c.id, d.id"),
        Map.entry("camaras_por_casa",
            "SELECT casa_id, COUNT(*) AS total_camaras FROM camara WHERE activo = true " +
            "GROUP BY casa_id ORDER BY total_camaras DESC"),
        Map.entry("suscripciones",
            "SELECT s.id, c.nombre AS casa, p.nombre AS plan, s.estado, s.fecha_inicio, s.fecha_fin, s.metodo_pago " +
            "FROM suscripcion s JOIN casa c ON c.id = s.casa_id JOIN plan p ON p.id = s.plan_id ORDER BY s.id")
    );

    /**
     * Lista las categorías de exportación disponibles (id y etiqueta legible),
     * para armar el menú de "Exportar Datos" en el panel sin repetir la lista
     * de nombres en el frontend.
     *
     * @return la lista de categorías disponibles.
     */
    @GetMapping(value = "/exportar/categorias", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<List<Map<String, String>>> categoriasExportacion() {
        List<Map<String, String>> categorias = List.of(
            Map.of("id", "usuarios_activos", "etiqueta", "Usuarios activos"),
            Map.of("id", "usuarios_eliminados", "etiqueta", "Usuarios eliminados"),
            Map.of("id", "usuarios_bloqueados", "etiqueta", "Usuarios bloqueados"),
            Map.of("id", "usuarios_sancionados", "etiqueta", "Usuarios sancionados"),
            Map.of("id", "usuarios_baneados", "etiqueta", "Usuarios baneados de comunidad"),
            Map.of("id", "miembros", "etiqueta", "Miembros"),
            Map.of("id", "por_plan", "etiqueta", "Suscripciones por plan"),
            Map.of("id", "dispositivos_iot", "etiqueta", "Dispositivos IoT"),
            Map.of("id", "camaras_por_casa", "etiqueta", "Cámaras por casa"),
            Map.of("id", "suscripciones", "etiqueta", "Suscripciones")
        );
        return ResponseEntity.ok(categorias);
    }

    /**
     * Exporta una categoría de datos reales del sistema como CSV, con BOM
     * UTF-8 al inicio del archivo para que Excel muestre bien los acentos y
     * la ñ en vez de caracteres ilegibles (el problema clásico de abrir un
     * CSV en UTF-8 sin BOM en Excel).
     *
     * @param tipo identificador de la categoría (ver {@link #categoriasExportacion()}).
     * @return el archivo CSV como descarga adjunta, o 400 si la categoría no existe.
     */
    @GetMapping(value = "/exportar")
    public ResponseEntity<byte[]> exportarDatos(@RequestParam String tipo) {
        String query = EXPORT_QUERIES.get(tipo);
        if (query == null) {
            return ResponseEntity.badRequest().body("Categoría desconocida".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }

        List<Map<String, Object>> filas = jdbcTemplate.queryForList(query);
        byte[] archivo = csvConBom(construirCsv(filas));

        return ResponseEntity.ok()
            .header("Content-Disposition", "attachment; filename=\"" + tipo + ".csv\"")
            .contentType(MediaType.parseMediaType("text/csv; charset=UTF-8"))
            .body(archivo);
    }

    /**
     * Arma el texto CSV (separador `,`, salto de línea `\r\n`) a partir de
     * una lista de filas. Cada valor se escapa entre comillas si contiene
     * coma, comillas o salto de línea, y los que empiezan con `=`, `+`, `-`
     * o `@` llevan un apóstrofo delante: Excel/Sheets los interpreta como
     * fórmulas si no, y un nombre o email malicioso podría ejecutar código
     * al abrir el archivo (inyección de fórmulas CSV).
     */
    /**
     * Antepone el BOM UTF-8 a un CSV para que Excel lo abra con los acentos
     * correctos en vez de interpretarlo como texto sin codificar.
     */
    private byte[] csvConBom(String csv) {
        byte[] bom = new byte[]{(byte) 0xEF, (byte) 0xBB, (byte) 0xBF};
        byte[] cuerpo = csv.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        byte[] archivo = new byte[bom.length + cuerpo.length];
        System.arraycopy(bom, 0, archivo, 0, bom.length);
        System.arraycopy(cuerpo, 0, archivo, bom.length, cuerpo.length);
        return archivo;
    }

    private String construirCsv(List<Map<String, Object>> filas) {
        StringBuilder sb = new StringBuilder();
        if (filas.isEmpty()) {
            return "sin_datos\r\n";
        }
        List<String> columnas = new java.util.ArrayList<>(filas.get(0).keySet());
        sb.append(String.join(",", columnas)).append("\r\n");
        for (Map<String, Object> fila : filas) {
            List<String> valores = new java.util.ArrayList<>();
            for (String col : columnas) {
                valores.add(escaparCsv(fila.get(col)));
            }
            sb.append(String.join(",", valores)).append("\r\n");
        }
        return sb.toString();
    }

    private String escaparCsv(Object valor) {
        String texto = valor == null ? "" : valor.toString();
        if (!texto.isEmpty() && "=+-@".indexOf(texto.charAt(0)) >= 0) {
            texto = "'" + texto;
        }
        boolean necesitaComillas = texto.contains(",") || texto.contains("\"") || texto.contains("\n") || texto.contains("\r");
        if (necesitaComillas) {
            texto = "\"" + texto.replace("\"", "\"\"") + "\"";
        }
        return texto;
    }

    // ── Explorador de Datos Avanzado ────────────────────────────────────────

    /**
     * Vista unificada de usuarios, dispositivos IoT y suscripciones en una
     * sola tabla real (id con prefijo por categoría, etiqueta, detalle,
     * estado normalizado y última actividad), para el buscador/filtro del
     * Explorador de Datos. El filtrado por texto/categoría/estado se hace en
     * el frontend: con el volumen de datos actual (decenas de filas) no hace
     * falta paginar ni filtrar en el servidor.
     */
    private static final String EXPLORADOR_QUERY =
        "SELECT 'Usuario' AS categoria, u.id AS id, u.nombre AS nombre, u.email AS correo, " +
        // Un usuario nunca queda "Eliminado" en este panel: los 3 strikes son
        // justo lo que hoy pone deleted_at/activo=false (ver fn_resolver_denuncia),
        // así que si llegó a 3 strikes es Sancionado; si está inactivo por
        // cualquier otro motivo (lo bloqueó un admin) es Bloqueado. Solo 3 estados.
        "  (CASE WHEN COALESCE(u.strikes, 0) >= 3 THEN 'Sancionado' " +
        "        WHEN u.activo = false OR u.deleted_at IS NOT NULL THEN 'Bloqueado' " +
        "        ELSE 'Activa' END) AS estado, " +
        "  (SELECT COUNT(*) FROM camara cam WHERE cam.casa_id = u.casa_id AND cam.conectada = true) AS camaras_conectadas, " +
        "  (CASE WHEN EXISTS (SELECT 1 FROM dispositivo d JOIN zona z ON z.id = d.zona_id WHERE z.casa_id = u.casa_id AND d.deleted_at IS NULL) " +
        "        THEN 'Sí' ELSE 'No' END) AS iot_implementado, " +
        "  (SELECT COUNT(*) FROM perro per WHERE per.casa_id = u.casa_id AND per.deleted_at IS NULL) AS mascotas, " +
        "  (SELECT pl.nombre FROM suscripcion sub JOIN plan pl ON pl.id = sub.plan_id " +
        "     WHERE sub.casa_id = u.casa_id ORDER BY (sub.estado::text = 'ACTIVA') DESC, sub.created_at DESC LIMIT 1) AS plan, " +
        "  NULL::text AS detalle, " +
        "  COALESCE(u.ultima_conexion, u.created_at) AS ultima_actividad, " +
        "  u.created_at AS fecha_registro " +
        "FROM usuario u " +
        "UNION ALL " +
        // El correo va al propietario de la vivienda, igual que en la fila
        // de Suscripción de abajo: es el mismo criterio ("¿de quién es esto?")
        // aplicado a la misma columna. Antes iba NULL a secas, así que ningún
        // filtro de texto ni la vista previa podían decir de qué usuario era
        // cada dispositivo — el propio detalle mostraba solo tipo·categoría,
        // sin la vivienda, y con varias casas todo se veía repetido.
        "SELECT 'Dispositivo IoT', d.id, COALESCE(d.modelo, d.mac_address, 'Dispositivo #' || d.id), diot_u.email, " +
        "  (CASE WHEN d.estado::text = 'ACTIVO' THEN 'Activa' ELSE 'Bloqueado' END), " +
        "  NULL, NULL, NULL, NULL, (d.tipo::text || ' · ' || d.categoria::text || ' · ' || COALESCE(diot_c.nombre, 'sin vivienda')), " +
        "  COALESCE(d.ultima_conexion, d.created_at), d.created_at " +
        "FROM dispositivo d " +
        "JOIN zona diot_z ON diot_z.id = d.zona_id " +
        "JOIN casa diot_c ON diot_c.id = diot_z.casa_id " +
        "LEFT JOIN usuario diot_u ON diot_u.id = diot_c.propietario_id " +
        "WHERE d.deleted_at IS NULL " +
        "UNION ALL " +
        // La suscripción es de la casa, pero lo legible para un admin es
        // "quién la contrató" — el propietario real de esa casa, no el
        // nombre de la casa (que no dice nada por sí solo).
        "SELECT 'Suscripción', s.id, pu.nombre, pu.email, " +
        "  (CASE WHEN s.estado::text = 'ACTIVA' THEN 'Activa' ELSE 'Bloqueado' END), " +
        "  NULL, NULL, NULL, p.nombre, NULL, " +
        "  COALESCE(s.updated_at, s.created_at), s.created_at " +
        "FROM suscripcion s JOIN casa c ON c.id = s.casa_id JOIN usuario pu ON pu.id = c.propietario_id JOIN plan p ON p.id = s.plan_id " +
        "UNION ALL " +
        "SELECT 'Grupo', g.id, g.nombre, NULL, 'Activa', NULL, NULL, NULL, NULL, COALESCE(g.descripcion, ''), " +
        "  COALESCE(g.updated_at, g.created_at), g.created_at " +
        "FROM grupo g";

    /**
     * Arma la consulta filtrada del Explorador a partir de los mismos
     * parámetros que usa el frontend (categoría, estado, texto libre, rango
     * de fecha de registro), para que la vista previa, el CSV, el PDF y el
     * correo exporten siempre exactamente lo que el administrador filtró —
     * antes cada exportación traía TODO sin importar el filtro activo.
     */
    private List<Map<String, Object>> filasExplorador(String categoria, String estado, String q, String fechaDesde, String fechaHasta) {
        StringBuilder sql = new StringBuilder("SELECT * FROM (" + EXPLORADOR_QUERY + ") t WHERE 1=1");
        List<Object> params = new java.util.ArrayList<>();

        if (categoria != null && !categoria.isBlank() && !categoria.equalsIgnoreCase("Todos")) {
            sql.append(" AND t.categoria = ?");
            params.add(categoria);
        }
        if (estado != null && !estado.isBlank() && !estado.equalsIgnoreCase("Todos")) {
            sql.append(" AND t.estado = ?");
            params.add(estado);
        }
        if (q != null && !q.isBlank()) {
            sql.append(" AND (t.nombre ILIKE ? OR t.correo ILIKE ? OR CAST(t.id AS text) ILIKE ?)");
            String like = "%" + q.trim() + "%";
            params.add(like); params.add(like); params.add(like);
        }
        if (fechaDesde != null && !fechaDesde.isBlank()) {
            sql.append(" AND t.fecha_registro >= ?::date");
            params.add(fechaDesde);
        }
        if (fechaHasta != null && !fechaHasta.isBlank()) {
            sql.append(" AND t.fecha_registro < (?::date + INTERVAL '1 day')");
            params.add(fechaHasta);
        }
        sql.append(" ORDER BY t.ultima_actividad DESC NULLS LAST");

        return jdbcTemplate.queryForList(sql.toString(), params.toArray());
    }

    /**
     * Datos unificados (usuarios, IoT, suscripciones, grupos) para el
     * Explorador de Datos Avanzado, en JSON, filtrados con los mismos
     * criterios que se usan para exportar.
     *
     * @return la lista de registros reales, más recientes primero.
     */
    @GetMapping(value = "/explorador", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<List<Map<String, Object>>> explorador(
            @RequestParam(required = false) String categoria,
            @RequestParam(required = false) String estado,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String fechaDesde,
            @RequestParam(required = false) String fechaHasta) {
        return ResponseEntity.ok(filasExplorador(categoria, estado, q, fechaDesde, fechaHasta));
    }

    /**
     * Métricas rápidas reales para el panel del Explorador: total de
     * registros unificados y la tasa de crecimiento de usuarios del último
     * mes con datos frente al mes anterior. Si no hay al menos dos meses con
     * registros, la tasa se reporta como {@code null} en vez de inventar un
     * número.
     *
     * @return {@code total_registros} y {@code tasa_crecimiento_pct}.
     */
    @GetMapping(value = "/explorador/metricas", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> exploradorMetricas() {
        Integer total = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM (" + EXPLORADOR_QUERY + ") t", Integer.class);

        List<Map<String, Object>> meses = jdbcTemplate.queryForList(
            "SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS mes, COUNT(*) AS total " +
            "FROM usuario WHERE deleted_at IS NULL " +
            "GROUP BY 1 ORDER BY 1 DESC LIMIT 2"
        );

        Double tasa = null;
        if (meses.size() == 2) {
            double actual = ((Number) meses.get(0).get("total")).doubleValue();
            double anterior = ((Number) meses.get(1).get("total")).doubleValue();
            if (anterior > 0) {
                tasa = Math.round(((actual - anterior) / anterior) * 1000) / 10.0;
            }
        }

        Map<String, Object> resultado = new java.util.LinkedHashMap<>();
        resultado.put("total_registros", total);
        resultado.put("tasa_crecimiento_pct", tasa);
        return ResponseEntity.ok(resultado);
    }

    /**
     * Exporta a CSV los datos del Explorador que coincidan con el filtro
     * activo (los mismos parámetros que {@link #explorador}), con BOM UTF-8
     * para que Excel muestre bien acentos y ñ.
     *
     * @return el CSV como descarga adjunta.
     */
    @GetMapping(value = "/explorador/csv")
    public ResponseEntity<byte[]> exploradorCsv(
            @RequestParam(required = false) String categoria,
            @RequestParam(required = false) String estado,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String fechaDesde,
            @RequestParam(required = false) String fechaHasta) {
        List<Map<String, Object>> filas = filasExplorador(categoria, estado, q, fechaDesde, fechaHasta);
        byte[] archivo = csvConBom(construirCsv(filas));
        return ResponseEntity.ok()
            .header("Content-Disposition", "attachment; filename=\"explorador-datos.csv\"")
            .contentType(MediaType.parseMediaType("text/csv; charset=UTF-8"))
            .body(archivo);
    }

    /**
     * Genera un reporte PDF formal con los datos del Explorador que
     * coincidan con el filtro activo, con paginación automática.
     *
     * @return el PDF como descarga adjunta.
     */
    @GetMapping(value = "/explorador/pdf")
    public ResponseEntity<byte[]> exploradorPdf(
            @RequestParam(required = false) String categoria,
            @RequestParam(required = false) String estado,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String fechaDesde,
            @RequestParam(required = false) String fechaHasta) {
        List<Map<String, Object>> filas = filasExplorador(categoria, estado, q, fechaDesde, fechaHasta);
        try {
            byte[] pdf = generarPdfReporte(filas);
            return ResponseEntity.ok()
                .header("Content-Disposition", "attachment; filename=\"explorador-datos.pdf\"")
                .contentType(MediaType.APPLICATION_PDF)
                .body(pdf);
        } catch (Exception e) {
            return ResponseEntity.status(500).body(("Error generando PDF: " + e.getMessage())
                .getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }
    }

    /** Datos para enviar el reporte del Explorador por correo. */
    public static class EnviarReporteDTO {
        public String email;
        public String formato; // "csv" o "pdf"
        public String categoria;
        public String estado;
        public String q;
        public String fechaDesde;
        public String fechaHasta;
    }

    /**
     * Envía por correo el reporte del Explorador de Datos —ya filtrado con
     * el mismo criterio activo en pantalla— como adjunto CSV o PDF. Es un
     * envío inmediato, no una programación recurrente: todavía no hay un
     * scheduler conectado a esta acción.
     *
     * @param dto correo de destino, formato del adjunto y filtro activo.
     * @return confirmación del envío, o 400/500 según el caso.
     */
    @PostMapping(value = "/explorador/enviar-reporte", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> enviarReporte(@RequestBody EnviarReporteDTO dto) {
        if (dto == null || dto.email == null || !dto.email.contains("@")) {
            return ResponseEntity.badRequest().body(Map.of("ok", false, "error", "Correo inválido"));
        }
        List<Map<String, Object>> filas = filasExplorador(dto.categoria, dto.estado, dto.q, dto.fechaDesde, dto.fechaHasta);
        boolean esPdf = "pdf".equalsIgnoreCase(dto.formato);
        try {
            byte[] adjunto;
            String nombreArchivo;
            if (esPdf) {
                adjunto = generarPdfReporte(filas);
                nombreArchivo = "explorador-datos.pdf";
            } else {
                adjunto = csvConBom(construirCsv(filas));
                nombreArchivo = "explorador-datos.csv";
            }
            boolean enviado = mailService.sendHtmlEmailWithAttachmentSync(
                dto.email, "Reporte Huellitas — Explorador de Datos",
                "<p>Adjunto el reporte solicitado con los datos actuales del sistema (" + filas.size() + " registros).</p>",
                nombreArchivo, adjunto
            );
            return ResponseEntity.ok(Map.of("ok", enviado));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("ok", false, "error", e.getMessage()));
        }
    }

    /** Arma un PDF tabular simple (título + filas) a partir de los datos del Explorador, con salto de página automático. */
    private byte[] generarPdfReporte(List<Map<String, Object>> filas) throws Exception {
        try (org.apache.pdfbox.pdmodel.PDDocument doc = new org.apache.pdfbox.pdmodel.PDDocument()) {
            org.apache.pdfbox.pdmodel.font.PDFont fontBold = new org.apache.pdfbox.pdmodel.font.PDType1Font(
                org.apache.pdfbox.pdmodel.font.Standard14Fonts.FontName.HELVETICA_BOLD);
            org.apache.pdfbox.pdmodel.font.PDFont font = new org.apache.pdfbox.pdmodel.font.PDType1Font(
                org.apache.pdfbox.pdmodel.font.Standard14Fonts.FontName.HELVETICA);

            float margen = 40;
            float alturaFila = 16;
            String[] columnas = {"Categoría", "ID", "Nombre", "Correo", "Estado", "Cámaras", "IoT", "Mascotas", "Plan", "Últ. actividad"};
            float[] anchos = {65, 30, 95, 130, 55, 45, 35, 55, 65, 80};

            org.apache.pdfbox.pdmodel.common.PDRectangle apaisada =
                new org.apache.pdfbox.pdmodel.common.PDRectangle(org.apache.pdfbox.pdmodel.common.PDRectangle.A4.getHeight(), org.apache.pdfbox.pdmodel.common.PDRectangle.A4.getWidth());
            org.apache.pdfbox.pdmodel.PDPage pagina = new org.apache.pdfbox.pdmodel.PDPage(apaisada);
            doc.addPage(pagina);
            org.apache.pdfbox.pdmodel.PDPageContentStream cs = new org.apache.pdfbox.pdmodel.PDPageContentStream(doc, pagina);
            float y = pagina.getMediaBox().getHeight() - margen;

            cs.setFont(fontBold, 16);
            cs.beginText();
            cs.newLineAtOffset(margen, y);
            cs.showText("Huellitas — Explorador de Datos");
            cs.endText();
            y -= 22;

            cs.setFont(font, 9);
            cs.beginText();
            cs.newLineAtOffset(margen, y);
            cs.showText(filas.size() + " registros reales, generado " + java.time.LocalDate.now());
            cs.endText();
            y -= 20;

            cs.setFont(fontBold, 9);
            cs.beginText();
            cs.newLineAtOffset(margen, y);
            for (int i = 0; i < columnas.length; i++) {
                if (i > 0) cs.newLineAtOffset(anchos[i - 1], 0);
                cs.showText(columnas[i]);
            }
            cs.endText();
            y -= alturaFila;
            cs.setFont(font, 8);

            for (Map<String, Object> fila : filas) {
                if (y < margen + alturaFila) {
                    cs.close();
                    pagina = new org.apache.pdfbox.pdmodel.PDPage(apaisada);
                    doc.addPage(pagina);
                    cs = new org.apache.pdfbox.pdmodel.PDPageContentStream(doc, pagina);
                    y = pagina.getMediaBox().getHeight() - margen;
                    cs.setFont(font, 8);
                }
                Object[] valores = {
                    fila.get("categoria"), fila.get("id"), fila.get("nombre"), fila.get("correo"),
                    fila.get("estado"), fila.get("camaras_conectadas"), fila.get("iot_implementado"),
                    fila.get("mascotas"), fila.get("plan"), fila.get("ultima_actividad")
                };
                cs.beginText();
                cs.newLineAtOffset(margen, y);
                for (int i = 0; i < valores.length; i++) {
                    String texto = valores[i] == null ? "" : valores[i].toString();
                    if (texto.length() > 28) texto = texto.substring(0, 25) + "...";
                    if (i > 0) cs.newLineAtOffset(anchos[i - 1], 0);
                    cs.showText(texto);
                }
                cs.endText();
                y -= alturaFila;
            }
            cs.close();

            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            doc.save(out);
            return out.toByteArray();
        }
    }
}