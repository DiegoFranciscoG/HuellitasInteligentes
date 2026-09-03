package com.huellitas.auth;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.client.j2se.MatrixToImageWriter;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;
import java.io.ByteArrayOutputStream;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.security.SecureRandom;
import java.util.List;
import java.util.Map;

/**
 * Permite al propietario de una vivienda administrar a los miembros
 * (familiares/cuidadores) que comparten el acceso a sus mascotas y
 * dispositivos, y gestiona el inicio de sesión rápido por código QR:
 * generación, envío por correo y validación de los tokens QR, además del
 * cambio de contraseña obligatorio en el primer acceso de un miembro.
 */
@RestController
@RequestMapping("/api/huellitas/auth")
public class MiembroController {

    private final AuthRepository repo;
    private final AuthMailService mailService;
    private final JwtUtil jwtUtil;
    private final JdbcTemplate jdbcTemplate;
    private final com.huellitas.storage.S3Service s3Service;

    private final com.huellitas.config.AuthContext authContext;

    /** URL base de la web — usada en los enlaces de los correos (invitación de miembro, QR). */
    @org.springframework.beans.factory.annotation.Value("${app.web-url:http://localhost:4200}")
    private String appWebUrl;

    public MiembroController(AuthRepository repo, AuthMailService mailService, JwtUtil jwtUtil,
                             JdbcTemplate jdbcTemplate, com.huellitas.storage.S3Service s3Service,
                             com.huellitas.config.AuthContext authContext) {
        this.repo = repo;
        this.mailService = mailService;
        this.jwtUtil = jwtUtil;
        this.jdbcTemplate = jdbcTemplate;
        this.s3Service = s3Service;
        this.authContext = authContext;
    }

    /**
     * Deja el PNG del QR en el almacenamiento y devuelve una URL firmada para
     * incrustarlo en el correo. Se usa una imagen remota y no un data:image
     * porque Gmail bloquea las incrustadas en base64 y mostraba el icono roto.
     * La URL vive 25 horas, una más que el propio código, para que nunca
     * caduque el enlace antes que el QR. Devuelve null si el almacenamiento
     * falla: en ese caso el correo sale igual, solo con el adjunto.
     */
    private String publicarQrParaCorreo(byte[] qrBytes) {
        try {
            String key = s3Service.uploadBytes(qrBytes, "image/png", ".png");
            return s3Service.generatePresignedUrl(key, 25);
        } catch (Exception e) {
            org.slf4j.LoggerFactory.getLogger(MiembroController.class)
                .warn("[QR MAIL] No se pudo publicar la imagen del QR, se envía solo como adjunto: {}", e.toString());
            return null;
        }
    }

    /** Bloque HTML con el QR dentro del texto; si no hay imagen, remite al adjunto. */
    private String bloqueQrHtml(String urlQr) {
        if (urlQr != null) {
            return "<div style='text-align: center; margin: 20px 0;'>" +
                   "<img src='" + urlQr + "' alt='Código QR' width='200' height='200' style='width: 200px; height: 200px; display: block; margin: 0 auto;'/>" +
                   "<p style='color: #94a3b8; font-size: 12px; margin-top: 8px;'>También lo tienes adjunto como acceso_qr.png</p>" +
                   "</div>";
        }
        return "<div style='background: #eef2ff; border: 1px solid #c7d2fe; padding: 16px; border-radius: 12px; margin: 20px 0;'>" +
               "<p style='color: #3730a3; margin: 0; font-weight: bold;'>Tu codigo QR va adjunto a este correo</p>" +
               "<p style='color: #4338ca; margin: 6px 0 0 0; font-size: 14px;'>Busca el archivo <b>acceso_qr.png</b> al final del mensaje y escanealo desde la app.</p>" +
               "</div>";
    }

    /** Datos para invitar a un nuevo miembro a la vivienda. */
    public static class CrearMiembroDTO {
        public String email;
        public String password;
        public String nombre;
    }

    /** Token QR (sin procesar) que el cliente escaneó y quiere canjear por una sesión. */
    public static class ValidarQrDTO {
        public String rawToken;
    }

    /** Nueva contraseña que un miembro debe fijar en su primer acceso. */
    public static class CambiarPasswordObligatorioDTO {
        public String nuevaPassword;
    }

    // ─────────────────────────────────────────────────────────
    // 1. GESTIÓN DE MIEMBROS POR EL PROPIETARIO
    // ─────────────────────────────────────────────────────────

    /**
     * Crea un nuevo miembro dentro de la vivienda del propietario autenticado,
     * le asigna una contraseña temporal (autogenerada si no se envía una) y
     * le envía por correo esa contraseña junto con un QR de bienvenida
     * válido por 24 horas para el inicio de sesión rápido desde la app.
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del propietario autenticado.
     * @param dto datos del nuevo miembro: email, nombre y contraseña opcional.
     * @return los datos del miembro creado y si el correo de bienvenida se pudo enviar, o un error 401/400/500 según el caso.
     */
    @PostMapping(value = "/miembros", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> crearMiembro(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody CrearMiembroDTO dto) {
        Long ownerId = authContext.usuarioIdActual();
        Long casaId = authContext.casaIdActual();

        if (ownerId == null || casaId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "No autorizado o sin casa vinculada"));
        }

        if (dto == null || dto.nombre == null || !dto.nombre.matches("^[a-zA-ZáéíóúÁÉÍÓÚñÑ\\s]{2,60}$")) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "NOMBRE_INVALIDO"));
        }

        if (dto.email == null || !dto.email.contains("@")) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "EMAIL_INVALIDO"));
        }

        String autoPassword = (dto.password != null && !dto.password.trim().isEmpty()) 
            ? dto.password.trim() 
            : "H!" + java.util.UUID.randomUUID().toString().substring(0, 8) + "a9";

        try {
            String resJson = repo.invitarMiembro(casaId, dto.email.trim(), autoPassword, dto.nombre.trim());
            Long miembroId = extractUserIdFromJson(resJson);

            try {
                jdbcTemplate.update("UPDATE usuario SET debe_cambiar_password = true WHERE email = ?", dto.email);
            } catch (Exception ignored) {}

            boolean correoEnviado = false;
            String bienvenidaRawToken = null;
            if (miembroId != null) {
                bienvenidaRawToken = generarQrInterno(miembroId, "BIENVENIDA", 86400);
                String qrLoginUrl = appWebUrl + "/auth/qr-login?token=" + bienvenidaRawToken;
                
                try {
                    // Generar QR Code Image Bytes
                    QRCodeWriter qrCodeWriter = new QRCodeWriter();
                    BitMatrix bitMatrix = qrCodeWriter.encode(bienvenidaRawToken, BarcodeFormat.QR_CODE, 250, 250);
                    byte[] qrBytes;
                    try (ByteArrayOutputStream pngOutputStream = new ByteArrayOutputStream()) {
                        MatrixToImageWriter.writeToStream(bitMatrix, "PNG", pngOutputStream);
                        qrBytes = pngOutputStream.toByteArray();
                    }
                    
                    // El QR se incrusta como imagen remota (subida al almacenamiento),
                    // no como data:image, que es lo que Gmail bloqueaba.
                    String urlQr = publicarQrParaCorreo(qrBytes);
                    String contenidoEmail = String.format(
                        "<div style='font-family: sans-serif; padding: 24px; border: 1px solid #e2e8f0; border-radius: 16px; max-width: 480px; margin: auto;'>" +
                        "<h2 style='color: #4f46e5; margin-top: 0;'>Bienvenido a Huellitas Inteligentes</h2>" +
                        "<p style='color: #475569;'>Hola <b>%s</b>,</p>" +
                        "<p style='color: #475569;'>Tu cuenta de Miembro ha sido creada. A continuación tienes tu contraseña temporal:</p>" +
                        "<div style='background: #f1f5f9; padding: 16px; border-radius: 12px; font-size: 20px; text-align: center; color: #1e1b4b; margin: 20px 0; font-family: monospace;'>%s</div>" +
                        "<p style='color: #475569;'>Para ingresar más rápido desde tu celular, escanea este <b>Código QR</b> con la opción 'Escanear QR' de la app:</p>" +
                        "%s" +
                        "<p style='color: #475569;'>Si la app te pide un Token escrito manualmente, es este:</p>" +
                        "<div style='background: #e0e7ff; padding: 12px; border-radius: 8px; font-size: 16px; text-align: center; color: #3730a3; margin: 10px 0; font-family: monospace; word-break: break-all;'>%s</div>" +
                        "<p style='color: #94a3b8; font-size: 13px;'>El acceso QR es de un solo uso y expira en 24 horas.</p>" +
                        "</div>",
                        dto.nombre, autoPassword, bloqueQrHtml(urlQr), bienvenidaRawToken
                    );
                    correoEnviado = mailService.sendHtmlEmailWithAttachmentSync(dto.email, "Bienvenido a Huellitas Inteligentes", contenidoEmail, "acceso_qr.png", qrBytes);
                } catch (Exception mailEx) {
                    org.slf4j.LoggerFactory.getLogger(MiembroController.class).warn("[SMTP WARNING] Fallo al enviar correo a {}. Miembro creado exitosamente. Se puede usar Reenviar QR. Causa: {}", dto.email, mailEx.toString());
                }
            }

            return ResponseEntity.ok(Map.of(
                "ok", true,
                "correoEnviado", correoEnviado,
                "message", correoEnviado 
                    ? "Miembro registrado exitosamente. Se envió correo con contraseña y QR de Bienvenida (24h)."
                    : "El miembro fue registrado en el sistema, pero el correo de bienvenida no pudo entregarse. Puedes presionar 'Reenviar QR'.",
                "miembroId", miembroId != null ? miembroId : 0L,
                "qrBienvenidaToken", bienvenidaRawToken != null ? bienvenidaRawToken : ""
            ));
        } catch (Exception e) {
            String msg = e.getMessage();
            if (msg != null && msg.contains("CASA_YA_TIENE_MIEMBRO")) {
                return ResponseEntity.status(400).body(Map.of("ok", false, "error", "CASA_YA_TIENE_MIEMBRO"));
            } else if (msg != null && msg.contains("EMAIL_YA_REGISTRADO")) {
                return ResponseEntity.status(400).body(Map.of("ok", false, "error", "EMAIL_YA_REGISTRADO"));
            }
            return ResponseEntity.status(500).body(Map.of("ok", false, "error", e.getMessage() != null ? e.getMessage() : "Error interno"));
        }
    }

    /**
     * Lista los miembros activos de la vivienda del propietario autenticado,
     * indicando si cada uno ya activó su QR de bienvenida.
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del propietario autenticado.
     * @return la lista de miembros de la vivienda, o un error 401 si no está autenticado.
     */
    @GetMapping(value = "/miembros", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> listarMiembros(
            @RequestHeader(value = "Authorization", required = false) String authHeader) {
        Long casaId = authContext.casaIdActual();
        if (casaId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "No autorizado o sin casa vinculada"));
        }

        List<Map<String, Object>> miembros = jdbcTemplate.queryForList(
            "SELECT u.id, u.nombre, u.email, u.rol, u.casa_id, u.activo, u.created_at, " +
            "EXISTS(SELECT 1 FROM qr_login_token q WHERE q.usuario_id = u.id AND q.tipo = 'BIENVENIDA' AND q.used = true) as bienvenida_activada " +
            "FROM usuario u WHERE u.casa_id = ? AND u.rol = 'MIEMBRO' AND u.deleted_at IS NULL AND u.activo = true ORDER BY u.id DESC",
            casaId
        );
        return ResponseEntity.ok(miembros);
    }

    /**
     * Da de baja a un miembro de la vivienda del propietario autenticado.
     *
     * <p>La cuenta no se elimina: el miembro se desvincula de la casa
     * ({@code casa_id = NULL}) y queda como PROPIETARIO sin vivienda, que es
     * el estado "en espera" que atiende el onboarding. Puede volver a
     * iniciar sesión y crear su propia casa, pero pierde todo acceso al hogar
     * del que salió, porque el aislamiento se resuelve por {@code casa_id}.</p>
     *
     * <p>Se conserva de dónde salió en {@code casa_anterior_id} para que el
     * propietario siga viendo en su historial lo que esa persona hizo
     * mientras era miembro; ese campo no otorga ningún acceso.</p>
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del propietario autenticado.
     * @param id identificador del miembro a dar de baja.
     * @return confirmación de la baja, o un error 401/404 según el caso.
     */
    @DeleteMapping(value = "/miembros/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> eliminarMiembro(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @PathVariable Long id) {
        Long casaId = authContext.casaIdActual();
        if (casaId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "No autorizado"));
        }

        int rows = jdbcTemplate.update(
            "UPDATE usuario SET casa_anterior_id = casa_id, " +
            "                   casa_id = NULL, " +
            "                   rol = 'PROPIETARIO'::rol_usuario, " +
            "                   activo = true, " +
            "                   deleted_at = NULL " +
            "WHERE id = ? AND casa_id = ? AND rol = 'MIEMBRO' AND deleted_at IS NULL",
            id, casaId
        );

        if (rows > 0) {
            return ResponseEntity.ok(Map.of(
                "ok", true,
                "message", "Miembro dado de baja. Su cuenta queda en espera: podrá entrar y crear su propia casa, pero ya no ve la tuya."
            ));
        } else {
            return ResponseEntity.status(404).body(Map.of("ok", false, "error", "Miembro no encontrado o no pertenece a tu casa"));
        }
    }

    // ─────────────────────────────────────────────────────────
    // 2. GENERACIÓN, VALIDACIÓN DE QR Y CAMBIO OBLIGATORIO DE PASSWORD
    // ─────────────────────────────────────────────────────────

    /**
     * Genera un nuevo token de acceso por QR para el usuario autenticado (o
     * para un miembro indicado por el propietario). El tipo
     * {@code ACCESO_RAPIDO} dura 90 segundos (pensado para escanear en el
     * momento); el tipo {@code BIENVENIDA} dura 24 horas y además reenvía el
     * QR por correo.
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado.
     * @param miembroId identificador del miembro para el que se genera el QR (opcional; si se omite, se usa el usuario autenticado).
     * @param tipo tipo de QR a generar: {@code ACCESO_RAPIDO} (por defecto) o {@code BIENVENIDA}.
     * @return el token QR generado, su duración en segundos y su tipo, o un error 401 si no está autenticado.
     */
    @PostMapping(value = "/qr/generar", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> generarQrToken(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestParam(required = false) Long miembroId,
            @RequestParam(defaultValue = "ACCESO_RAPIDO") String tipo) {
        Long userId = miembroId != null ? miembroId : authContext.usuarioIdActual();
        if (userId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "No autorizado"));
        }
        if (miembroId != null) {
            // Generar un QR de acceso para OTRO usuario solo puede hacerlo el
            // propietario de esa misma casa — si no, cualquiera podría pedir
            // un QR de inicio de sesión para la cuenta de otra persona.
            Long casaDelMiembro = jdbcTemplate.queryForList("SELECT casa_id FROM usuario WHERE id = ?", miembroId)
                .stream().findFirst().map(m -> ((Number) m.get("casa_id")).longValue()).orElse(null);
            if (!authContext.perteneceACasa(casaDelMiembro)) {
                return ResponseEntity.status(403).body(Map.of("ok", false, "error", "No tienes permiso para generar un QR de acceso para ese usuario"));
            }
        }

        String tipoUpper = tipo != null && tipo.equalsIgnoreCase("BIENVENIDA") ? "BIENVENIDA" : "ACCESO_RAPIDO";
        int duracionSegundos = "BIENVENIDA".equals(tipoUpper) ? 86400 : 90;

        String rawToken = generarQrInterno(userId, tipoUpper, duracionSegundos);

        if ("BIENVENIDA".equals(tipoUpper)) {
            try {
                List<Map<String, Object>> u = jdbcTemplate.queryForList("SELECT email, nombre FROM usuario WHERE id = ?", userId);
                if (!u.isEmpty()) {
                    String email = (String) u.get(0).get("email");
                    String nombre = (String) u.get(0).get("nombre");
                    
                    QRCodeWriter qrCodeWriter = new QRCodeWriter();
                    BitMatrix bitMatrix = qrCodeWriter.encode(rawToken, BarcodeFormat.QR_CODE, 250, 250);
                    byte[] qrBytes;
                    try (ByteArrayOutputStream pngOutputStream = new ByteArrayOutputStream()) {
                        MatrixToImageWriter.writeToStream(bitMatrix, "PNG", pngOutputStream);
                        qrBytes = pngOutputStream.toByteArray();
                    }
                    
                    // Imagen remota en lugar de data:image, que Gmail bloquea.
                    String urlQr = publicarQrParaCorreo(qrBytes);
                    String contenidoEmail = String.format(
                        "<div style='font-family: sans-serif; padding: 24px; border: 1px solid #e2e8f0; border-radius: 16px; max-width: 480px; margin: auto;'>" +
                        "<h2 style='color: #4f46e5; margin-top: 0;'>Nuevo QR de Bienvenida</h2>" +
                        "<p style='color: #475569;'>Hola %s,</p>" +
                        "<p style='color: #475569;'>Se ha generado un nuevo QR de Bienvenida para ti. Escanéalo desde la app móvil con la opción 'Escanear QR':</p>" +
                        "%s" +
                        "<p style='color: #475569;'>Si la app te pide un Token en texto, es este:</p>" +
                        "<div style='background: #e0e7ff; padding: 12px; border-radius: 8px; font-size: 16px; text-align: center; color: #3730a3; margin: 10px 0; font-family: monospace; word-break: break-all;'>%s</div>" +
                        "<p style='color: #94a3b8; font-size: 13px;'>Este código es de un solo uso y expira en 24 horas.</p>" +
                        "</div>",
                        nombre, bloqueQrHtml(urlQr), rawToken
                    );
                    mailService.sendHtmlEmailWithAttachmentSync(email, "Nuevo QR de Bienvenida - Huellitas", contenidoEmail, "acceso_qr.png", qrBytes);
                }
            } catch (Exception mailEx) {
                // Antes se descartaba en silencio, asi que un fallo de correo no
                // dejaba ninguna pista al revisar el log del backend.
                org.slf4j.LoggerFactory.getLogger(MiembroController.class)
                    .warn("[QR MAIL] No se pudo enviar el QR de bienvenida al usuario {}: {}", userId, mailEx.toString());
            }
        }

        return ResponseEntity.ok(Map.of(
            "ok", true,
            "raw_token", rawToken,
            "expires_in", duracionSegundos,
            "tipo", tipoUpper
        ));
    }

    /**
     * Canjea un token QR escaneado por una sesión: valida que el token no
     * esté usado ni expirado, lo marca como usado (de un solo uso) y entrega
     * un JWT de sesión para el usuario dueño del token.
     *
     * @param dto contiene el token QR sin procesar (tal cual fue escaneado).
     * @return el token JWT y los datos del usuario si el QR es válido, o un error 400/401 según el caso.
     */
    @PostMapping(value = "/qr/validar", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> validarQrToken(@RequestBody ValidarQrDTO dto) {
        if (dto == null || dto.rawToken == null || dto.rawToken.trim().isEmpty()) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "Token QR no proporcionado"));
        }

        String tokenHash = CryptoUtils.sha256(dto.rawToken.trim());

        List<Map<String, Object>> rows = jdbcTemplate.queryForList(
            "UPDATE qr_login_token SET used = true WHERE token_hash = ? AND used = false AND expires_at > NOW() RETURNING usuario_id, tipo",
            tokenHash
        );

        if (rows.isEmpty()) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "Token QR inválido, usado o expirado"));
        }

        Long usuarioId = ((Number) rows.get(0).get("usuario_id")).longValue();
        String tipoToken = (String) rows.get(0).get("tipo");

        Map<String, Object> userMap;
        try {
            userMap = jdbcTemplate.queryForMap(
                "SELECT id, nombre, email, rol, casa_id, email_verificado, COALESCE(debe_cambiar_password, false) as debe_cambiar_password FROM usuario WHERE id = ? AND deleted_at IS NULL AND activo = true",
                usuarioId
            );
        } catch (Exception e) {
            userMap = jdbcTemplate.queryForMap(
                "SELECT id, nombre, email, rol, casa_id, email_verificado, false as debe_cambiar_password FROM usuario WHERE id = ? AND deleted_at IS NULL AND activo = true",
                usuarioId
            );
        }

        String userJson = String.format(
            "{\"id\":%d, \"nombre\":\"%s\", \"email\":\"%s\", \"rol\":\"%s\", \"casa_id\":%s, \"email_verificado\":%b, \"debe_cambiar_password\":%b}",
            usuarioId,
            userMap.get("nombre"),
            userMap.get("email"),
            userMap.get("rol"),
            userMap.get("casa_id") != null ? userMap.get("casa_id").toString() : "null",
            Boolean.TRUE.equals(userMap.get("email_verificado")),
            Boolean.TRUE.equals(userMap.get("debe_cambiar_password"))
        );

        String jwt = jwtUtil.generateTokenFromJsonUser(userJson);

        return ResponseEntity.ok(Map.of(
            "token", jwt,
            "tipoToken", tipoToken != null ? tipoToken : "ACCESO_RAPIDO",
            "usuario", userMap
        ));
    }

    /**
     * Permite a un miembro fijar su propia contraseña la primera vez que
     * inicia sesión (reemplazando la contraseña temporal asignada al crear su cuenta).
     *
     * @param authHeader encabezado {@code Authorization} con el JWT del usuario autenticado.
     * @param dto contiene la nueva contraseña, de al menos 6 caracteres.
     * @return confirmación del cambio, o un error 401/400/500 según el caso.
     */
    @PostMapping(value = "/cambiar-password-obligatorio", consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> cambiarPasswordObligatorio(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody CambiarPasswordObligatorioDTO dto) {
        Long usuarioId = authContext.usuarioIdActual();
        if (usuarioId == null) {
            return ResponseEntity.status(401).body(Map.of("ok", false, "error", "No autorizado"));
        }

        if (dto == null || dto.nuevaPassword == null || dto.nuevaPassword.trim().length() < 6) {
            return ResponseEntity.status(400).body(Map.of("ok", false, "error", "La contraseña debe tener al menos 6 caracteres"));
        }

        try {
            jdbcTemplate.update(
                "UPDATE usuario SET password_hash = crypt(?, gen_salt('bf')), debe_cambiar_password = false WHERE id = ?",
                dto.nuevaPassword.trim(), usuarioId
            );

            return ResponseEntity.ok(Map.of("ok", true, "message", "Contraseña actualizada exitosamente."));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(Map.of("ok", false, "error", e.getMessage()));
        }
    }

    // ─────────────────────────────────────────────────────────
    // HELPERS DE TOKEN Y QR
    // ─────────────────────────────────────────────────────────

    /**
     * Genera un token QR aleatorio, guarda su hash en la base de datos con
     * el tipo y la vigencia indicados, y devuelve el token sin procesar
     * (el que se codifica en la imagen QR y se le entrega al cliente).
     *
     * @param userId identificador del usuario dueño del token.
     * @param tipo tipo de token ({@code ACCESO_RAPIDO} o {@code BIENVENIDA}).
     * @param duracionSegundos segundos de vigencia del token antes de expirar.
     * @return el token QR sin procesar.
     */
    private String generarQrInterno(Long userId, String tipo, int duracionSegundos) {
        byte[] randomBytes = new byte[32];
        new SecureRandom().nextBytes(randomBytes);
        StringBuilder sb = new StringBuilder();
        for (byte b : randomBytes) sb.append(String.format("%02x", b));
        String rawToken = sb.toString();

        String tokenHash = CryptoUtils.sha256(rawToken);

        jdbcTemplate.update(
            "INSERT INTO qr_login_token (usuario_id, token_hash, used, expires_at, created_at, tipo) VALUES (?, ?, false, NOW() + interval '" + duracionSegundos + " seconds', NOW(), ?)",
            userId, tokenHash, tipo
        );

        return rawToken;
    }

    private Long extractUserIdFromJson(String json) {
        if (json == null) return null;
        String key = "\"id\":";
        int start = json.indexOf(key);
        if (start < 0) return null;
        start += key.length();
        int end = json.indexOf(",", start);
        if (end < 0) end = json.indexOf("}", start);
        if (end > start) {
            try {
                return Long.parseLong(json.substring(start, end).trim());
            } catch (Exception e) {
                return null;
            }
        }
        return null;
    }
}
