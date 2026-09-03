package com.fernando.esp32.service;

import com.huellitas.config.AuthContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * Persiste en la base de datos los comandos que el sistema envía a los
 * actuadores del ESP32, para dejar trazabilidad del historial de acciones
 * ejecutadas sobre cada dispositivo.
 *
 * <p>Cuando la petición trae un JWT válido, el comando queda firmado con el
 * usuario que lo disparó y con origen {@code APP}; si no hay sesión —porque
 * lo disparó el propio motor de automatización o el firmware— se guarda sin
 * usuario y con origen {@code REGLA}. Esa distinción es la que permite ver
 * en el historial qué hizo cada integrante del hogar y qué hizo el sistema
 * por su cuenta.</p>
 */
@Service
public class IotDatabaseService {

    private final JdbcTemplate jdbcTemplate;
    private final AuthContext authContext;

    public IotDatabaseService(JdbcTemplate jdbcTemplate, AuthContext authContext) {
        this.jdbcTemplate = jdbcTemplate;
        this.authContext = authContext;
    }

    /**
     * Inserta un registro de comando (activar/desactivar) para el
     * dispositivo identificado por su dirección MAC, anotando quién lo
     * ejecutó cuando la petición viene autenticada. Si el dispositivo no
     * existe o está eliminado, la inserción simplemente no afecta filas; los
     * errores de base de datos se registran en la salida estándar sin
     * interrumpir el flujo de la aplicación.
     *
     * @param macAddress dirección MAC (o identificador lógico) del dispositivo destino.
     * @param activado {@code true} si el comando es de activación, {@code false} si es de desactivación.
     */
    public void registrarComando(String macAddress, boolean activado) {
        String comando = activado ? "ACTIVAR" : "DESACTIVAR";

        // Fuera de una petición HTTP (por ejemplo, desde una tarea
        // programada) no hay contexto de seguridad: usuarioIdActual() es null
        // y el comando queda registrado como acción del sistema.
        Long usuarioId = null;
        try {
            usuarioId = authContext.usuarioIdActual();
        } catch (Exception ignored) {
            // Sin contexto de seguridad disponible; se registra sin usuario.
        }
        String origen = usuarioId != null ? "APP" : "REGLA";

        String sql = "INSERT INTO actuador_comando (dispositivo_id, comando, origen, ejecutado_por) " +
                     "SELECT id, ?::comando_actuador, ?::origen_comando, ? " +
                     "FROM dispositivo WHERE mac_address = ? AND deleted_at IS NULL LIMIT 1";
        try {
            jdbcTemplate.update(sql, comando, origen, usuarioId, macAddress);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
