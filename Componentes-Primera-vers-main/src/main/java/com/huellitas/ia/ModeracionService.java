package com.huellitas.ia;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Servicio de moderación preventiva de contenido (antes de publicarse) vía
 * OpenAI. Actualmente deshabilitado por falta de créditos de la cuenta de
 * OpenAI: {@link #moderarContenido} siempre aprueba el contenido sin
 * llamar a la IA; la moderación efectiva del sistema ocurre después de la
 * publicación, a través de las denuncias y {@link ModeracionIaService}.
 */
@Service
public class ModeracionService {

    @Value("${openai.api.key.moderacion:}")
    private String openAiApiKey;

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper = new ObjectMapper();

    // Usamos gpt-3.5-turbo porque es más estable para cuentas sin fondos
    private static final String MODEL_NAME = "gpt-3.5-turbo";

    private static final String SYSTEM_PROMPT = """
        Eres un estricto moderador de contenido automatizado para la comunidad "Huellitas Inteligentes" (una app sobre perros).
        Tu tarea es analizar el texto (y la imagen si se provee) y determinar si viola las normas de la comunidad.
        
        BLOQUEA contenido si contiene:
        1. Lenguaje altamente ofensivo, insultos graves o discursos de odio.
        2. Violencia explícita, maltrato animal (texto o imagen).
        3. Contenido sexual explícito (NSFW).
        4. Spam evidente o enlaces maliciosos.
        
        PERMITE contenido:
        - Si es lenguaje coloquial inofensivo.
        - Si trata sobre problemas de salud de perros de forma médica (no morbosa).
        
        RESPONDE ÚNICAMENTE CON UN JSON VÁLIDO en el siguiente formato:
        {
          "bloquear": true o false,
          "motivo": "Explicación breve de por qué se bloquea o por qué está limpio",
          "gravedad": "ALTA, MEDIA, BAJA o NINGUNA"
        }
        """;

    public ModeracionService() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(3000);
        factory.setReadTimeout(5000); // 5 segundos max para responder
        this.restTemplate = new RestTemplate(factory);
    }

    private String getOpenAiKey() {
        if (openAiApiKey != null && openAiApiKey.trim().startsWith("sk-")) {
            return openAiApiKey.trim();
        }
        throw new IllegalStateException("Falta la variable de entorno OPENAI_API_KEY_MODERACION");
    }

    /** Veredicto de moderación: si el contenido debe bloquearse, por qué, y con qué gravedad. */
    public record ModeracionResult(boolean bloquear, String motivo, String gravedad) {}

    /**
     * Evalúa si un contenido (texto y opcionalmente una imagen) debe
     * bloquearse antes de publicarse. Actualmente siempre aprueba el
     * contenido: la validación real con IA está deshabilitada.
     *
     * @param texto contenido de texto a evaluar.
     * @param imageUrl URL de la imagen asociada, si la hay (sin uso mientras la validación está deshabilitada).
     * @return el veredicto de moderación; siempre {@code bloquear = false} en el estado actual.
     */
    public ModeracionResult moderarContenido(String texto, String imageUrl) {
        // Validación de OpenAI desactivada por falta de créditos (Solicitud del usuario)
        return new ModeracionResult(false, "Moderación automática deshabilitada", "NINGUNA");
    }
}
