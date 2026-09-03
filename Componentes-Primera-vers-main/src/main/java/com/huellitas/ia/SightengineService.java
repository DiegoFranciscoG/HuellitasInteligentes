package com.huellitas.ia;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.util.UriComponentsBuilder;

import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Cliente genérico para la API de moderación de Sightengine
 * (https://sightengine.com). No depende de ninguna entidad del dominio:
 * solo sabe hablar con Sightengine y devolver puntajes 0.0–1.0 por
 * categoría — quien lo use decide qué hacer con esos números.
 *
 * Si faltan las credenciales (`sightengine.api.user`/`sightengine.api.secret`)
 * o la llamada falla, los métodos devuelven un resultado vacío
 * (disponible=false, score 0) en vez de lanzar una excepción, para no
 * tumbar el flujo de publicación por un problema de la API externa.
 */
@Service
public class SightengineService {

    private static final Logger log = LoggerFactory.getLogger(SightengineService.class);

    private static final String TEXT_ENDPOINT = "https://api.sightengine.com/1.0/text/check.json";
    private static final String IMAGE_ENDPOINT = "https://api.sightengine.com/1.0/check.json";

    @Value("${sightengine.api.user:}")
    private String apiUser;

    @Value("${sightengine.api.secret:}")
    private String apiSecret;

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public SightengineService() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(4000);
        factory.setReadTimeout(8000);
        this.restTemplate = new RestTemplate(factory);
    }

    private boolean configurado() {
        return apiUser != null && !apiUser.isBlank() && apiSecret != null && !apiSecret.isBlank();
    }

    /** Recorta espacios accidentales (típicos de pegar la clave con un espacio de más en el .properties/.env). */
    private String apiUserLimpio() { return apiUser == null ? null : apiUser.trim(); }
    private String apiSecretLimpio() { return apiSecret == null ? null : apiSecret.trim(); }

    /**
     * Puntajes 0.0–1.0 por categoría detectada (para texto: "sexual",
     * "discriminatory", "insulting", "violent", "toxic", "self-harm"; para
     * imagen: "nudity", "offensive", "gore", "violence"), más utilidades
     * para comparar contra un único umbral.
     */
    public static class ResultadoSightengine {
        private final Map<String, Double> scores;
        private final boolean disponible;

        public ResultadoSightengine(Map<String, Double> scores, boolean disponible) {
            this.scores = scores;
            this.disponible = disponible;
        }

        public Map<String, Double> getScores() { return scores; }
        public boolean isDisponible() { return disponible; }

        /** El puntaje más alto entre todas las categorías (0 si no hay ninguna). */
        public double maxScore() {
            return scores.values().stream().mapToDouble(Double::doubleValue).max().orElse(0.0);
        }

        /** La categoría con el puntaje más alto, o null si no hay ninguna. */
        public String categoriaMasAlta() {
            return scores.entrySet().stream()
                .max(Map.Entry.comparingByValue())
                .map(Map.Entry::getKey)
                .orElse(null);
        }
    }

    /**
     * Evalúa un texto con el modelo ML de Sightengine (sexual, racismo/
     * discriminación, insultos, violencia, toxicidad, autolesión).
     *
     * @param texto contenido a evaluar; si es nulo/vacío no llama a la API.
     */
    public ResultadoSightengine validarTexto(String texto) {
        if (texto == null || texto.isBlank() || !configurado()) {
            return new ResultadoSightengine(Map.of(), false);
        }
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.MULTIPART_FORM_DATA);
            MultiValueMap<String, Object> form = new LinkedMultiValueMap<>();
            form.add("text", texto);
            form.add("lang", "es");
            form.add("mode", "ml");
            // "self-harm" no soporta el idioma español (Sightengine responde 400 y
            // aborta toda la petición si se combina con lang=es) — solo "general"
            // (sexual/discriminatory/insulting/violent/toxic) funciona en español.
            form.add("models", "general");
            form.add("api_user", apiUserLimpio());
            form.add("api_secret", apiSecretLimpio());

            HttpEntity<MultiValueMap<String, Object>> entity = new HttpEntity<>(form, headers);
            String respuesta = restTemplate.postForObject(TEXT_ENDPOINT, entity, String.class);
            return parsearScoresTexto(respuesta);
        } catch (Exception e) {
            log.error("[SIGHTENGINE] Error validando texto: {}", e.getMessage());
            return new ResultadoSightengine(Map.of(), false);
        }
    }

    /** Modelos pedidos a Sightengine para cada imagen: contenido explícito/violento + detección de rostros humanos. */
    private static final String IMAGE_MODELS = "nudity-2.1,offensive,gore,violence,face-attributes";

    /** Evalúa una imagen subida (desnudez, contenido ofensivo, gore, violencia, rostros humanos). */
    public ResultadoSightengine validarImagen(MultipartFile imagen) {
        if (imagen == null || imagen.isEmpty() || !configurado()) {
            return new ResultadoSightengine(Map.of(), false);
        }
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.MULTIPART_FORM_DATA);
            MultiValueMap<String, Object> form = new LinkedMultiValueMap<>();
            form.add("media", new ByteArrayResource(imagen.getBytes()) {
                @Override
                public String getFilename() {
                    return imagen.getOriginalFilename() != null ? imagen.getOriginalFilename() : "imagen.jpg";
                }
            });
            form.add("models", IMAGE_MODELS);
            form.add("api_user", apiUserLimpio());
            form.add("api_secret", apiSecretLimpio());

            HttpEntity<MultiValueMap<String, Object>> entity = new HttpEntity<>(form, headers);
            String respuesta = restTemplate.postForObject(IMAGE_ENDPOINT, entity, String.class);
            return parsearScoresImagen(respuesta);
        } catch (Exception e) {
            log.error("[SIGHTENGINE] Error validando imagen: {}", e.getMessage());
            return new ResultadoSightengine(Map.of(), false);
        }
    }

    /**
     * Igual que {@link #validarImagen}, pero para una imagen que ya está en
     * una URL pública (por ejemplo, ya subida a S3/Backblaze) — útil cuando
     * en el flujo la imagen ya no está disponible como {@code MultipartFile}
     * en el punto donde se modera.
     */
    public ResultadoSightengine validarImagenPorUrl(String urlImagen) {
        if (urlImagen == null || urlImagen.isBlank() || !configurado()) {
            return new ResultadoSightengine(Map.of(), false);
        }
        try {
            String uri = UriComponentsBuilder.fromHttpUrl(IMAGE_ENDPOINT)
                .queryParam("models", IMAGE_MODELS)
                .queryParam("api_user", apiUserLimpio())
                .queryParam("api_secret", apiSecretLimpio())
                .queryParam("url", urlImagen)
                .toUriString();
            String respuesta = restTemplate.getForObject(uri, String.class);
            return parsearScoresImagen(respuesta);
        } catch (Exception e) {
            log.error("[SIGHTENGINE] Error validando imagen por URL: {}", e.getMessage());
            return new ResultadoSightengine(Map.of(), false);
        }
    }

    /** Estructura real de Sightengine: {@code moderation_classes.<categoria>} = score 0–1. */
    private ResultadoSightengine parsearScoresTexto(String json) {
        try {
            JsonNode clases = objectMapper.readTree(json).path("moderation_classes");
            Map<String, Double> scores = new LinkedHashMap<>();
            Iterator<String> nombres = clases.fieldNames();
            while (nombres.hasNext()) {
                String nombre = nombres.next();
                if ("available".equals(nombre)) continue; // lista de categorías soportadas, no un score
                JsonNode valor = clases.get(nombre);
                if (valor.isNumber()) scores.put(nombre, valor.asDouble());
            }
            return new ResultadoSightengine(scores, true);
        } catch (Exception e) {
            log.error("[SIGHTENGINE] Error parseando respuesta de texto: {}", json, e);
            return new ResultadoSightengine(Map.of(), false);
        }
    }

    /**
     * nudity-2.1 no trae un único campo "raw": tomamos el máximo entre
     * sexual_activity/sexual_display/erotica como puntaje de desnudez.
     * offensive/gore/violence sí traen un campo "prob" directo.
     */
    private ResultadoSightengine parsearScoresImagen(String json) {
        try {
            JsonNode root = objectMapper.readTree(json);
            Map<String, Double> scores = new LinkedHashMap<>();

            JsonNode nudity = root.path("nudity");
            if (nudity.has("sexual_activity")) {
                double nudez = Math.max(nudity.path("sexual_activity").asDouble(0),
                               Math.max(nudity.path("sexual_display").asDouble(0),
                                        nudity.path("erotica").asDouble(0)));
                scores.put("nudity", nudez);
            }
            if (root.path("offensive").has("prob")) scores.put("offensive", root.path("offensive").path("prob").asDouble());
            if (root.path("gore").has("prob")) scores.put("gore", root.path("gore").path("prob").asDouble());
            if (root.path("violence").has("prob")) scores.put("violence", root.path("violence").path("prob").asDouble());

            // face-attributes: no da un puntaje de confianza por sí solo, solo
            // la lista de rostros detectados — si hay al menos uno, tratamos
            // la imagen como "contiene una persona" con puntaje máximo, para
            // la regla de "nada de fotos de personas" de la comunidad.
            JsonNode faces = root.path("faces");
            if (faces.isArray() && faces.size() > 0) {
                scores.put("rostro_humano", 1.0);
            }

            return new ResultadoSightengine(scores, true);
        } catch (Exception e) {
            log.error("[SIGHTENGINE] Error parseando respuesta de imagen: {}", json, e);
            return new ResultadoSightengine(Map.of(), false);
        }
    }
}
