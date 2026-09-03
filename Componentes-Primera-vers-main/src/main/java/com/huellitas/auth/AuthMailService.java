package com.huellitas.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

/**
 * Envía los correos transaccionales del sistema (verificación de cuenta,
 * restablecimiento de contraseña, bienvenida y mensajes personalizados)
 * usando la API REST de Brevo como proveedor de correo.
 */
@Service
public class AuthMailService {
    private static final Logger logger = LoggerFactory.getLogger(AuthMailService.class);
    
    @Value("${app.frontend.url:http://localhost:4200}")
    private String frontendUrl;

    private final String BREVO_API_URL = "https://api.brevo.com/v3/smtp/email";

    // La clave llega por configuración (variable de entorno BREVO_API_KEY);
    // antes estaba escrita aquí y se subía al repositorio.
    @Value("${brevo.api.key:}")
    private String apiKey;

    @Value("${brevo.sender.email:diego.granda.est@tecazuay.edu.ec}")
    private String senderEmail;

    @Value("${brevo.sender.name:Huellitas App}")
    private String senderName;

    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;

    public AuthMailService(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build();
    }

    /**
     * Envía un correo HTML de forma síncrona, sin adjuntos.
     *
     * @param to destinatario del correo.
     * @param subject asunto del correo.
     * @param htmlContent cuerpo del correo en formato HTML.
     * @return {@code true} si Brevo aceptó el envío.
     */
    public boolean sendHtmlEmailSync(String to, String subject, String htmlContent) {
        return sendHtmlEmailWithAttachmentSync(to, subject, htmlContent, null, null);
    }

    /**
     * Envía un correo HTML de forma síncrona, opcionalmente con un archivo adjunto.
     *
     * @param to destinatario del correo.
     * @param subject asunto del correo.
     * @param htmlContent cuerpo del correo en formato HTML.
     * @param attachmentName nombre del archivo adjunto, o {@code null} si no hay adjunto.
     * @param attachmentBytes contenido binario del archivo adjunto, o {@code null} si no hay adjunto.
     * @return {@code true} si Brevo aceptó el envío (código HTTP 201).
     */
    public boolean sendHtmlEmailWithAttachmentSync(String to, String subject, String htmlContent, String attachmentName, byte[] attachmentBytes) {
        try {
            ObjectNode payload = objectMapper.createObjectNode();
            
            ObjectNode sender = objectMapper.createObjectNode();
            sender.put("name", senderName);
            sender.put("email", senderEmail);
            payload.set("sender", sender);
            
            ArrayNode toArray = objectMapper.createArrayNode();
            ObjectNode toObj = objectMapper.createObjectNode();
            toObj.put("email", to);
            toArray.add(toObj);
            payload.set("to", toArray);
            
            payload.put("subject", subject);
            payload.put("htmlContent", htmlContent);
            
            if (attachmentBytes != null && attachmentName != null) {
                ArrayNode attachmentArray = objectMapper.createArrayNode();
                ObjectNode attachment = objectMapper.createObjectNode();
                attachment.put("name", attachmentName);
                attachment.put("content", java.util.Base64.getEncoder().encodeToString(attachmentBytes));
                attachmentArray.add(attachment);
                // El campo de Brevo es "attachment" en singular. Con "attachments"
                // la API acepta el correo con 201 pero descarta el adjunto sin
                // avisar, y el QR nunca llegaba (Gmail además bloquea las
                // imagenes embebidas como data:image, asi que no quedaba nada).
                payload.set("attachment", attachmentArray);
            }
            
            String jsonPayload = objectMapper.writeValueAsString(payload);

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(BREVO_API_URL))
                    .header("Content-Type", "application/json")
                    .header("api-key", apiKey)
                    .POST(HttpRequest.BodyPublishers.ofString(jsonPayload))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            
            if (response.statusCode() == 201) {
                logger.info("[BREVO API SUCCESS] EMAIL HTML ENVIADO EXITOSAMENTE a {} (adjunto: {})",
                        to, attachmentName != null ? attachmentName : "ninguno");
                return true;
            } else {
                logger.error("[BREVO API ERROR] Fallo al enviar email HTML a {}. Status Code: {}. Body: {}", to, response.statusCode(), response.body());
                return false;
            }
        } catch (Exception e) {
            logger.error("[BREVO API ERROR] Fallo al enviar email HTML a {}: {}", to, e.getMessage());
            return false;
        }
    }

    /**
     * Construye y envía de forma síncrona el correo de verificación de cuenta con el código de 6 dígitos.
     *
     * @param to destinatario del correo.
     * @param nombre nombre del usuario, usado en el saludo (se usa "Usuario" si es {@code null}).
     * @param codigo código de verificación de 6 dígitos.
     * @return {@code true} si el correo se envió correctamente.
     */
    public boolean sendVerificationEmailSync(String to, String nombre, String codigo) {
        String subject = "Verifica tu correo electrónico - Huellitas Inteligentes";
        String htmlContent = "<div style='font-family: sans-serif; padding: 24px; border: 1px solid #e2e8f0; border-radius: 16px; max-width: 480px; margin: auto;'>" +
            "<h2 style='color: #4f46e5; margin-top: 0;'>Verificación de Correo</h2>" +
            "<p style='color: #475569;'>Hola " + (nombre != null ? nombre : "Usuario") + ", gracias por registrarte en Huellitas Inteligentes. Tu código de verificación de 6 dígitos es:</p>" +
            "<div style='background: #f1f5f9; padding: 16px; border-radius: 12px; font-size: 28px; letter-spacing: 6px; font-weight: bold; text-align: center; color: #1e1b4b; margin: 20px 0; font-family: monospace;'>" + codigo + "</div>" +
            "<p style='color: #94a3b8; font-size: 13px;'>Si no solicitaste este código, puedes ignorar este correo.</p>" +
            "</div>";

        return sendHtmlEmailSync(to, subject, htmlContent);
    }

    /**
     * Envía en segundo plano (sin bloquear al llamador) el correo de verificación de cuenta.
     *
     * @param to destinatario del correo.
     * @param nombre nombre del usuario.
     * @param codigo código de verificación de 6 dígitos.
     */
    @Async
    public void sendVerificationEmail(String to, String nombre, String codigo) {
        sendVerificationEmailSync(to, nombre, codigo);
    }

    /**
     * Construye y envía de forma síncrona el correo de restablecimiento de
     * contraseña con el enlace (o token) para completar el cambio.
     *
     * @param to destinatario del correo.
     * @param resetTokenOrContent enlace completo o token de restablecimiento; si no empieza con "http" se arma el enlace con la URL del frontend.
     * @return {@code true} si el correo se envió correctamente.
     */
    public boolean sendPasswordResetEmailSync(String to, String resetTokenOrContent) {
        String resetLink = resetTokenOrContent.startsWith("http") ? resetTokenOrContent : (frontendUrl + "/auth/reset-password?token=" + resetTokenOrContent);
        String subject = "Restablece tu contraseña - Huellitas Inteligentes";
        String htmlContent = "<div style='font-family: sans-serif; padding: 24px; border: 1px solid #e2e8f0; border-radius: 16px; max-width: 480px; margin: auto;'>" +
            "<h2 style='color: #4f46e5; margin-top: 0;'>Recuperación de Contraseña</h2>" +
            "<p style='color: #475569;'>Hemos recibido una solicitud para restablecer la contraseña de tu cuenta en Huellitas Inteligentes.</p>" +
            "<p style='color: #475569;'>Haz clic en el siguiente botón para continuar (válido por 30 minutos):</p>" +
            "<div style='text-align: center; margin: 30px 0;'>" +
            "<a href='" + resetLink + "' style='background: #4f46e5; color: white; text-decoration: none; padding: 14px 28px; border-radius: 8px; font-weight: bold; display: inline-block;'>Restablecer Contraseña</a>" +
            "</div>" +
            "<p style='color: #94a3b8; font-size: 13px; margin-top: 20px;'>Si no solicitaste este cambio, puedes ignorar este mensaje de forma segura.</p>" +
            "</div>";

        return sendHtmlEmailSync(to, subject, htmlContent);
    }

    /**
     * Envía en segundo plano (sin bloquear al llamador) el correo de restablecimiento de contraseña.
     *
     * @param to destinatario del correo.
     * @param resetTokenOrContent enlace completo o token de restablecimiento.
     */
    @Async
    public void sendPasswordResetEmail(String to, String resetTokenOrContent) {
        sendPasswordResetEmailSync(to, resetTokenOrContent);
    }

    /**
     * Construye y envía de forma síncrona el correo de bienvenida tras verificar la cuenta.
     *
     * @param to destinatario del correo.
     * @param nombre nombre del usuario.
     * @return {@code true} si el correo se envió correctamente.
     */
    public boolean sendWelcomeEmailSync(String to, String nombre) {
        String subject = "Bienvenido a Huellitas Inteligentes";
        String htmlContent = "<div style='font-family: sans-serif; padding: 24px; border: 1px solid #e2e8f0; border-radius: 16px; max-width: 480px; margin: auto;'>" +
            "<h2 style='color: #4f46e5; margin-top: 0;'>¡Bienvenido!</h2>" +
            "<p style='color: #475569;'>Hola " + (nombre != null ? nombre : "Usuario") + ", gracias por unirte a Huellitas Inteligentes. Tu cuenta ha sido verificada con éxito.</p>" +
            "<p style='color: #475569;'>Ahora puedes acceder a todas las funciones de la aplicación, controlar los dispositivos y formar parte de la comunidad.</p>" +
            "</div>";

        return sendHtmlEmailSync(to, subject, htmlContent);
    }

    /**
     * Envía en segundo plano (sin bloquear al llamador) el correo de bienvenida.
     *
     * @param to destinatario del correo.
     * @param nombre nombre del usuario.
     */
    @Async
    public void sendWelcomeEmail(String to, String nombre) {
        sendWelcomeEmailSync(to, nombre);
    }

    /**
     * Envía de forma síncrona un correo con contenido de texto libre,
     * envuelto en la plantilla HTML estándar del sistema.
     *
     * @param to destinatario del correo.
     * @param subject asunto del correo.
     * @param content contenido del mensaje (los saltos de línea se convierten en {@code <br>}).
     * @return {@code true} si el correo se envió correctamente.
     */
    public boolean sendCustomEmailSync(String to, String subject, String content) {
        String htmlContent = "<div style='font-family: sans-serif; padding: 24px; border: 1px solid #e2e8f0; border-radius: 16px; max-width: 480px; margin: auto;'>" +
            "<p style='color: #475569;'>" + content.replace("\n", "<br>") + "</p>" +
            "</div>";
        return sendHtmlEmailSync(to, subject, htmlContent);
    }

    /**
     * Envía en segundo plano (sin bloquear al llamador) un correo con contenido de texto libre.
     *
     * @param to destinatario del correo.
     * @param subject asunto del correo.
     * @param content contenido del mensaje.
     */
    @Async
    public void sendCustomEmail(String to, String subject, String content) {
        sendCustomEmailSync(to, subject, content);
    }
}
