package com.huellitas.camara;

import com.huellitas.casa.Casa;
import com.huellitas.casa.CasaRepository;
import com.huellitas.config.AuthContext;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * Administra las cámaras IP vinculadas a las viviendas: alta, baja,
 * asignación de la mascota que vigilan, y el flujo de vinculación de una
 * cámara nueva mediante un código QR que el dispositivo escanea.
 */
@RestController
@RequestMapping("/api/huellitas/camaras")
public class CamaraController {

    private final CamaraRepository camaraRepository;
    private final CasaRepository casaRepository;
    private final com.huellitas.auth.JwtUtil jwtUtil;
    private final org.springframework.jdbc.core.JdbcTemplate jdbcTemplate;
    private final AuthContext authContext;

    public CamaraController(CamaraRepository camaraRepository, CasaRepository casaRepository,
                            com.huellitas.auth.JwtUtil jwtUtil,
                            org.springframework.jdbc.core.JdbcTemplate jdbcTemplate,
                            AuthContext authContext) {
        this.camaraRepository = camaraRepository;
        this.casaRepository = casaRepository;
        this.jwtUtil = jwtUtil;
        this.jdbcTemplate = jdbcTemplate;
        this.authContext = authContext;
    }

    /** Representación de una cámara para los clientes, incluyendo datos básicos de la mascota que vigila. */
    public static class CamaraDTO {
        public Long id;
        public Long casaId;
        public String nombre;
        public String urlStream;
        public Boolean activo;
        public Boolean conectada;
        /** Mascota vigilada por esta cámara (null si no tiene ninguna asignada). */
        public Long perroId;
        public String perroNombre;
        public String perroFotoUrl;

        public static CamaraDTO fromEntity(Camara camara) {
            CamaraDTO dto = new CamaraDTO();
            dto.id = camara.getId();
            dto.casaId = camara.getCasaId();
            dto.nombre = camara.getNombre();
            dto.urlStream = camara.getUrlStream();
            dto.activo = camara.getActivo();
            dto.conectada = camara.getConectada();
            dto.perroId = camara.getPerroId();
            return dto;
        }
    }

    public static class AsignarMascotaDTO {
        /** Id de la mascota; null o 0 quita la asignación. */
        public Long perroId;
    }

    /** Alta de cámara a partir de un dispositivo IoT encontrado en la red del hogar. */
    public static class VincularDispositivoDTO {
        /** Dispositivo detectado, tal como lo devuelve {@code GET /dispositivo/descubrir}. */
        public Long dispositivoId;
        /** Nombre con el que el usuario quiere ver la cámara. */
        public String nombre;
    }

    /**
     * Añade el nombre y la foto de la mascota asignada para que las interfaces
     * no tengan que cruzar la lista de mascotas por su cuenta.
     */
    private void rellenarDatosMascota(List<CamaraDTO> camaras) {
        List<Long> perroIds = camaras.stream()
                .map(c -> c.perroId)
                .filter(java.util.Objects::nonNull)
                .distinct()
                .toList();
        if (perroIds.isEmpty()) return;

        String marcadores = String.join(",", java.util.Collections.nCopies(perroIds.size(), "?"));
        List<java.util.Map<String, Object>> filas = jdbcTemplate.queryForList(
                "SELECT id, nombre, foto_url FROM perro WHERE id IN (" + marcadores + ")",
                perroIds.toArray());

        java.util.Map<Long, java.util.Map<String, Object>> porId = new java.util.HashMap<>();
        for (java.util.Map<String, Object> fila : filas) {
            porId.put(((Number) fila.get("id")).longValue(), fila);
        }

        for (CamaraDTO dto : camaras) {
            java.util.Map<String, Object> perro = dto.perroId != null ? porId.get(dto.perroId) : null;
            if (perro != null) {
                dto.perroNombre = (String) perro.get("nombre");
                dto.perroFotoUrl = (String) perro.get("foto_url");
            }
        }
    }

    /**
     * Lista las cámaras activas de una vivienda, con los datos básicos de la mascota que cada una vigila.
     *
     * @param casaId identificador de la vivienda.
     * @return la lista de cámaras activas de la vivienda.
     */
    @GetMapping("/casa/{casaId}")
    public ResponseEntity<?> listarCamarasPorCasa(@PathVariable Long casaId) {
        if (!authContext.perteneceACasa(casaId)) {
            return ResponseEntity.status(403).body(java.util.Map.of("ok", false, "error", "No tienes acceso a esta vivienda", "message", "No tienes acceso a esta vivienda"));
        }
        List<CamaraDTO> camaras = camaraRepository.findByCasaIdAndActivoTrue(casaId)
                .stream()
                .map(CamaraDTO::fromEntity)
                .toList();
        rellenarDatosMascota(camaras);
        return ResponseEntity.ok(camaras);
    }

    /**
     * Marca qué mascota vigila una cámara. Se comprueba que la mascota sea de la
     * misma casa que la cámara para no cruzar datos entre hogares.
     */
    /**
     * @param id identificador de la cámara.
     * @param request mascota a asignar (o {@code null}/0 para quitar la asignación actual).
     * @return la cámara actualizada, o un error 404/400 si la cámara no existe o la mascota no pertenece a la misma casa.
     */
    @PutMapping("/{id}/mascota")
    public ResponseEntity<?> asignarMascota(@PathVariable Long id, @RequestBody AsignarMascotaDTO request) {
        Camara camara = camaraRepository.findById(id).orElse(null);
        if (camara == null) {
            return ResponseEntity.status(404).body(java.util.Map.of("error", "Cámara no encontrada"));
        }
        if (!authContext.perteneceACasa(camara.getCasaId())) {
            return ResponseEntity.status(403).body(java.util.Map.of("ok", false, "error", "No tienes acceso a esta cámara", "message", "No tienes acceso a esta cámara"));
        }

        Long perroId = (request != null && request.perroId != null && request.perroId > 0)
                ? request.perroId
                : null;

        if (perroId != null) {
            Integer coincidencias = jdbcTemplate.queryForObject(
                    "SELECT COUNT(*) FROM perro WHERE id = ? AND casa_id = ? AND deleted_at IS NULL",
                    Integer.class, perroId, camara.getCasaId());
            if (coincidencias == null || coincidencias == 0) {
                return ResponseEntity.badRequest()
                        .body(java.util.Map.of("error", "La mascota no pertenece a esta casa"));
            }
        }

        camara.setPerroId(perroId);
        CamaraDTO dto = CamaraDTO.fromEntity(camaraRepository.save(camara));
        rellenarDatosMascota(List.of(dto));
        return ResponseEntity.ok(dto);
    }

    /**
     * Registra una nueva cámara para una vivienda a partir de su URL de streaming.
     *
     * @param request datos de la cámara: casaId, nombre, urlStream y estado activo opcional.
     * @return la cámara creada, o un error 400 si faltan datos o la casa no existe.
     */
    @PostMapping
    public ResponseEntity<?> crearCamara(@RequestBody CamaraDTO request) {
        if (request.casaId == null) {
            return ResponseEntity.badRequest().body("{\"error\": \"casaId es requerido\"}");
        }
        if (!authContext.perteneceACasa(request.casaId)) {
            return ResponseEntity.status(403).body(java.util.Map.of("ok", false, "error", "No tienes acceso a esta vivienda", "message", "No tienes acceso a esta vivienda"));
        }

        if (!casaRepository.existsById(request.casaId)) {
            return ResponseEntity.badRequest().body("{\"error\": \"Casa no encontrada\"}");
        }

        Camara camara = new Camara();
        camara.setCasaId(request.casaId);
        camara.setNombre(request.nombre);
        camara.setUrlStream(request.urlStream);
        if (request.activo != null) {
            camara.setActivo(request.activo);
        }

        Camara guardada = camaraRepository.save(camara);
        return ResponseEntity.ok(CamaraDTO.fromEntity(guardada));
    }

    /**
     * Elimina una cámara del sistema.
     *
     * @param id identificador de la cámara a eliminar.
     * @return confirmación de la eliminación.
     */
    @DeleteMapping("/{id}")
    public ResponseEntity<?> eliminarCamara(@PathVariable Long id) {
        Camara camara = camaraRepository.findById(id).orElse(null);
        if (camara == null) {
            return ResponseEntity.status(404).body(java.util.Map.of("error", "Cámara no encontrada"));
        }
        if (!authContext.perteneceACasa(camara.getCasaId())) {
            return ResponseEntity.status(403).body(java.util.Map.of("ok", false, "error", "No tienes acceso a esta cámara", "message", "No tienes acceso a esta cámara"));
        }
        camaraRepository.deleteById(id);
        return ResponseEntity.ok("{\"ok\": true}");
    }

    /**
     * Genera un código QR con los datos necesarios para vincular una cámara
     * nueva a la vivienda (identificador único del stream, casa destino y
     * credenciales del usuario), pensado para que el dispositivo cámara lo escanee.
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado (opcional).
     * @param request datos de la cámara a vincular: casaId y nombre.
     * @return la imagen del QR en base64, o un error 400/500 según el caso.
     */
    @PostMapping("/qr-vinculacion")
    public ResponseEntity<?> generarQrVinculacion(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody CamaraDTO request) {
        
        if (request.casaId == null || request.nombre == null || request.nombre.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(java.util.Map.of("error", "casaId y nombre son requeridos"));
        }

        if (!casaRepository.existsById(request.casaId)) {
            return ResponseEntity.badRequest().body(java.util.Map.of("error", "Casa no encontrada"));
        }

        String token = "";
        Long userId = 0L;
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            token = authHeader.substring(7);
            userId = jwtUtil.getAuthenticatedUserId(authHeader);
        }

        // Generate unique UUID for camera stream
        String uniqueCamId = "webrtc:" + java.util.UUID.randomUUID().toString();

        // Create JSON payload for QR
        String qrPayload = String.format(
            "{\"action\":\"link_camera\",\"urlStream\":\"%s\",\"casaId\":%d,\"nombre\":\"%s\",\"userId\":%d,\"token\":\"%s\"}",
            uniqueCamId, request.casaId, request.nombre, userId, token
        );

        try {
            com.google.zxing.qrcode.QRCodeWriter qrCodeWriter = new com.google.zxing.qrcode.QRCodeWriter();
            com.google.zxing.common.BitMatrix bitMatrix = qrCodeWriter.encode(qrPayload, com.google.zxing.BarcodeFormat.QR_CODE, 300, 300);
            
            try (java.io.ByteArrayOutputStream pngOutputStream = new java.io.ByteArrayOutputStream()) {
                com.google.zxing.client.j2se.MatrixToImageWriter.writeToStream(bitMatrix, "PNG", pngOutputStream);
                byte[] qrBytes = pngOutputStream.toByteArray();
                String base64Qr = java.util.Base64.getEncoder().encodeToString(qrBytes);
                
                return ResponseEntity.ok(java.util.Map.of(
                    "ok", true,
                    "qrBase64", "data:image/png;base64," + base64Qr
                ));
            }
        } catch (Exception e) {
            return ResponseEntity.status(500).body(java.util.Map.of("error", "Error generando QR: " + e.getMessage()));
        }
    }

    /**
     * Completa la vinculación de una cámara nueva registrándola con la URL
     * de streaming que el dispositivo obtuvo tras escanear el QR de vinculación.
     *
     * @param request datos de la cámara a vincular: casaId, nombre y urlStream.
     * @return la cámara vinculada, o un error 400 si los datos son inválidos o la cámara ya estaba vinculada.
     */
    /**
     * Da de alta una cámara a partir de un dispositivo IoT que el hogar
     * detectó en su red, sin pasar por el código QR.
     *
     * <p>Comprueba que el dispositivo sea de la vivienda del usuario
     * autenticado antes de vincularlo, de modo que nadie pueda enganchar un
     * aparato de otra casa pasando su identificador a mano.</p>
     *
     * @param request dispositivo a vincular y nombre para la cámara.
     * @return la cámara creada, o 400/403 si los datos no son válidos o el dispositivo no es de tu casa.
     */
    @PostMapping("/vincular-dispositivo")
    public ResponseEntity<?> vincularDispositivo(@RequestBody VincularDispositivoDTO request) {
        Long casaId = authContext.casaIdActual();
        if (casaId == null) {
            return ResponseEntity.status(401).body(java.util.Map.of("ok", false, "error", "No autorizado"));
        }
        if (request.dispositivoId == null || request.nombre == null || request.nombre.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(java.util.Map.of("ok", false, "error", "Falta el dispositivo o el nombre"));
        }

        // El dispositivo tiene que colgar de una zona de esta misma casa.
        var duenos = jdbcTemplate.queryForList(
            "SELECT z.casa_id FROM dispositivo d JOIN zona z ON z.id = d.zona_id " +
            "WHERE d.id = ? AND d.deleted_at IS NULL", request.dispositivoId);
        if (duenos.isEmpty()) {
            return ResponseEntity.badRequest().body(java.util.Map.of("ok", false, "error", "Dispositivo no encontrado"));
        }
        Long casaDelDispositivo = ((Number) duenos.get(0).get("casa_id")).longValue();
        if (!casaId.equals(casaDelDispositivo)) {
            return ResponseEntity.status(403).body(java.util.Map.of("ok", false, "error", "Ese dispositivo no pertenece a tu vivienda"));
        }

        var yaVinculado = jdbcTemplate.queryForList(
            "SELECT id FROM camara WHERE dispositivo_id = ? AND activo = true", request.dispositivoId);
        if (!yaVinculado.isEmpty()) {
            return ResponseEntity.badRequest().body(java.util.Map.of("ok", false, "error", "Ese dispositivo ya está vinculado como cámara"));
        }

        String urlStream = "webrtc:disp-" + request.dispositivoId + "-" + java.util.UUID.randomUUID();
        jdbcTemplate.update(
            "INSERT INTO camara (casa_id, nombre, url_stream, activo, conectada, dispositivo_id) " +
            "VALUES (?, ?, ?, true, false, ?)",
            casaId, request.nombre.trim(), urlStream, request.dispositivoId);

        var creada = jdbcTemplate.queryForList(
            "SELECT id, casa_id, nombre, url_stream, activo, conectada, dispositivo_id " +
            "FROM camara WHERE url_stream = ?", urlStream);
        return ResponseEntity.ok(java.util.Map.of("ok", true, "camara", creada.isEmpty() ? java.util.Map.of() : creada.get(0)));
    }

    @PostMapping("/vincular")
    public ResponseEntity<?> vincularCamara(@RequestBody CamaraDTO request) {
        if (request.casaId == null || request.urlStream == null || request.nombre == null) {
            return ResponseEntity.badRequest().body(java.util.Map.of("error", "Datos incompletos para vincular"));
        }

        if (!casaRepository.existsById(request.casaId)) {
            return ResponseEntity.badRequest().body(java.util.Map.of("error", "Casa no encontrada"));
        }

        // Verify if camera already exists
        if (!camaraRepository.findByUrlStream(request.urlStream).isEmpty()) {
            return ResponseEntity.badRequest().body(java.util.Map.of("error", "La cámara ya fue vinculada"));
        }

        Camara camara = new Camara();
        camara.setCasaId(request.casaId);
        camara.setNombre(request.nombre);
        camara.setUrlStream(request.urlStream);
        camara.setActivo(true);
        camara.setConectada(false);
        Camara guardada = camaraRepository.save(camara);

        return ResponseEntity.ok(CamaraDTO.fromEntity(guardada));
    }
}
