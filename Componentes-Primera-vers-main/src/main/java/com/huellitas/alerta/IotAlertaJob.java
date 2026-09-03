package com.huellitas.alerta;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Genera automáticamente las alertas que el dueño de un dispositivo IoT ve en
 * su propia vivienda, con los mismos tres criterios que ya usa el panel de
 * monitoreo del administrador (ver {@code AdminRepository#listarDispositivosIoT}):
 * nunca dio señal, lleva más de 24 horas sin dar señal, o quedó en estado de
 * error. "Sin conexión ahora" (menos de 5 minutos) también genera un aviso,
 * más suave, para no descubrir un aparato apagado solo al revisar la app.
 *
 * <p>Cada condición se inserta como máximo una vez mientras siga sin
 * resolverse (la comprobación {@code NOT EXISTS ... leida = false} evita
 * llenar el historial con la misma alerta cada 5 minutos), y en cuanto el
 * aparato vuelve a dar señal reciente, las alertas pendientes de ese
 * dispositivo se marcan como leídas solas: nadie tiene que "cerrarlas" a
 * mano cuando el problema ya se resolvió.</p>
 */
@Component
public class IotAlertaJob {

    private static final Logger log = LoggerFactory.getLogger(IotAlertaJob.class);
    private final JdbcTemplate jdbc;

    public IotAlertaJob(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Scheduled(fixedRate = 5 * 60 * 1000) // cada 5 minutos
    public void revisarDispositivos() {
        try {
            int nuncaConecto = jdbc.update(
                "INSERT INTO alerta (casa_id, dispositivo_id, tipo, mensaje, severidad) " +
                "SELECT z.casa_id, d.id, 'IOT_NUNCA_CONECTO', " +
                "  'Tu dispositivo \"' || COALESCE(d.modelo, d.mac_address) || '\" nunca ha dado señal. Comprueba que esté encendido y conectado al WiFi.', " +
                "  'ADVERTENCIA'::severidad_alerta " +
                "FROM dispositivo d JOIN zona z ON z.id = d.zona_id " +
                "WHERE d.deleted_at IS NULL AND d.ultima_conexion IS NULL " +
                "  AND d.created_at < now() - interval '10 minutes' " +
                "  AND NOT EXISTS (SELECT 1 FROM alerta a WHERE a.dispositivo_id = d.id AND a.tipo = 'IOT_NUNCA_CONECTO' AND a.leida = false)");

            int offline = jdbc.update(
                "INSERT INTO alerta (casa_id, dispositivo_id, tipo, mensaje, severidad) " +
                "SELECT z.casa_id, d.id, 'IOT_OFFLINE', " +
                "  'Tu dispositivo \"' || COALESCE(d.modelo, d.mac_address) || '\" no da señal desde hace más de 5 minutos.', " +
                "  'ADVERTENCIA'::severidad_alerta " +
                "FROM dispositivo d JOIN zona z ON z.id = d.zona_id " +
                "WHERE d.deleted_at IS NULL AND d.ultima_conexion IS NOT NULL " +
                "  AND d.ultima_conexion < now() - interval '5 minutes' " +
                "  AND NOT EXISTS (SELECT 1 FROM alerta a WHERE a.dispositivo_id = d.id AND a.tipo = 'IOT_OFFLINE' AND a.leida = false)");

            int critico = jdbc.update(
                "INSERT INTO alerta (casa_id, dispositivo_id, tipo, mensaje, severidad) " +
                "SELECT z.casa_id, d.id, 'IOT_CRITICO', " +
                "  CASE WHEN d.estado::text = 'ERROR' " +
                "       THEN 'Tu dispositivo \"' || COALESCE(d.modelo, d.mac_address) || '\" reportó un error.' " +
                "       ELSE 'Tu dispositivo \"' || COALESCE(d.modelo, d.mac_address) || '\" lleva más de 24 horas sin dar señal.' END, " +
                "  'CRITICA'::severidad_alerta " +
                "FROM dispositivo d JOIN zona z ON z.id = d.zona_id " +
                "WHERE d.deleted_at IS NULL " +
                "  AND (d.estado::text = 'ERROR' OR (d.ultima_conexion IS NOT NULL AND d.ultima_conexion < now() - interval '24 hours')) " +
                "  AND NOT EXISTS (SELECT 1 FROM alerta a WHERE a.dispositivo_id = d.id AND a.tipo = 'IOT_CRITICO' AND a.leida = false)");

            // El aparato volvió a dar señal reciente: lo que estaba pendiente ya no aplica.
            int resueltas = jdbc.update(
                "UPDATE alerta SET leida = true " +
                "WHERE leida = false AND dispositivo_id IS NOT NULL " +
                "  AND tipo IN ('IOT_NUNCA_CONECTO','IOT_OFFLINE','IOT_CRITICO') " +
                "  AND dispositivo_id IN (" +
                "    SELECT d.id FROM dispositivo d " +
                "    WHERE d.estado::text <> 'ERROR' AND d.ultima_conexion IS NOT NULL " +
                "      AND d.ultima_conexion > now() - interval '5 minutes')");

            if (nuncaConecto + offline + critico + resueltas > 0) {
                log.info("[ALERTAS IOT] nunca conectó: {}, offline: {}, críticas: {}, auto-resueltas: {}",
                    nuncaConecto, offline, critico, resueltas);
            }
        } catch (Exception e) {
            log.error("[ALERTAS IOT] Error generando alertas de dispositivos", e);
        }
    }
}
