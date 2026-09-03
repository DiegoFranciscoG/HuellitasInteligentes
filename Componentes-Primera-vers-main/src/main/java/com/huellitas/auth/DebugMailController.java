package com.huellitas.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Endpoint de diagnóstico (no destinado a usuarios finales) para verificar
 * en tiempo de ejecución cómo quedó configurado el envío de correos del sistema.
 */
@RestController
@RequestMapping("/api/huellitas/_debug")
public class DebugMailController {

    @Value("${spring.mail.username:diegofgz2004@gmail.com}")
    private String mailFrom;

    @Value("${resend.api.key:}")
    private String resendApiKey;

    /**
     * Reporta qué proveedor de correo está activo y datos de configuración
     * (con la clave de API enmascarada) para depurar problemas de envío de correos.
     *
     * @return un mapa con el proveedor activo, la clave enmascarada y el remitente configurado.
     */
    @GetMapping("/mail-config")
    public ResponseEntity<?> getMailConfig() {
        String maskedKey = (resendApiKey != null && resendApiKey.length() > 4) 
            ? "..." + resendApiKey.substring(resendApiKey.length() - 4)
            : "NOT_CONFIGURED";

        boolean isResendActive = resendApiKey != null && !resendApiKey.trim().isEmpty();

        return ResponseEntity.ok(Map.of(
            "provedorActivo", isResendActive ? "Resend REST API" : "Gmail SMTP",
            "resendApiKeyMasked", maskedKey,
            "resendKeyLength", resendApiKey != null ? resendApiKey.length() : 0,
            "mailFromConfigured", mailFrom,
            "status", "ACTIVE"
        ));
    }
}
