package com.huellitas.momento;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.huellitas.storage.S3Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

/**
 * Limpieza de "Momentos de tu mascota", con el mismo patrón que
 * {@link com.huellitas.auth.TokenCleanupTask}: borra del bucket los
 * fragmentos que nadie guardó y ya vencieron. El enlace firmado ya dejó de
 * servir por su cuenta antes de que esto corra — esto es solo liberar espacio
 * real en Backblaze B2 y no acumular filas muertas.
 */
@Component
public class MomentoMascotaCleanupJob {

    private static final Logger log = LoggerFactory.getLogger(MomentoMascotaCleanupJob.class);

    private final JdbcTemplate jdbc;
    private final S3Service s3Service;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public MomentoMascotaCleanupJob(JdbcTemplate jdbc, S3Service s3Service) {
        this.jdbc = jdbc;
        this.s3Service = s3Service;
    }

    @Scheduled(fixedRate = 5 * 60 * 1000)
    public void purgarFragmentosVencidos() {
        List<Map<String, Object>> vencidos;
        try {
            vencidos = jdbc.queryForList(
                "SELECT id, claves_fragmento::text AS claves_json FROM momento_mascota " +
                "WHERE guardado = false AND expira_at < now()");
        } catch (Exception e) {
            log.error("[MOMENTOS MASCOTA] Error listando fragmentos vencidos", e);
            return;
        }
        if (vencidos.isEmpty()) return;

        int objetosBorrados = 0;
        for (Map<String, Object> fila : vencidos) {
            for (String clave : parsearClaves((String) fila.get("claves_json"))) {
                try {
                    s3Service.eliminarObjeto(clave);
                    objetosBorrados++;
                } catch (Exception e) {
                    log.warn("[MOMENTOS MASCOTA] No se pudo borrar el objeto {}: {}", clave, e.getMessage());
                }
            }
        }

        int filasBorradas = jdbc.update("DELETE FROM momento_mascota WHERE guardado = false AND expira_at < now()");
        log.info("[MOMENTOS MASCOTA] Limpieza: {} fragmentos vencidos, {} objetos borrados del bucket",
            filasBorradas, objetosBorrados);
    }

    private List<String> parsearClaves(String clavesJson) {
        try {
            return objectMapper.readValue(clavesJson, objectMapper.getTypeFactory()
                .constructCollectionType(List.class, String.class));
        } catch (Exception e) {
            log.warn("[MOMENTOS MASCOTA] No se pudieron leer las claves de fragmento: {}", e.getMessage());
            return List.of();
        }
    }
}
