package com.huellitas.social;

import com.huellitas.config.AuthContext;
import com.huellitas.ia.ModeracionIaService;
import com.huellitas.ia.ModeracionService;
import com.huellitas.ia.SightengineService;
import com.huellitas.ia.ContenidoMascotaService;
import com.huellitas.storage.S3Service;
import com.huellitas.storage.S3AvatarService;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import com.huellitas.utils.ValidationUtils;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.text.Normalizer;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Superficie principal de la red social de la comunidad: feed de
 * publicaciones, comentarios, reacciones, denuncias, grupos temáticos con
 * su propio muro, y sugerencias de lenguaje inclusivo. La mayoría de
 * escrituras de texto pasan primero por {@link ModeracionService} antes de
 * guardarse, y las denuncias por {@link ModeracionIaService}.
 */
@RestController
@RequestMapping("/api/huellitas/social")
public class SocialController {
    private final SocialRepository repo;
    private final JdbcTemplate jdbcTemplate;
    private final ModeracionIaService moderacionIaService;
    private final ModeracionService moderacionService;
    private final SightengineService sightengineService;
    private final ContenidoMascotaService contenidoMascotaService;
    private final S3Service s3Service;
    private final S3AvatarService s3AvatarService;
    private final SimpMessagingTemplate messagingTemplate;
    private final AuthContext authContext;

    public SocialController(SocialRepository repo, JdbcTemplate jdbcTemplate, ModeracionIaService moderacionIaService, ModeracionService moderacionService, SightengineService sightengineService, ContenidoMascotaService contenidoMascotaService, S3Service s3Service, S3AvatarService s3AvatarService, SimpMessagingTemplate messagingTemplate, AuthContext authContext) {
        this.repo = repo;
        this.jdbcTemplate = jdbcTemplate;
        this.moderacionIaService = moderacionIaService;
        this.moderacionService = moderacionService;
        this.sightengineService = sightengineService;
        this.contenidoMascotaService = contenidoMascotaService;
        this.s3Service = s3Service;
        this.s3AvatarService = s3AvatarService;
        this.messagingTemplate = messagingTemplate;
        this.authContext = authContext;
    }

    /**
     * Identidad real del usuario que hace la petición, según el JWT ya
     * validado por {@link com.huellitas.config.JwtAuthenticationFilter} —
     * nunca el {@code usuarioId} que venga en el body/query, que cualquiera
     * puede falsificar para actuar en nombre de otra persona.
     */
    private Long usuarioAutenticado() {
        return authContext.usuarioIdActual();
    }

    /**
     * Avisa por WebSocket a los clientes suscritos al feed social que hay contenido nuevo para refrescar.
     */
    private void notifySocialUpdate() {
        messagingTemplate.convertAndSend("/topic/social/feed", "{\"event\":\"UPDATE\"}");
    }

    /** Puntaje desde el cual se avisa al usuario pero se le deja decidir si publica igual. Bajado de 0.35 a 0.30 para ser más estrictos. */
    private static final double SIGHTENGINE_WARN_THRESHOLD = 0.30;
    /**
     * Puntaje desde el cual se bloquea directamente, sin importar si el
     * usuario confirmó: se aplica strike y nunca se guarda. Calibrado con
     * un caso real ("Quiero matar a los perros" dio violent=0.73 en
     * Sightengine) — 0.70 lo trata como grave/comprobable, tal como se
     * espera para una amenaza explícita de violencia contra mascotas.
     */
    private static final double SIGHTENGINE_BLOCK_THRESHOLD = 0.70;

    /**
     * Verbos que, combinados con una palabra de animal/mascota en la misma
     * publicación, indican maltrato animal explícito — fuerzan bloqueo
     * directo (0.90) sin importar lo que diga Sightengine por sí solo. Esta
     * comunidad es de cuidado animal: el maltrato hacia mascotas es un tema
     * propio y sensible que un modelo genérico de toxicidad no prioriza.
     */
    private static final List<String> VERBOS_MALTRATO_GRAVE = List.of(
        "matar", "mate", "mato", "mataste", "matarlo", "matarla", "matarlos", "matarlas",
        "golpear", "golpeando", "golpealo", "golpeenlo", "maltratar", "maltrato", "maltratando",
        "torturar", "torturando", "ahorcar", "envenenar", "quemar", "quemarlo", "patear", "pateando",
        "pegar", "pegarle", "pegale", "azotar", "apalear", "descuartizar", "degollar"
    );

    /**
     * Verbos/expresiones más leves de hostilidad hacia animales — fuerzan
     * al menos advertencia (0.45), para que casos como "odio a los
     * perritos" (que Sightengine solo puntuó 0.25, por debajo del umbral)
     * no pasen desapercibidos.
     */
    private static final List<String> VERBOS_HOSTILIDAD_LEVE = List.of(
        "odio", "odiar", "odiando", "detesto", "detestar", "asco me dan", "abandonar", "abandonado",
        "abandonada", "lastimar", "lastimando", "herir", "hiriendo", "dano", "danar"
    );

    private static final List<String> PALABRAS_ANIMAL = List.of(
        "perro", "perros", "perrito", "perritos", "perra", "perras",
        "gato", "gatos", "gatito", "gatitos", "gata", "gatas",
        "mascota", "mascotas", "animal", "animales", "cachorro", "cachorros"
    );

    /**
     * Resultado de {@link #evaluarModeracion}: si {@code permitir} es
     * {@code true}, el llamador debe continuar y guardar el contenido; si es
     * {@code false}, debe devolver {@code respuesta} tal cual (que puede ser
     * una advertencia recuperable con HTTP 200, o un bloqueo definitivo).
     */
    private record VeredictoModeracion(boolean permitir, ResponseEntity<String> respuesta) {}

    /**
     * Quita tildes y pasa a minúsculas, para que la búsqueda de palabras
     * clave no falle por "dañar" vs "danar" o mayúsculas/minúsculas.
     */
    private String normalizarTexto(String texto) {
        if (texto == null) return "";
        String sinTildes = Normalizer.normalize(texto.toLowerCase(), Normalizer.Form.NFD)
            .replaceAll("\\p{M}", "");
        return sinTildes;
    }

    /**
     * Capa de palabras clave propia del dominio: si el texto menciona a la
     * vez una palabra de animal/mascota y un verbo de maltrato, sube el
     * puntaje aunque Sightengine no lo detecte como grave por sí solo — es
     * el complemento pensado específicamente para esta comunidad de cuidado
     * animal, donde el maltrato/odio hacia mascotas es más sensible que en
     * una red social genérica.
     */
    private double puntajePalabrasClaveAnimal(String texto) {
        String t = normalizarTexto(texto);
        if (t.isBlank()) return 0;
        boolean mencionaAnimal = PALABRAS_ANIMAL.stream().anyMatch(t::contains);
        if (!mencionaAnimal) return 0;
        if (VERBOS_MALTRATO_GRAVE.stream().anyMatch(t::contains)) return 0.90;
        if (VERBOS_HOSTILIDAD_LEVE.stream().anyMatch(t::contains)) return 0.45;
        return 0;
    }

    /**
     * Evalúa un contenido en varias capas antes de guardarlo:
     * 1) {@link ModeracionService} (hoy deshabilitado) — si bloquea, aplica
     *    strike (mecanismo legado, sin tocar) y corta con 400.
     * 2) {@link SightengineService} sobre el texto (combinado con la capa
     *    de palabras clave de maltrato animal) y, si hay imagen, tres
     *    verificaciones sobre ella:
     *    a) Puntaje de contenido explícito/violento (desnudez, gore, etc.) — igual que el texto, arriba de 0.70 bloquea con strike.
     *    b) Rostro humano detectado — se bloquea sin strike (la comunidad es solo de mascotas, no de personas), a menos que confirmado (deja pasar con advertencia).
     *    c) La imagen no es de una mascota/animal (clasificador de visión) — igual, se bloquea sin strike salvo confirmación.
     *    Un puntaje ≥ {@link #SIGHTENGINE_BLOCK_THRESHOLD} aplica strike real y corta con 422 — nunca se guarda.
     *    Un puntaje ≥ {@link #SIGHTENGINE_WARN_THRESHOLD} (o una advertencia de imagen) y {@code !confirmado}
     *    devuelve una advertencia (200, `advertencia:true`) sin guardar nada.
     *
     * @param usuarioId identificador del autor del contenido.
     * @param texto contenido de texto a evaluar.
     * @param imagenUrl URL de la imagen asociada, si la hay.
     * @param confirmado si el usuario ya vio la advertencia y decidió publicar de todas formas.
     */
    private VeredictoModeracion evaluarModeracion(Long usuarioId, String texto, String imagenUrl, boolean confirmado) {
        var modRes = moderacionService.moderarContenido(texto, imagenUrl);
        if (modRes.bloquear()) {
            repo.sistemaDarStrike(usuarioId, modRes.motivo());
            String msg = "Contenido bloqueado por moderación automática: " + modRes.motivo();
            return new VeredictoModeracion(false, ResponseEntity.status(400)
                .body("{\"ok\":false,\"error\":\"" + msg + "\",\"message\":\"" + msg + "\"}"));
        }

        boolean hayImagen = imagenUrl != null && !imagenUrl.isBlank();
        var imagenRes = hayImagen ? sightengineService.validarImagenPorUrl(imagenUrl) : null;

        // ── Reglas de imagen "todo o nada": sin escala de advertencia por
        // puntaje, se bloquean directas salvo que el usuario ya confirmó.
        if (hayImagen) {
            if (imagenRes.getScores().containsKey("rostro_humano") && !confirmado) {
                return new VeredictoModeracion(false, ResponseEntity.ok(
                    "{\"ok\":true,\"advertencia\":true,\"mensaje\":\"Esta comunidad es solo de mascotas: no se permiten fotos de personas. Si crees que es un error, puedes continuar de todas formas.\"}"
                ));
            }
            var veredictoMascota = contenidoMascotaService.esContenidoDeMascota(imagenUrl);
            if (veredictoMascota.disponible() && !veredictoMascota.esMascota() && !confirmado) {
                // motivo() lo genera un modelo de IA (texto libre) — se escapa
                // antes de meterlo en el JSON armado a mano, para que unas
                // comillas en la respuesta del modelo no rompan la respuesta.
                String motivoCrudo = veredictoMascota.motivo();
                String motivo = motivoCrudo != null && !motivoCrudo.isBlank()
                    ? " (" + escaparJson(motivoCrudo) + ")" : "";
                return new VeredictoModeracion(false, ResponseEntity.ok(
                    "{\"ok\":true,\"advertencia\":true,\"mensaje\":\"Esta comunidad es solo para fotos de mascotas y animales" + motivo + ". Si crees que es un error, puedes continuar de todas formas.\"}"
                ));
            }
        }

        var textoRes = sightengineService.validarTexto(texto);
        double scorePalabrasClave = puntajePalabrasClaveAnimal(texto);
        double scoreTexto = Math.max(textoRes.maxScore(), scorePalabrasClave);
        double scoreImagen = imagenRes != null ? imagenRes.maxScore() : 0.0;
        double score = Math.max(scoreTexto, scoreImagen);
        String categoria = scorePalabrasClave >= scoreTexto && scorePalabrasClave > 0 ? "maltrato_animal"
            : (scoreImagen > scoreTexto && imagenRes != null ? imagenRes.categoriaMasAlta() : textoRes.categoriaMasAlta());

        if (score >= SIGHTENGINE_BLOCK_THRESHOLD) {
            String motivoLegible = categoriaLegible(categoria);
            String msg = "No puedes publicar esto. El contenido infringe las normas de la comunidad (" + motivoLegible + ") y fue eliminado. Se te aplicó un strike — al llegar a 3 strikes tu cuenta queda bloqueada.";
            if (usuarioId != null) {
                jdbcTemplate.update("UPDATE usuario SET strikes = COALESCE(strikes, 0) + 1 WHERE id = ?", usuarioId);
                Integer strikesActuales = jdbcTemplate.queryForObject("SELECT COALESCE(strikes, 0) FROM usuario WHERE id = ?", Integer.class, usuarioId);
                String contenidoNotificacion = "⚠️ Se eliminó tu publicación por " + motivoLegible + ". Strike " + strikesActuales + "/3"
                    + (strikesActuales != null && strikesActuales >= 3 ? " — tu cuenta fue bloqueada por acumular 3 strikes." : ".");
                jdbcTemplate.update(
                    "INSERT INTO notificacion (usuario_id, canal, contenido, estado, tipo, enviado_at) VALUES (?, 'WEBSOCKET'::canal_notificacion, ?, 'PENDIENTE'::estado_notificacion, 'ADVERTENCIA', NOW())",
                    usuarioId, contenidoNotificacion
                );
            }
            return new VeredictoModeracion(false, ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY)
                .body("{\"ok\":false,\"eliminado\":true,\"error\":\"" + msg + "\",\"message\":\"" + msg + "\"}"));
        }
        if (score >= SIGHTENGINE_WARN_THRESHOLD && !confirmado) {
            return new VeredictoModeracion(false, ResponseEntity.ok(
                "{\"ok\":true,\"advertencia\":true,\"mensaje\":\"Este contenido podría romper nuestras reglas y afectar a otros usuarios. Te recomendamos no subirlo.\"}"
            ));
        }
        return new VeredictoModeracion(true, null);
    }

    /** Escapa comillas y barras invertidas para insertar texto libre (p. ej. de un modelo de IA) dentro de un JSON armado a mano. */
    private String escaparJson(String texto) {
        return texto.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ").replace("\r", " ");
    }

    /** Traduce las categorías de Sightengine (y las propias) a una etiqueta legible en español, para el mensaje que ve el usuario. */
    private String categoriaLegible(String categoria) {
        if (categoria == null) return "contenido inapropiado";
        return switch (categoria) {
            case "violent", "violence" -> "violencia";
            case "toxic" -> "toxicidad";
            case "insulting" -> "insultos";
            case "discriminatory" -> "discriminación/racismo";
            case "sexual" -> "contenido sexual";
            case "nudity" -> "desnudez";
            case "offensive" -> "símbolos ofensivos";
            case "gore" -> "contenido gráfico/violento";
            case "rostro_humano" -> "foto de una persona";
            case "maltrato_animal" -> "maltrato o agresión hacia animales";
            default -> categoria;
        };
    }

    /** Datos de una nueva publicación en el muro social. */
    public static class PublicacionDTO {
        public Long usuarioId;
        public String contenido;
        public String imagenUrl;
        /** Si el usuario ya vio la advertencia de moderación y decidió publicar de todas formas. */
        public boolean confirmado;
    }

    /** Datos de un nuevo comentario sobre una publicación. */
    public static class ComentarioDTO {
        public Long usuarioId;
        public String contenido;
        public boolean confirmado;
    }

    /** Datos de una publicación dentro de un grupo temático. */
    public static class GrupoPublicacionDTO {
        public Long usuarioId;
        public String contenido;
        public String imagenUrl;
        public boolean confirmado;
    }

    /** Identifica al usuario que se une o sale de un grupo. */
    public static class UnirseDTO {
        public Long usuarioId;
    }

    /** Datos para crear un nuevo grupo temático. */
    public static class CrearGrupoDTO {
        public Long usuarioId;
        public Long creadoPor;
        public String nombre;
        public String descripcion;
    }

    /** Datos de una denuncia sobre una publicación o usuario de la comunidad. */
    public static class ReporteDTO {
        public Long reportadorId;
        public Long publicacionId;
        public Long reportadoId;
        public String motivo;
        public String contenido;
    }

    /**
     * Obtiene el feed principal de publicaciones de la comunidad, paginado.
     *
     * @param usuarioId identificador del usuario que consulta (para marcar si ya reaccionó a cada publicación).
     * @param limite cantidad máxima de publicaciones a devolver.
     * @param offset cantidad de publicaciones a saltar (paginación).
     * @return un JSON (como texto) con las publicaciones del feed.
     */
    @GetMapping(value = "/feed", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> feedSocial(@RequestParam(required = false) Long usuarioId, @RequestParam(defaultValue = "20") Integer limite, @RequestParam(defaultValue = "0") Integer offset) {
        return ResponseEntity.ok(repo.feedSocial(usuarioAutenticado(), limite, offset));
    }

    /**
     * Busca publicaciones por texto libre, por autor o por hashtag (#tema).
     * Devuelve la misma estructura que el feed para que web y app reutilicen
     * el mismo renderizado.
     */
    @GetMapping(value = "/buscar", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> buscarPublicaciones(
            @RequestParam(required = false) Long usuarioId,
            @RequestParam(required = false, name = "q") String q,
            @RequestParam(defaultValue = "20") Integer limite,
            @RequestParam(defaultValue = "0") Integer offset) {
        Long uid = usuarioAutenticado();
        return ResponseEntity.ok(repo.buscarPublicaciones(uid != null ? uid : 0L, q, limite, offset));
    }

    /** Hashtags más usados en la comunidad. */
    @GetMapping(value = "/hashtags", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> hashtagsPopulares(
            @RequestParam(defaultValue = "10") Integer limite) {
        return ResponseEntity.ok(repo.hashtagsPopulares(limite));
    }

    /**
     * Publicaciones reales de la comunidad marcadas con #testimonio, para
     * mostrar como testimonios en la landing pública (con el nombre y la
     * foto reales de su autor). No requiere autenticación: solo expone
     * publicaciones que sus propios autores etiquetaron para este fin.
     * Un mismo usuario nunca aparece más de una vez: si publicó varios
     * #testimonio, solo se devuelve el más reciente de cada uno.
     *
     * @param limite cantidad máxima de testimonios (de usuarios distintos) a devolver.
     * @return la lista de publicaciones etiquetadas, una por usuario, más recientes primero.
     */
    @GetMapping(value = "/testimonios-publicos", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<List<Map<String, Object>>> testimoniosPublicos(
            @RequestParam(defaultValue = "20") Integer limite) {
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
            "SELECT * FROM (" +
            "  SELECT DISTINCT ON (u.id) p.id, p.contenido, p.created_at, u.id AS usuario_id, u.nombre, u.foto_url " +
            "  FROM publicacion p JOIN usuario u ON u.id = p.usuario_id " +
            "  WHERE p.deleted_at IS NULL AND p.contenido ILIKE '%#testimonio%' " +
            "  ORDER BY u.id, p.created_at DESC" +
            ") t ORDER BY created_at DESC LIMIT ?",
            limite
        );
        return ResponseEntity.ok(rows);
    }

    /**
     * Lista los comentarios de una publicación.
     *
     * @param id identificador de la publicación.
     * @return un JSON (como texto) con los comentarios de la publicación.
     */
    @GetMapping(value = "/publicacion/{id}/comentarios", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarComentarios(@PathVariable Long id, @RequestParam(required = false) Long usuarioId) {
        return ResponseEntity.ok(repo.listarComentarios(id, usuarioAutenticado()));
    }

    /**
     * Crea una nueva publicación en el feed (variante JSON).
     *
     * @param dto autor, contenido e imagen (opcional) de la publicación.
     * @return los datos de la publicación creada, o un error 400 si el contenido fue bloqueado por moderación.
     */
    @PostMapping(value = "/publicacion", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> publicarJson(@RequestBody PublicacionDTO dto) {
        dto.usuarioId = usuarioAutenticado();
        var veredicto = evaluarModeracion(dto.usuarioId, dto.contenido, dto.imagenUrl, dto.confirmado);
        if (!veredicto.permitir()) return veredicto.respuesta();
        String res = repo.crearPublicacion(dto.usuarioId, dto.contenido, dto.imagenUrl, "IMAGE");
        notifySocialUpdate();
        return ResponseEntity.ok(res);
    }

    /**
     * Crea una nueva publicación en el feed (variante con parámetros de formulario).
     *
     * @param usuarioId identificador del autor.
     * @param contenido texto de la publicación.
     * @param imagenUrl URL de la imagen asociada (opcional).
     * @return los datos de la publicación creada, o un error 400 si el contenido fue bloqueado por moderación.
     */
    @PostMapping(value = "/publicacion", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> publicarParams(@RequestParam(required = false) Long usuarioId, @RequestParam String contenido, @RequestParam(required = false) String imagenUrl, @RequestParam(defaultValue = "false") boolean confirmado) {
        usuarioId = usuarioAutenticado();
        var veredicto = evaluarModeracion(usuarioId, contenido, imagenUrl, confirmado);
        if (!veredicto.permitir()) return veredicto.respuesta();
        String res = repo.crearPublicacion(usuarioId, contenido, imagenUrl, "IMAGE");
        notifySocialUpdate();
        return ResponseEntity.ok(res);
    }

    /**
     * Crea una nueva publicación en el feed adjuntando un archivo (imagen o video) subido a Backblaze B2.
     *
     * @param usuarioId identificador del autor.
     * @param contenido texto de la publicación.
     * @param file archivo multimedia a adjuntar (opcional).
     * @return los datos de la publicación creada, o un error 400/500 según el caso.
     */
    @PostMapping(value = "/publicacion/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> publicarConArchivo(
            @RequestParam(value = "usuarioId", required = false) Long usuarioId,
            @RequestParam("contenido") String contenido,
            @RequestParam(value = "file", required = false) MultipartFile file,
            @RequestParam(defaultValue = "false") boolean confirmado) {
        usuarioId = usuarioAutenticado();
        String url = null;
        String mediaType = "IMAGE";
        if (file != null && !file.isEmpty()) {
            try {
                url = s3Service.uploadFile(file);
                String contentType = file.getContentType();
                if (contentType != null && contentType.startsWith("video/")) {
                    mediaType = "VIDEO";
                }
            } catch (IllegalArgumentException e) {
                return ResponseEntity.status(400).body("{\"ok\": false, \"error\": \"" + e.getMessage() + "\"}");
            } catch (Exception e) {
                return ResponseEntity.status(500).body("{\"error\": \"Error guardando archivo en Backblaze B2\"}");
            }
        }
        // Los moderadores (Sightengine, clasificador de mascota) son servicios
        // externos: descargan la imagen ellos mismos, así que necesitan una URL
        // que puedan resolver desde internet. `uploadFile` devuelve la ruta
        // interna de nuestra API, que para ellos no existe — con esa ruta las
        // dos comprobaciones fallaban y, al fallar abiertas, dejaban pasar
        // cualquier imagen. Se firma una URL temporal solo para moderar; lo que
        // se guarda en la base sigue siendo la ruta interna de siempre.
        String urlParaModerar = urlPublicaParaModeracion(url);
        var veredicto = evaluarModeracion(usuarioId, contenido, urlParaModerar, confirmado);
        if (!veredicto.permitir()) return veredicto.respuesta();
        String res = repo.crearPublicacion(usuarioId, contenido, url, mediaType);
        notifySocialUpdate();
        return ResponseEntity.ok(res);
    }

    /**
     * Convierte la ruta interna que devuelve la subida
     * ({@code /api/huellitas/media/CLAVE}) en una URL firmada que un servicio
     * externo pueda descargar. Si la entrada ya es una URL absoluta se
     * devuelve tal cual, y si no se puede firmar se devuelve la original para
     * no romper la publicación.
     */
    private String urlPublicaParaModeracion(String rutaInterna) {
        if (rutaInterna == null || rutaInterna.isBlank()) return rutaInterna;
        if (rutaInterna.startsWith("http://") || rutaInterna.startsWith("https://")) return rutaInterna;

        final String prefijo = "/api/huellitas/media/";
        if (!rutaInterna.startsWith(prefijo)) return rutaInterna;

        String clave = rutaInterna.substring(prefijo.length());
        try {
            return s3Service.generatePresignedUrl(clave);
        } catch (Exception e) {
            return rutaInterna;
        }
    }

    /**
     * Alterna el "me gusta" de un usuario sobre una publicación.
     *
     * @param id identificador de la publicación.
     * @param usuarioId identificador del usuario que reacciona.
     * @return si la publicación quedó marcada como "gustada" por el usuario tras la operación.
     */
    @PostMapping(value = "/publicacion/{id}/reaccionar", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> reaccionar(@PathVariable Long id, @RequestParam(required = false) Long usuarioId) {
        Boolean liked = repo.reaccionar(id, usuarioAutenticado());
        notifySocialUpdate();
        return ResponseEntity.ok(Map.of("liked", liked));
    }

    /**
     * Alterna la reacción de un usuario sobre una publicación de un grupo temático.
     *
     * @param id identificador de la publicación del grupo.
     * @param usuarioId identificador del usuario que reacciona.
     * @param tipo tipo de reacción (opcional).
     * @return el resultado de la operación en formato JSON.
     */
    @PostMapping(value = "/grupos/mensaje/{id}/reaccionar", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> reaccionarGrupo(@PathVariable Long id, @RequestParam(required = false) Long usuarioId, @RequestParam(required = false) String tipo) {
        return ResponseEntity.ok(repo.reaccionarPublicacionGrupo(id, usuarioAutenticado(), tipo));
    }

    /**
     * Registra una denuncia simple sobre una publicación (sin pasar por la evaluación automática con IA).
     *
     * @param id identificador de la publicación denunciada.
     * @param dto datos de la denuncia: denunciante y motivo.
     * @return el resultado del registro en formato JSON.
     */
    @PostMapping(value = "/publicacion/{id}/reportar", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> reportarPublicacion(@PathVariable Long id, @RequestBody ReporteDTO dto) {
        return ResponseEntity.ok(repo.reportar(id, usuarioAutenticado(), dto.motivo));
    }

    /**
     * Agrega un comentario a una publicación (variante JSON).
     *
     * @param id identificador de la publicación.
     * @param dto autor y contenido del comentario.
     * @return el comentario creado, o un error 400 si el contenido fue bloqueado por moderación.
     */
    @PostMapping(value = "/publicacion/{id}/comentar", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> comentarJson(@PathVariable Long id, @RequestBody ComentarioDTO dto) {
        dto.usuarioId = usuarioAutenticado();
        var veredicto = evaluarModeracion(dto.usuarioId, dto.contenido, null, dto.confirmado);
        if (!veredicto.permitir()) return veredicto.respuesta();
        String res = repo.comentar(id, dto.usuarioId, dto.contenido);
        notifySocialUpdate();
        return ResponseEntity.ok(res);
    }

    /**
     * Agrega un comentario a una publicación (variante con parámetros de formulario).
     *
     * @param id identificador de la publicación.
     * @param usuarioId identificador del autor del comentario.
     * @param contenido texto del comentario.
     * @return el comentario creado, o un error 400 si el contenido fue bloqueado por moderación.
     */
    @PostMapping(value = "/publicacion/{id}/comentar", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> comentarParams(@PathVariable Long id, @RequestParam(required = false) Long usuarioId, @RequestParam String contenido, @RequestParam(defaultValue = "false") boolean confirmado) {
        usuarioId = usuarioAutenticado();
        var veredicto = evaluarModeracion(usuarioId, contenido, null, confirmado);
        if (!veredicto.permitir()) return veredicto.respuesta();
        String res = repo.comentar(id, usuarioId, contenido);
        notifySocialUpdate();
        return ResponseEntity.ok(res);
    }

    /**
     * Edita el contenido de un comentario propio.
     *
     * @param id identificador del comentario.
     * @param usuarioId identificador del autor (para verificar que es el dueño).
     * @param contenido nuevo texto del comentario.
     * @return el comentario actualizado en formato JSON.
     */
    @PutMapping(value = "/comentario/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> editarComentario(@PathVariable Long id, @RequestParam(required = false) Long usuarioId, @RequestParam String contenido) {
        try {
            return ResponseEntity.ok(repo.editarComentario(id, usuarioAutenticado(), contenido));
        } catch (Exception e) {
            return manejarErrorEdicion(e);
        }
    }

    /**
     * Elimina un comentario propio.
     *
     * @param id identificador del comentario.
     * @param usuarioId identificador del autor (para verificar que es el dueño).
     * @return el resultado de la eliminación en formato JSON.
     */
    @DeleteMapping(value = "/comentario/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> eliminarComentario(@PathVariable Long id, @RequestParam(required = false) Long usuarioId) {
        return ResponseEntity.ok(repo.eliminarComentario(id, usuarioAutenticado()));
    }

    /**
     * Edita el contenido de una publicación propia.
     *
     * @param id identificador de la publicación.
     * @param usuarioId identificador del autor (para verificar que es el dueño).
     * @param contenido nuevo texto de la publicación.
     * @return la publicación actualizada en formato JSON.
     */
    @PutMapping(value = "/publicacion/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> editarPublicacion(@PathVariable Long id, @RequestParam(required = false) Long usuarioId, @RequestParam String contenido) {
        try {
            return ResponseEntity.ok(repo.editarPublicacion(id, usuarioAutenticado(), contenido));
        } catch (Exception e) {
            return manejarErrorEdicion(e);
        }
    }

    /**
     * Elimina una publicación propia.
     *
     * @param id identificador de la publicación.
     * @param usuarioId identificador del autor (para verificar que es el dueño).
     * @return el resultado de la eliminación en formato JSON.
     */
    @DeleteMapping(value = "/publicacion/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> eliminarPublicacion(@PathVariable Long id, @RequestParam(required = false) Long usuarioId) {
        return ResponseEntity.ok(repo.eliminarPublicacion(id, usuarioAutenticado()));
    }

    // ── Denuncias y Moderación IA ──────────────────────────────────────────

    /**
     * Registra una denuncia de contenido y la evalúa de inmediato con
     * {@link ModeracionIaService}, que puede resolverla automáticamente
     * (strike o descarte) o dejarla pendiente para un administrador.
     *
     * @param dto datos de la denuncia: denunciante, denunciado, publicación (opcional), motivo y contenido.
     * @return el identificador del reporte creado, o un error 500 si falla el registro.
     */
    @PostMapping(value = "/reportar", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> reportarContenido(@RequestBody ReporteDTO dto) {
        try {
            Long reportadorId = usuarioAutenticado();
            Long reportadoId = dto.reportadoId;
            String contenidoText = dto.contenido != null ? dto.contenido : "";

            if (dto.publicacionId != null) {
                List<Map<String, Object>> rows = jdbcTemplate.queryForList("SELECT usuario_id, contenido FROM publicacion WHERE id = ?", dto.publicacionId);
                if (!rows.isEmpty()) {
                    if (reportadoId == null) {
                        reportadoId = ((Number) rows.get(0).get("usuario_id")).longValue();
                    }
                    if (contenidoText.isEmpty()) {
                        contenidoText = (String) rows.get(0).get("contenido");
                    }
                }
            }

            String motivo = dto.motivo != null ? dto.motivo : "Contenido inapropiado";
            String motivoConId = dto.publicacionId != null ? "[Comunidad Post #" + dto.publicacionId + "] " + motivo : motivo;

            List<Map<String, Object>> res = jdbcTemplate.queryForList(
                "INSERT INTO reporte_moderacion (casa_id, reportador_id, reportado_id, motivo, estado, created_at) VALUES (NULL, ?, ?, ?, 'PENDIENTE', NOW()) RETURNING id",
                reportadorId, reportadoId, motivoConId
            );

            Long reporteId = ((Number) res.get(0).get("id")).longValue();

            // Filtro rápido con Sightengine: si ya está muy seguro (>0.85),
            // resuelve directo sin gastar la llamada a OpenAI. Reutiliza las
            // mismas columnas (decidido_por, motivo_ia, confianza_ia) que ya
            // lee el panel de moderación en la web/app, así que no hace
            // falta ningún cambio ahí para que se vea.
            var sightengineRes = sightengineService.validarTexto(contenidoText);
            if (sightengineRes.maxScore() > 0.85) {
                if (reportadoId != null) {
                    jdbcTemplate.update("UPDATE usuario SET strikes = COALESCE(strikes, 0) + 1 WHERE id = ?", reportadoId);
                }
                jdbcTemplate.update(
                    "UPDATE reporte_moderacion SET estado = 'RESUELTO', decidido_por = 'SIGHTENGINE', motivo_ia = ?, confianza_ia = ? WHERE id = ?",
                    sightengineRes.categoriaMasAlta(), sightengineRes.maxScore(), reporteId
                );
            } else {
                // Sightengine no está seguro: deja que decida la IA existente (OpenAI) o un admin humano
                moderacionIaService.procesarReporteConIa(reporteId, contenidoText, motivo, reportadoId, reportadorId);
            }

            return ResponseEntity.ok(Map.of(
                "ok", true,
                "reporteId", reporteId,
                "message", "Reporte procesado correctamente por el sistema de moderación."
            ));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("ok", false, "error", e.getMessage()));
        }
    }

    // ── Grupos ────────────────────────────────────────────────────────────

    /**
     * Lista los grupos temáticos existentes, indicando cuáles integra el usuario.
     *
     * @param usuarioId identificador del usuario que consulta (opcional).
     * @return un JSON (como texto) con los grupos.
     */
    @GetMapping(value = "/grupos", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarGrupos(@RequestParam(required = false) Long usuarioId) {
        Long uid = usuarioAutenticado();
        return ResponseEntity.ok(repo.listarGrupos(uid != null ? uid : 0L));
    }

    /**
     * Lista las publicaciones del muro de un grupo temático.
     *
     * @param grupoId identificador del grupo.
     * @param usuarioId identificador del usuario que consulta (opcional).
     * @return un JSON (como texto) con las publicaciones del grupo.
     */
    @GetMapping(value = "/grupos/{grupoId}/mensajes", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> mensajesGrupo(@PathVariable Long grupoId, @RequestParam(required = false) Long usuarioId) {
        Long uid = usuarioAutenticado();
        return ResponseEntity.ok(repo.mensajesGrupo(grupoId, uid != null ? uid : 0L));
    }

    /**
     * Crea un nuevo grupo temático de la comunidad.
     *
     * @param dto datos del grupo en JSON (opcional; los parámetros de abajo sirven como alternativa/complemento).
     * @param nombre nombre del grupo, si no viene en {@code dto}.
     * @param descripcion descripción del grupo, si no viene en {@code dto}.
     * @param creadoPor identificador del usuario creador, si no viene en {@code dto}.
     * @return los datos del grupo creado, o un error 400 si el nombre es inválido.
     */
    @PostMapping("/grupos")
    public ResponseEntity<String> crearGrupoJson(@RequestBody(required = false) CrearGrupoDTO dto,
                                                  @RequestParam(required = false) String nombre,
                                                  @RequestParam(required = false) String descripcion,
                                                  @RequestParam(required = false) Long creadoPor) {
        Long creador = usuarioAutenticado();
        String nom = dto != null && dto.nombre != null ? dto.nombre : nombre;
        String desc = dto != null && dto.descripcion != null ? dto.descripcion : descripcion;
        
        try {
            if (nom != null) {
                nom = com.huellitas.utils.ValidationUtils.validarNombreEntidad(nom);
            }
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body("{\"message\": \"" + e.getMessage() + "\"}");
        }

        return ResponseEntity.ok(repo.crearGrupo(nom, desc, creador != null ? creador : 0L));
    }

    /**
     * Agrega a un usuario como miembro de un grupo temático. Acepta tanto el
     * usuarioId en el cuerpo JSON como en un parámetro de consulta — antes
     * eran dos métodos separados mapeados a la misma ruta, y una petición
     * sin cabecera Content-Type (body vacío) hacía que Spring no supiera
     * cuál de los dos usar y respondiera 500 "Ambiguous handler methods".
     *
     * @param grupoId identificador del grupo.
     * @param dto identificador del usuario en JSON (opcional).
     * @param usuarioId identificador del usuario, si no viene en {@code dto}.
     * @return los datos de la membresía creada, o un error 400 si el usuario ya era miembro.
     */
    @PostMapping(value = "/grupos/{grupoId}/unirse", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> unirseGrupo(@PathVariable Long grupoId,
                                               @RequestBody(required = false) UnirseDTO dto,
                                               @RequestParam(required = false) Long usuarioId) {
        Long uid = usuarioAutenticado();
        try {
            return ResponseEntity.ok(repo.unirseGrupo(grupoId, uid != null ? uid : 0L));
        } catch (Exception e) {
            String msg = e.getMessage() != null ? e.getMessage() : "";
            if (msg.contains("YA_ES_MIEMBRO") || e.getCause() != null && e.getCause().getMessage() != null && e.getCause().getMessage().contains("YA_ES_MIEMBRO")) {
                return ResponseEntity.status(400).body("{\"error\": \"YA_ES_MIEMBRO\"}");
            }
            throw e;
        }
    }

    /**
     * Quita a un usuario de un grupo temático del que era miembro.
     *
     * @param grupoId identificador del grupo.
     * @param dto identificador del usuario en JSON (opcional).
     * @param usuarioId identificador del usuario, si no viene en {@code dto}.
     * @return el resultado de la operación en formato JSON.
     */
    @PostMapping(value = "/grupos/{grupoId}/salir", consumes = {MediaType.APPLICATION_JSON_VALUE, MediaType.APPLICATION_FORM_URLENCODED_VALUE}, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> salirGrupoJson(@PathVariable Long grupoId,
                                                  @RequestBody(required = false) UnirseDTO dto,
                                                  @RequestParam(required = false) Long usuarioId) {
        Long uid = usuarioAutenticado();
        return ResponseEntity.ok(repo.salirGrupo(grupoId, uid != null ? uid : 0L));
    }

    /**
     * Publica un mensaje en el muro de un grupo temático, adjuntando una imagen si se proporciona.
     *
     * @param grupoId identificador del grupo.
     * @param usuarioId identificador del autor.
     * @param contenido texto del mensaje.
     * @param file imagen a adjuntar (opcional).
     * @return los datos de la publicación creada, o un error 400/500 según el caso.
     */
    @PostMapping(value = {"/grupos/{grupoId}/publicar", "/grupos/{grupoId}/mensajes"}, consumes = {MediaType.MULTIPART_FORM_DATA_VALUE}, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> publicarEnGrupoUpload(
            @PathVariable Long grupoId,
            @RequestParam(required = false) Long usuarioId,
            @RequestParam String contenido,
            @RequestParam(value = "file", required = false) MultipartFile file,
            @RequestParam(defaultValue = "false") boolean confirmado) {
        usuarioId = usuarioAutenticado();
        String imagenUrl = null;
        if (file != null && !file.isEmpty()) {
            try {
                imagenUrl = s3AvatarService.uploadFile(file);
            } catch (IllegalArgumentException e) {
                return ResponseEntity.status(400).body("{\"ok\": false, \"error\": \"" + e.getMessage() + "\"}");
            } catch (Exception e) {
                return ResponseEntity.status(500).body("{\"error\": \"Error subiendo la imagen a Backblaze B2 ALM-FT\"}");
            }
        }

        var veredicto = evaluarModeracion(usuarioId, contenido, imagenUrl, confirmado);
        if (!veredicto.permitir()) return veredicto.respuesta();

        return ResponseEntity.ok(repo.publicarEnGrupo(grupoId, usuarioId, contenido, imagenUrl));
    }

    /** Datos de un mensaje de texto (sin adjunto) para el muro de un grupo. */
    public static class MensajeGrupoDTO {
        public Long usuarioId;
        public String contenido;
        public boolean confirmado;
    }

    /**
     * Publica un mensaje de solo texto en el muro de un grupo temático.
     *
     * @param grupoId identificador del grupo.
     * @param dto autor y contenido del mensaje.
     * @return los datos de la publicación creada, o un error 400 si el contenido fue bloqueado por moderación.
     */
    @PostMapping(value = "/grupos/{grupoId}/mensajes", consumes = {MediaType.APPLICATION_JSON_VALUE, MediaType.APPLICATION_FORM_URLENCODED_VALUE}, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> publicarEnGrupoJson(
            @PathVariable Long grupoId,
            @RequestBody MensajeGrupoDTO dto) {
        dto.usuarioId = usuarioAutenticado();
        var veredicto = evaluarModeracion(dto.usuarioId, dto.contenido, null, dto.confirmado);
        if (!veredicto.permitir()) return veredicto.respuesta();

        return ResponseEntity.ok(repo.publicarEnGrupo(grupoId, dto.usuarioId, dto.contenido, null));
    }

    /**
     * Lista sugerencias de lenguaje inclusivo para ayudar a los usuarios a redactar publicaciones.
     *
     * @return un JSON (como texto) con las sugerencias de lenguaje inclusivo.
     */
    @GetMapping(value = "/lenguaje-inclusivo", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> listarSugerenciasInclusivas() {
        return ResponseEntity.ok(repo.listarSugerenciasInclusivas());
    }

    /**
     * Aplica manualmente un strike a un usuario de la comunidad (acción de un administrador).
     *
     * @param adminId identificador del administrador que aplica el strike.
     * @param usuarioId identificador del usuario sancionado.
     * @return un mensaje de confirmación en formato JSON.
     */
    @PostMapping(value = "/strike", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> darStrike(@RequestParam(required = false) Long adminId, @RequestParam Long usuarioId) {
        return ResponseEntity.ok("{\"message\": \"" + repo.darStrike(usuarioAutenticado(), usuarioId) + "\"}");
    }

    /**
     * Edita el contenido de una publicación de un grupo temático.
     *
     * @param id identificador de la publicación del grupo.
     * @param usuarioId identificador del autor (para verificar que es el dueño).
     * @param contenido nuevo texto de la publicación.
     * @return la publicación actualizada en formato JSON.
     */
    @PutMapping(value = "/grupos/mensaje/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> editarPublicacionGrupo(
            @PathVariable Long id,
            @RequestParam(required = false) Long usuarioId,
            @RequestParam String contenido) {
        try {
            return ResponseEntity.ok(repo.editarPublicacionGrupo(id, usuarioAutenticado(), contenido));
        } catch (Exception e) {
            return manejarErrorEdicion(e);
        }
    }

    /**
     * Traduce las excepciones de las funciones SQL de edición
     * (NO_AUTORIZADO, TIEMPO_EDICION_EXPIRADO) a respuestas HTTP legibles —
     * después de 5 minutos ya no se puede editar el contenido propio, solo
     * eliminarlo (para uno mismo o para todos).
     */
    private ResponseEntity<String> manejarErrorEdicion(Exception e) {
        String msg = e.getMessage() != null ? e.getMessage() : "";
        if (msg.contains("TIEMPO_EDICION_EXPIRADO")) {
            String texto = "Ya pasaron más de 5 minutos — no puedes editar esto, pero sí puedes eliminarlo.";
            return ResponseEntity.status(400).body("{\"ok\":false,\"error\":\"" + texto + "\",\"message\":\"" + texto + "\"}");
        }
        if (msg.contains("NO_AUTORIZADO")) {
            String texto = "No tienes permiso para editar esto.";
            return ResponseEntity.status(403).body("{\"ok\":false,\"error\":\"" + texto + "\",\"message\":\"" + texto + "\"}");
        }
        String texto = "No se pudo editar el contenido.";
        return ResponseEntity.status(400).body("{\"ok\":false,\"error\":\"" + texto + "\",\"message\":\"" + texto + "\"}");
    }

    /**
     * Elimina una publicación de un grupo temático.
     *
     * @param id identificador de la publicación del grupo.
     * @param usuarioId identificador del autor (para verificar que es el dueño).
     * @return el resultado de la eliminación en formato JSON.
     */
    @DeleteMapping(value = "/grupos/mensaje/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> eliminarPublicacionGrupo(
            @PathVariable Long id,
            @RequestParam(required = false) Long usuarioId) {
        return ResponseEntity.ok(repo.eliminarPublicacionGrupo(id, usuarioAutenticado()));
    }

    /**
     * Transfiere la administración de un grupo temático a otro miembro.
     *
     * @param grupoId identificador del grupo.
     * @param adminId identificador del administrador actual (para verificar el permiso).
     * @param nuevoAdminId identificador del nuevo administrador.
     * @return el resultado de la transferencia en formato JSON.
     */
    @PostMapping(value = "/grupos/{grupoId}/transferir-admin", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> transferirAdminGrupo(
            @PathVariable Long grupoId,
            @RequestParam(required = false) Long adminId,
            @RequestParam Long nuevoAdminId) {
        return ResponseEntity.ok(repo.transferirAdminGrupo(grupoId, usuarioAutenticado(), nuevoAdminId));
    }

    /**
     * Elimina un grupo temático.
     *
     * @param grupoId identificador del grupo a eliminar.
     * @param adminId identificador del administrador del grupo (para verificar el permiso).
     * @return el resultado de la eliminación en formato JSON.
     */
    @DeleteMapping(value = "/grupos/{grupoId}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> eliminarGrupo(
            @PathVariable Long grupoId,
            @RequestParam(required = false) Long adminId) {
        return ResponseEntity.ok(repo.eliminarGrupo(grupoId, usuarioAutenticado()));
    }

    /**
     * Lista los miembros de un grupo temático con su rol, para elegir a
     * quién expulsar o a quién transferir la administración.
     *
     * @param grupoId identificador del grupo.
     * @return un JSON (como texto) con los miembros del grupo.
     */
    @GetMapping(value = "/grupos/{grupoId}/miembros", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> miembrosGrupo(@PathVariable Long grupoId) {
        Boolean esMiembro = jdbcTemplate.queryForObject(
            "SELECT EXISTS(SELECT 1 FROM grupo_miembro WHERE grupo_id = ? AND usuario_id = ?)",
            Boolean.class, grupoId, usuarioAutenticado());
        if (esMiembro == null || !esMiembro) {
            return ResponseEntity.status(403).body("{\"ok\":false,\"error\":\"No eres miembro de este grupo\"}");
        }
        return ResponseEntity.ok(repo.miembrosGrupo(grupoId));
    }

    /**
     * Expulsa a un miembro de un grupo temático.
     *
     * @param grupoId identificador del grupo.
     * @param adminId identificador de quien expulsa (para verificar el permiso).
     * @param usuarioId identificador del miembro a expulsar.
     * @return el resultado de la operación en formato JSON, o un error 400 si no está autorizado o intenta expulsar al creador.
     */
    @PostMapping(value = "/grupos/{grupoId}/expulsar", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> expulsarMiembroGrupo(
            @PathVariable Long grupoId,
            @RequestParam(required = false) Long adminId,
            @RequestParam Long usuarioId) {
        try {
            return ResponseEntity.ok(repo.expulsarMiembroGrupo(grupoId, usuarioAutenticado(), usuarioId));
        } catch (Exception e) {
            String msg = e.getMessage() != null ? e.getMessage() : "";
            if (msg.contains("NO_AUTORIZADO")) {
                return ResponseEntity.status(403).body("{\"ok\":false,\"error\":\"No tienes permiso para expulsar miembros de este grupo\",\"message\":\"No tienes permiso para expulsar miembros de este grupo\"}");
            }
            if (msg.contains("NO_SE_PUEDE_EXPULSAR_AL_CREADOR")) {
                return ResponseEntity.status(400).body("{\"ok\":false,\"error\":\"No puedes expulsar al creador del grupo — transfiere la administración primero\",\"message\":\"No puedes expulsar al creador del grupo — transfiere la administración primero\"}");
            }
            return ResponseEntity.status(400).body("{\"ok\":false,\"error\":\"No se pudo expulsar al miembro\",\"message\":\"No se pudo expulsar al miembro\"}");
        }
    }

    /**
     * Registra una denuncia sobre una publicación de un grupo temático (a
     * diferencia de {@link #reportarPublicacion}, que solo sirve para el
     * feed principal — las publicaciones de grupo viven en otra tabla).
     *
     * @param id identificador de la publicación del grupo denunciada.
     * @param dto datos de la denuncia: denunciante y motivo.
     * @return el resultado del registro en formato JSON, o un error 400 si la publicación no existe.
     */
    @PostMapping(value = "/grupos/mensaje/{id}/reportar", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> reportarPublicacionGrupo(@PathVariable Long id, @RequestBody ReporteDTO dto) {
        try {
            return ResponseEntity.ok(repo.reportarPublicacionGrupo(id, usuarioAutenticado(), dto.motivo));
        } catch (Exception e) {
            return ResponseEntity.status(400).body("{\"ok\":false,\"error\":\"No se pudo enviar la denuncia\",\"message\":\"No se pudo enviar la denuncia\"}");
        }
    }

    /** Datos para ocultar un contenido solo para quien lo pide (sigue visible para los demás). */
    public static class OcultarDTO {
        public Long usuarioId;
        /** PUBLICACION, COMENTARIO o PUBLICACION_GRUPO. */
        public String tipo;
        public Long contenidoId;
    }

    /**
     * Oculta un contenido (publicación del feed, comentario, o publicación
     * de grupo) solo para el usuario que lo pide — "eliminar para mí": el
     * contenido sigue existiendo y visible para todos los demás.
     *
     * @param dto usuario, tipo de contenido y su identificador.
     * @return confirmación en formato JSON.
     */
    @PostMapping(value = "/ocultar", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> ocultarContenido(@RequestBody OcultarDTO dto) {
        return ResponseEntity.ok(repo.ocultarContenido(usuarioAutenticado(), dto.tipo, dto.contenidoId));
    }
}