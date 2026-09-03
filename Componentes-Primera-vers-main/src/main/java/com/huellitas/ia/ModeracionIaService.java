package com.huellitas.ia;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.List;
import java.util.Map;

/**
 * Evalúa automáticamente los reportes de contenido de la comunidad usando un
 * modelo de OpenAI: si la confianza es alta, aplica un strike o descarta la
 * denuncia sin intervención humana; en los casos ambiguos, deja el reporte
 * pendiente de revisión por un administrador.
 */
@Service
public class ModeracionIaService {
    private static final Logger log = LoggerFactory.getLogger(ModeracionIaService.class);

    @Value("${openai.api.key.moderacion:}")
    private String openAiApiKey;

    private final RestTemplate restTemplate;
    private final JdbcTemplate jdbcTemplate;

    public ModeracionIaService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(4000);
        factory.setReadTimeout(6000);
        this.restTemplate = new RestTemplate(factory);
    }

    /** Veredicto de la IA sobre un contenido denunciado, con su nivel de confianza y una justificación breve. */
    public static record ResultadoModeracion(String categoria, double confianza, String motivo) {}

    /**
     * Consulta a la IA si un contenido denunciado viola las normas de la
     * comunidad, considerando también el motivo de la denuncia.
     *
     * @param contenido texto denunciado a evaluar.
     * @param motivoDenuncia motivo indicado por quien denunció.
     * @return el veredicto de la IA; categoría {@code AMBIGUA} con confianza 0 si la llamada falla.
     */
    public ResultadoModeracion analizarContenido(String contenido, String motivoDenuncia) {
        if (contenido == null || contenido.trim().isEmpty()) {
            return new ResultadoModeracion("AMBIGUA", 0.5, "Contenido vacío");
        }

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Authorization", "Bearer " + openAiApiKey.trim());
            headers.set("HTTP-Referer", "http://localhost:8087");
            headers.set("X-Title", "Huellitas Moderacion IA");

            String systemPrompt = """
                Eres el sistema automatizado de moderación de contenido de la comunidad Huellitas Inteligentes.
                Debes evaluar si el contenido denunciado es una violación grave de normas o una denuncia infundada.

                Responde ÚNICAMENTE con un formato JSON estricto sin markdown ni texto extra:
                {"categoria":"VIOLACION_GRAVE|INFUNDADA|AMBIGUA", "confianza":0.95, "motivo":"razón muy breve"}

                Reglas de clasificación:
                1. VIOLACION_GRAVE: Amenazas, violencia, insultos graves, xenofobia, discurso de odio o contenido explícito.
                2. INFUNDADA: Texto inofensivo, saludos, dudas sobre mascotas, publicaciones amigables.
                3. AMBIGUA: Sarcasmo, opiniones divididas, discusiones menores o contexto impreciso.
                """;

            String userPrompt = String.format("Contenido a evaluar: \"%s\". Motivo denuncia: \"%s\".", contenido, motivoDenuncia);

            Map<String, Object> body = Map.of(
                "model", "gpt-3.5-turbo",
                "temperature", 0.1,
                "max_tokens", 150,
                "messages", List.of(
                    Map.of("role", "system", "content", systemPrompt),
                    Map.of("role", "user", "content", userPrompt)
                )
            );

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);
            Map<?, ?> response = restTemplate.postForObject("https://api.openai.com/v1/chat/completions", entity, Map.class);

            if (response != null && response.containsKey("choices")) {
                List<?> choices = (List<?>) response.get("choices");
                if (!choices.isEmpty()) {
                    Map<?, ?> choice = (Map<?, ?>) choices.get(0);
                    Map<?, ?> message = (Map<?, ?>) choice.get("message");
                    String rawJson = (String) message.get("content");
                    return parsearRespuestaIa(rawJson);
                }
            }
        } catch (Exception e) {
            log.error("[MODERACIÓN IA] Error llamando a OpenAI API: {}", e.getMessage());
        }

        return new ResultadoModeracion("AMBIGUA", 0.0, "Fallo en evaluación IA");
    }

    private ResultadoModeracion parsearRespuestaIa(String rawJson) {
        try {
            String json = rawJson.replaceAll("```json", "").replaceAll("```", "").trim();
            String cat = "AMBIGUA";
            double conf = 0.5;
            String mot = "Revisión requerida";

            if (json.contains("\"categoria\":\"")) {
                cat = json.split("\"categoria\":\"")[1].split("\"")[0];
            }
            if (json.contains("\"confianza\":")) {
                String confStr = json.split("\"confianza\":")[1].split("[,}]")[0].trim();
                conf = Double.parseDouble(confStr);
            }
            if (json.contains("\"motivo\":\"")) {
                mot = json.split("\"motivo\":\"")[1].split("\"")[0];
            }

            return new ResultadoModeracion(cat, conf, mot);
        } catch (Exception e) {
            log.error("[MODERACIÓN IA] Error parseando JSON de IA: {}", rawJson, e);
            return new ResultadoModeracion("AMBIGUA", 0.0, "Error formato JSON");
        }
    }

    /**
     * Evalúa un reporte de contenido con IA y aplica la resolución
     * correspondiente: strike automático al reportado si la violación es
     * clara, descarte automático si la denuncia es infundada, o lo deja
     * pendiente para revisión manual si el resultado es ambiguo.
     *
     * @param reporteId identificador del reporte a evaluar.
     * @param contenido contenido denunciado.
     * @param motivoDenuncia motivo indicado por el denunciante.
     * @param reportadoId identificador del usuario denunciado (puede ser {@code null}).
     * @param reportadorId identificador del usuario que denunció (puede ser {@code null}).
     */
    public void procesarReporteConIa(Long reporteId, String contenido, String motivoDenuncia, Long reportadoId, Long reportadorId) {
        ResultadoModeracion res = analizarContenido(contenido, motivoDenuncia);
        log.info("[MODERACIÓN IA] Reporte #{} -> Categoría: {}, Confianza: {}, Motivo: {}", reporteId, res.categoria(), res.confianza(), res.motivo());

        if (res.confianza() >= 0.90 && "VIOLACION_GRAVE".equals(res.categoria())) {
            // Auto-aplicar STRIKE y resolver
            if (reportadoId != null) {
                jdbcTemplate.update("UPDATE usuario SET strikes = COALESCE(strikes, 0) + 1 WHERE id = ?", reportadoId);
                jdbcTemplate.update(
                    "INSERT INTO notificacion (usuario_id, canal, contenido, estado, tipo, enviado_at) VALUES (?, 'WEBSOCKET'::canal_notificacion, ?, 'PENDIENTE'::estado_notificacion, 'ADVERTENCIA', NOW())",
                    reportadoId, "⚠️ Strike Automático (IA): Contenido removido por " + res.motivo()
                );
            }
            jdbcTemplate.update(
                "UPDATE reporte_moderacion SET estado = 'RESUELTO', decidido_por = 'IA', motivo_ia = ?, confianza_ia = ? WHERE id = ?",
                res.motivo(), res.confianza(), reporteId
            );
        } else if (res.confianza() >= 0.90 && "INFUNDADA".equals(res.categoria())) {
            // Auto-descartar
            if (reportadorId != null) {
                jdbcTemplate.update(
                    "INSERT INTO notificacion (usuario_id, canal, contenido, estado, tipo, enviado_at) VALUES (?, 'WEBSOCKET'::canal_notificacion, ?, 'PENDIENTE'::estado_notificacion, 'INFO', NOW())",
                    reportadorId, "ℹ️ Denuncia Descartada (IA): Tu reporte fue revisado automáticamente y no viola las normas."
                );
            }
            jdbcTemplate.update(
                "UPDATE reporte_moderacion SET estado = 'DESCARTADO', decidido_por = 'IA', motivo_ia = ?, confianza_ia = ? WHERE id = ?",
                res.motivo(), res.confianza(), reporteId
            );
        } else {
            // Caso AMBIGUO -> Queda PENDIENTE para admin humano
            jdbcTemplate.update(
                "UPDATE reporte_moderacion SET decidido_por = 'IA_AMBIGUO', motivo_ia = ?, confianza_ia = ? WHERE id = ?",
                res.motivo(), res.confianza(), reporteId
            );
        }
    }
}
