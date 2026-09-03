package com.huellitas.perro;
import com.huellitas.config.AuthContext;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import com.huellitas.storage.S3AvatarService;
import com.huellitas.ia.ContenidoMascotaService;
import java.time.LocalDate;
import java.math.BigDecimal;
import com.huellitas.utils.ValidationUtils;

/**
 * Gestiona el registro, edición y baja de las mascotas de una vivienda,
 * incluyendo la subida de su foto de perfil a Backblaze B2.
 */
@RestController
@RequestMapping("/api/huellitas/perro")
public class PerroController {
    private final PerroRepository repo;
    private final S3AvatarService s3AvatarService;
    private final JdbcTemplate jdbcTemplate;
    private final AuthContext authContext;
    private final ContenidoMascotaService contenidoMascotaService;

    public PerroController(PerroRepository repo, S3AvatarService s3AvatarService, JdbcTemplate jdbcTemplate,
                            AuthContext authContext, ContenidoMascotaService contenidoMascotaService) {
        this.repo = repo;
        this.s3AvatarService = s3AvatarService;
        this.jdbcTemplate = jdbcTemplate;
        this.authContext = authContext;
        this.contenidoMascotaService = contenidoMascotaService;
    }

    private static final String ERROR_FOTO_NO_ES_PERRO =
        "{\"ok\":false,\"error\":\"La foto no parece ser de un perro real\",\"message\":\"Esa imagen no parece ser la foto de un perro real. Sube una foto real de tu mascota — sin ella, la mascota se guarda igual, pero el reconocimiento en Momentos no podrá usarla.\"}";

    /**
     * Verifica que la foto sea realmente de un perro real antes de subirla.
     * Falla abierto si el clasificador no está disponible, igual que el
     * resto de las verificaciones de contenido del sistema.
     *
     * @return {@code null} si la foto es válida (o no se pudo verificar); la respuesta 400 a devolver si no lo es.
     */
    private ResponseEntity<String> validarFotoPerro(MultipartFile file) {
        try {
            var veredicto = contenidoMascotaService.esFotoRealDePerro(file.getBytes());
            if (veredicto.disponible() && !veredicto.esFotoDePerro()) {
                return ResponseEntity.status(400).body(ERROR_FOTO_NO_ES_PERRO);
            }
            return null;
        } catch (java.io.IOException e) {
            return null;
        }
    }

    /** Datos de una mascota para su registro o edición. */
    public static class PerroDTO {
        public Long casaId;
        public String nombre;
        public String raza;
        public LocalDate fechaNacimiento;
        public BigDecimal peso;
        public String fotoUrl;
    }

    private ResponseEntity<String> sinAcceso() {
        return ResponseEntity.status(403).body("{\"ok\":false,\"error\":\"No tienes acceso a esta mascota\",\"message\":\"No tienes acceso a esta mascota\"}");
    }

    private static final ResponseEntity<String> PESO_INVALIDO = ResponseEntity.status(400)
        .body("{\"ok\":false,\"error\":\"El peso debe ser mayor a 0 y menor a 200 kg\",\"message\":\"El peso debe ser mayor a 0 y menor a 200 kg\"}");

    /** @return {@code true} si el peso está en un rango plausible para una mascota (0, 200] kg. */
    private boolean pesoValido(BigDecimal peso) {
        return peso == null || (peso.signum() > 0 && peso.compareTo(new BigDecimal("200")) <= 0);
    }

    /** @return la casa_id de una mascota, o {@code null} si no existe. */
    private Long casaDeMascota(Long perroId) {
        var filas = jdbcTemplate.queryForList("SELECT casa_id FROM perro WHERE id = ?", perroId);
        return filas.isEmpty() ? null : ((Number) filas.get(0).get("casa_id")).longValue();
    }

    /**
     * Registra una nueva mascota en una vivienda, subiendo su foto de perfil si se proporciona.
     *
     * @param casaId identificador de la vivienda a la que pertenece la mascota.
     * @param nombre nombre de la mascota.
     * @param raza raza de la mascota.
     * @param fechaNacimiento fecha de nacimiento de la mascota.
     * @param peso peso de la mascota.
     * @param file foto de perfil de la mascota, opcional.
     * @return los datos de la mascota creada, o un error 400/500 según el caso.
     */
    @PostMapping(consumes = {MediaType.MULTIPART_FORM_DATA_VALUE}, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> registrarPerro(
            @RequestParam(required = false) Long casaId,
            @RequestParam(required = false) String nombre,
            @RequestParam(required = false) String raza,
            @RequestParam(required = false) LocalDate fechaNacimiento,
            @RequestParam(required = false) BigDecimal peso,
            @RequestParam(value = "file", required = false) MultipartFile file) {
        if (!authContext.perteneceACasa(casaId)) return sinAcceso();
        if (!pesoValido(peso)) return PESO_INVALIDO;
        if (nombre != null) {
            nombre = ValidationUtils.validarNombreEntidad(nombre);
        }

        String fotoUrl = null;
        if (file != null && !file.isEmpty()) {
            ResponseEntity<String> errorFoto = validarFotoPerro(file);
            if (errorFoto != null) return errorFoto;
            try {
                fotoUrl = s3AvatarService.uploadFile(file);
            } catch (IllegalArgumentException e) {
                return ResponseEntity.status(400).body("{\"ok\": false, \"error\": \"" + e.getMessage() + "\"}");
            } catch (Exception e) {
                return ResponseEntity.status(500).body("{\"error\": \"Error subiendo la imagen a Backblaze B2\"}");
            }
        }

        String result = repo.registrarPerro(casaId, nombre, raza, fechaNacimiento, peso, fotoUrl);
        if (result != null && result.contains("\"ok\":false")) {
            return ResponseEntity.status(400).body(result);
        }
        return ResponseEntity.ok(result);
    }

    /**
     * Edita los datos de una mascota existente, reemplazando su foto de perfil si se proporciona una nueva.
     *
     * @param id identificador de la mascota a editar.
     * @param nombre nuevo nombre de la mascota (opcional).
     * @param raza nueva raza de la mascota (opcional).
     * @param peso nuevo peso de la mascota (opcional).
     * @param file nueva foto de perfil de la mascota (opcional).
     * @return los datos actualizados de la mascota, o un error 500 si falla la subida de la imagen.
     */
    @PutMapping(value = "/{id}", consumes = {MediaType.MULTIPART_FORM_DATA_VALUE}, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> editarPerro(
            @PathVariable Long id,
            @RequestParam(required = false) String nombre,
            @RequestParam(required = false) String raza,
            @RequestParam(required = false) BigDecimal peso,
            @RequestParam(value = "file", required = false) MultipartFile file) {
        Long casaId = casaDeMascota(id);
        if (casaId == null) return ResponseEntity.status(404).body("{\"error\":\"Mascota no encontrada\"}");
        if (!authContext.perteneceACasa(casaId)) return sinAcceso();
        if (!pesoValido(peso)) return PESO_INVALIDO;
        if (nombre != null) {
            nombre = ValidationUtils.validarNombreEntidad(nombre);
        }

        String fotoUrl = null;
        if (file != null && !file.isEmpty()) {
            ResponseEntity<String> errorFoto = validarFotoPerro(file);
            if (errorFoto != null) return errorFoto;
            try {
                fotoUrl = s3AvatarService.uploadFile(file);
            } catch (IllegalArgumentException e) {
                return ResponseEntity.status(400).body("{\"ok\": false, \"error\": \"" + e.getMessage() + "\"}");
            } catch (Exception e) {
                return ResponseEntity.status(500).body("{\"error\": \"Error subiendo la imagen a Backblaze B2\"}");
            }
        }

        return ResponseEntity.ok(repo.editarPerro(id, nombre, raza, peso, fotoUrl));
    }

    /**
     * Da de baja (borrado lógico) a una mascota.
     *
     * @param id identificador de la mascota a eliminar.
     * @return el resultado de la operación en formato JSON.
     */
    @DeleteMapping(value = "/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> eliminarPerro(@PathVariable Long id) {
        Long casaId = casaDeMascota(id);
        if (casaId == null) return ResponseEntity.status(404).body("{\"error\":\"Mascota no encontrada\"}");
        if (!authContext.perteneceACasa(casaId)) return sinAcceso();
        return ResponseEntity.ok(repo.eliminarPerro(id));
    }
}
