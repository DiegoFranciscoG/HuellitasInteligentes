package com.huellitas.auth;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Tarea programada de mantenimiento que limpia periódicamente los tokens de
 * seguridad (inicio de sesión por QR, restablecimiento de contraseña) que ya
 * expiraron o fueron usados, para no acumular datos obsoletos en la base de datos.
 */
@Component
public class TokenCleanupTask {

    private static final Logger log = LoggerFactory.getLogger(TokenCleanupTask.class);
    private final JdbcTemplate jdbcTemplate;

    public TokenCleanupTask(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    // Se ejecuta diariamente a las 3 AM (o cada 12 horas en dev)
    /**
     * Elimina de la base de datos los tokens de inicio de sesión por QR y de
     * restablecimiento de contraseña que llevan más de 7 días expirados o usados.
     */
    @Scheduled(cron = "0 0 3 * * ?")
    public void purgarTokensExpirados() {
        try {
            int qrPurged = jdbcTemplate.update(
                "DELETE FROM qr_login_token WHERE (expires_at < NOW() - INTERVAL '7 days') OR (used = true AND created_at < NOW() - INTERVAL '7 days')"
            );
            int resetPurged = 0;
            try {
                resetPurged = jdbcTemplate.update(
                    "DELETE FROM password_reset_token WHERE (expiracion < NOW() - INTERVAL '7 days') OR (usado = true AND creado_en < NOW() - INTERVAL '7 days')"
                );
            } catch (Exception ignored) {}

            log.info("[CRON TOKEN CLEANUP] Purga de tokens antiguos finalizada. Tokens QR eliminados: {}, Tokens Reset eliminados: {}", qrPurged, resetPurged);
        } catch (Exception e) {
            log.error("[CRON TOKEN CLEANUP] Error al purgar tokens expirados", e);
        }
    }
}
