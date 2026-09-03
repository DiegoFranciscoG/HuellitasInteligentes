package com.huellitas.ia;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.List;
import java.util.Map;

/**
 * Verifica que una imagen sea realmente sobre mascotas/animales (incluye
 * memes de mascotas) antes de dejarla publicar — la comunidad es
 * exclusivamente de cuidado animal, así que cualquier imagen ajena al tema
 * (personas, objetos, capturas de pantalla sin relación, etc.) se rechaza,
 * aunque Sightengine no la marque como explícita ni ofensiva.
 *
 * Usa un modelo de visión (GPT-4o-mini vía OpenRouter, la misma clave que ya
 * existe para moderación) con una pregunta de clasificación simple. Si la
 * API no está configurada o falla, no bloquea nada (falla abierto) — igual
 * que {@link SightengineService}, para no tumbar la publicación de imágenes
 * por un problema de un proveedor externo.
 */
@Service
public class ContenidoMascotaService {

    private static final Logger log = LoggerFactory.getLogger(ContenidoMascotaService.class);
    private static final String OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

    @Value("${openrouter.api.key.moderacion:}")
    private String apiKey;

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public ContenidoMascotaService() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(4000);
        factory.setReadTimeout(8000);
        this.restTemplate = new RestTemplate(factory);
    }

    private boolean configurado() {
        return apiKey != null && apiKey.trim().startsWith("sk-or-v1");
    }

    /** Veredicto de la clasificación: si es contenido de mascotas, y por qué (para el mensaje al usuario). */
    public record VeredictoImagen(boolean esMascota, boolean disponible, String motivo) {}

    /**
     * Clasifica si una imagen (por URL pública) muestra una mascota/animal
     * o un meme sobre mascotas.
     *
     * @param urlImagen URL pública de la imagen (ya subida a S3/Backblaze).
     * @return el veredicto; {@code esMascota=true} y {@code disponible=false} si no se pudo verificar (no bloquea).
     */
    public VeredictoImagen esContenidoDeMascota(String urlImagen) {
        if (urlImagen == null || urlImagen.isBlank() || !configurado()) {
            return new VeredictoImagen(true, false, null);
        }
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Authorization", "Bearer " + apiKey.trim());
            headers.set("HTTP-Referer", "http://localhost:4200");
            headers.set("X-Title", "Huellitas Moderacion Imagenes");

            String prompt = """
                Esta es una comunidad exclusiva para el cuidado de mascotas (perros, gatos, etc.).
                Evalúa la imagen y responde ÚNICAMENTE con JSON estricto, sin markdown:
                {"es_mascota": true|false, "motivo": "razón muy breve en español"}

                Responde es_mascota=true SOLO si la imagen muestra:
                - Una o más mascotas/animales domésticos reales (perro, gato, etc.)
                - Un meme o ilustración cuyo tema central es una mascota/animal
                - Accesorios o productos para mascotas (comida, juguetes, casas) fotografiados junto a la mascota o claramente sobre el tema

                Responde es_mascota=false si la imagen muestra principalmente:
                - Una persona (selfie, retrato, cuerpo humano) sin que una mascota sea el foco
                - Paisajes, objetos, capturas de pantalla u otro contenido sin relación con mascotas
                - Cualquier cosa que no tenga que ver con el cuidado de animales
                """;

            Map<String, Object> body = Map.of(
                "model", "openai/gpt-4o-mini",
                "temperature", 0.1,
                "max_tokens", 120,
                "messages", List.of(Map.of(
                    "role", "user",
                    "content", List.of(
                        Map.of("type", "text", "text", prompt),
                        Map.of("type", "image_url", "image_url", Map.of("url", urlImagen))
                    )
                ))
            );

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);
            String respuesta = restTemplate.postForObject(OPENROUTER_URL, entity, String.class);
            return parsearRespuesta(respuesta);
        } catch (Exception e) {
            log.error("[CONTENIDO MASCOTA] Error clasificando imagen: {}", e.getMessage());
            return new VeredictoImagen(true, false, null);
        }
    }

    private VeredictoImagen parsearRespuesta(String json) {
        try {
            JsonNode root = objectMapper.readTree(json);
            String contenido = root.path("choices").get(0).path("message").path("content").asText("");
            String limpio = contenido.replaceAll("```json", "").replaceAll("```", "").trim();
            JsonNode clasificacion = objectMapper.readTree(limpio);
            boolean esMascota = clasificacion.path("es_mascota").asBoolean(true);
            String motivo = clasificacion.path("motivo").asText("");
            return new VeredictoImagen(esMascota, true, motivo);
        } catch (Exception e) {
            log.error("[CONTENIDO MASCOTA] Error parseando respuesta: {}", json, e);
            return new VeredictoImagen(true, false, null);
        }
    }

    /**
     * Veredicto de actividad para "Momentos de tu mascota": si hay una
     * mascota en el cuadro, qué parece estar haciendo, y con cuánta certeza.
     * {@code hayMascota=false} cuando no se detectó nada o el clasificador no
     * está disponible — en ese caso no debe generarse ningún aviso.
     */
    public record VeredictoActividad(boolean hayMascota, String actividad, double confianza) {}

    private static final java.util.Set<String> ACTIVIDADES_VALIDAS =
        java.util.Set.of("COMIENDO", "BEBIENDO", "DURMIENDO", "JUGANDO", "NINGUNA_CLARA");

    /**
     * Clasifica un fotograma capturado directamente de una cámara IoT
     * (ESP32-CAM vía {@code /capture}) para decidir si hay una mascota y qué
     * está haciendo. A diferencia de {@link #esContenidoDeMascota(String)},
     * recibe los bytes crudos en vez de una URL pública: el fotograma nunca
     * se sube a almacenamiento salvo que la actividad detectada valga la pena
     * guardar, así que no puede depender de tener ya una URL.
     *
     * @param imagenJpeg bytes del JPEG obtenido de la cámara.
     * @return el veredicto; {@code hayMascota=false} si no se pudo clasificar (no genera aviso).
     */
    public VeredictoActividad clasificarActividad(byte[] imagenJpeg) {
        if (imagenJpeg == null || imagenJpeg.length == 0 || !configurado()) {
            return new VeredictoActividad(false, "NINGUNA_CLARA", 0.0);
        }
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Authorization", "Bearer " + apiKey.trim());
            headers.set("HTTP-Referer", "http://localhost:4200");
            headers.set("X-Title", "Huellitas Momentos Mascota");

            String dataUrl = "data:image/jpeg;base64," + java.util.Base64.getEncoder().encodeToString(imagenJpeg);

            String prompt = """
                Esta imagen viene de una cámara de vigilancia doméstica para mascotas (perros).
                Evalúa la imagen y responde ÚNICAMENTE con JSON estricto, sin markdown:
                {"hay_mascota": true|false, "actividad": "COMIENDO"|"BEBIENDO"|"DURMIENDO"|"JUGANDO"|"NINGUNA_CLARA", "confianza": 0.0-1.0}

                hay_mascota=true solo si se ve un perro real en la imagen.
                actividad describe qué está haciendo:
                - COMIENDO: tiene el hocico en un plato o comedero de comida
                - BEBIENDO: tiene el hocico en agua o un bebedero
                - DURMIENDO: está echado, quieto, con los ojos cerrados o en reposo claro
                - JUGANDO: en movimiento activo, con un juguete, corriendo o saltando
                - NINGUNA_CLARA: hay perro pero no se puede distinguir bien la actividad
                confianza es tu certeza real sobre la actividad elegida (no la definas siempre en 1.0).
                Si no hay ningún perro, hay_mascota=false y actividad="NINGUNA_CLARA".
                """;

            Map<String, Object> body = Map.of(
                "model", "openai/gpt-4o-mini",
                "temperature", 0.1,
                "max_tokens", 150,
                "messages", List.of(Map.of(
                    "role", "user",
                    "content", List.of(
                        Map.of("type", "text", "text", prompt),
                        Map.of("type", "image_url", "image_url", Map.of("url", dataUrl))
                    )
                ))
            );

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);
            String respuesta = restTemplate.postForObject(OPENROUTER_URL, entity, String.class);
            return parsearVeredictoActividad(respuesta);
        } catch (Exception e) {
            log.error("[MOMENTOS MASCOTA] Error clasificando actividad: {}", e.getMessage());
            return new VeredictoActividad(false, "NINGUNA_CLARA", 0.0);
        }
    }

    private VeredictoActividad parsearVeredictoActividad(String json) {
        try {
            JsonNode root = objectMapper.readTree(json);
            String contenido = root.path("choices").get(0).path("message").path("content").asText("");
            String limpio = contenido.replaceAll("```json", "").replaceAll("```", "").trim();
            JsonNode clasificacion = objectMapper.readTree(limpio);
            boolean hayMascota = clasificacion.path("hay_mascota").asBoolean(false);
            String actividad = clasificacion.path("actividad").asText("NINGUNA_CLARA").toUpperCase();
            if (!ACTIVIDADES_VALIDAS.contains(actividad)) actividad = "NINGUNA_CLARA";
            double confianza = clasificacion.path("confianza").asDouble(0.0);
            return new VeredictoActividad(hayMascota, actividad, Math.max(0.0, Math.min(1.0, confianza)));
        } catch (Exception e) {
            log.error("[MOMENTOS MASCOTA] Error parseando respuesta: {}", json, e);
            return new VeredictoActividad(false, "NINGUNA_CLARA", 0.0);
        }
    }

    /**
     * Veredicto para la foto de perfil de una mascota: a diferencia de
     * {@link #esContenidoDeMascota(String)} (que también acepta memes o
     * ilustraciones para la comunidad), aquí se exige una FOTO real de un
     * perro real — esta imagen es la que después usa el reconocimiento de
     * mascota de "Momentos", así que un meme, un dibujo o la foto de una
     * persona no sirven aunque el tema sea "sobre mascotas".
     * {@code disponible=false} cuando el clasificador no está configurado o
     * falló — en ese caso no debe bloquear la subida (falla abierto).
     */
    public record VeredictoFotoPerro(boolean esFotoDePerro, boolean disponible, String motivo) {}

    /**
     * Valida que una foto recién subida sea realmente la foto de un perro
     * real, antes de guardarla como {@code perro.foto_url}.
     *
     * @param imagenBytes bytes de la imagen tal como la subió el usuario.
     * @return el veredicto; {@code disponible=false} si no se pudo verificar (no bloquea la subida).
     */
    public VeredictoFotoPerro esFotoRealDePerro(byte[] imagenBytes) {
        if (imagenBytes == null || imagenBytes.length == 0 || !configurado()) {
            return new VeredictoFotoPerro(true, false, null);
        }
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Authorization", "Bearer " + apiKey.trim());
            headers.set("HTTP-Referer", "http://localhost:4200");
            headers.set("X-Title", "Huellitas Foto de Mascota");

            String dataUrl = "data:image/jpeg;base64," + java.util.Base64.getEncoder().encodeToString(imagenBytes);

            String prompt = """
                Esta imagen se va a usar como foto de perfil de una mascota, y más adelante para
                reconocerla en video, así que tiene que ser una FOTOGRAFÍA REAL de un perro real.
                Responde ÚNICAMENTE con JSON estricto, sin markdown:
                {"es_foto_de_perro": true|false, "motivo": "razón muy breve en español"}

                es_foto_de_perro=true SOLO si la imagen es una fotografía real (no un dibujo, no un
                meme, no una ilustración, no una captura de pantalla) donde el sujeto principal es
                un perro real.

                es_foto_de_perro=false si es una persona, un meme, una ilustración/dibujo, un objeto,
                un paisaje, otro animal que no sea perro, o cualquier imagen que no sea una foto real
                de un perro real.
                """;

            Map<String, Object> body = Map.of(
                "model", "openai/gpt-4o-mini",
                "temperature", 0.1,
                "max_tokens", 100,
                "messages", List.of(Map.of(
                    "role", "user",
                    "content", List.of(
                        Map.of("type", "text", "text", prompt),
                        Map.of("type", "image_url", "image_url", Map.of("url", dataUrl))
                    )
                ))
            );

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);
            String respuesta = restTemplate.postForObject(OPENROUTER_URL, entity, String.class);
            return parsearVeredictoFotoPerro(respuesta);
        } catch (Exception e) {
            log.error("[FOTO MASCOTA] Error validando foto de perro: {}", e.getMessage());
            return new VeredictoFotoPerro(true, false, null);
        }
    }

    private VeredictoFotoPerro parsearVeredictoFotoPerro(String json) {
        try {
            JsonNode root = objectMapper.readTree(json);
            String contenido = root.path("choices").get(0).path("message").path("content").asText("");
            String limpio = contenido.replaceAll("```json", "").replaceAll("```", "").trim();
            JsonNode clasificacion = objectMapper.readTree(limpio);
            boolean esFoto = clasificacion.path("es_foto_de_perro").asBoolean(true);
            String motivo = clasificacion.path("motivo").asText("");
            return new VeredictoFotoPerro(esFoto, true, motivo);
        } catch (Exception e) {
            log.error("[FOTO MASCOTA] Error parseando respuesta: {}", json, e);
            return new VeredictoFotoPerro(true, false, null);
        }
    }
}
