package com.huellitas.ia;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

import java.util.List;
import java.util.Map;

/**
 * Proxy de Asistente IA respaldado por OpenRouter API con timeout y fallback científico.
 */
@RestController
@RequestMapping("/api/huellitas/ia")
public class GeminiProxyController {

    @Value("${openrouter.api.key.ia:}")
    private String openRouterApiKey;

    private final RestTemplate restTemplate;

    public GeminiProxyController() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(4000);
        factory.setReadTimeout(6000);
        this.restTemplate = new RestTemplate(factory);
    }

    /** Pregunta del dueño sobre su mascota, con los datos de contexto necesarios para una respuesta personalizada. */
    public record PreguntaRequest(
        String pregunta,
        String raza,
        String edad,
        Double peso,
        String contextoRag
    ) {}

    /** Respuesta del asistente IA, indicando si se usó contexto documental (RAG) para elaborarla. */
    public record GeminiResponse(String respuesta, boolean usaContexto) {}

    private static final String SYSTEM_PROMPT = """
        Eres un nutricionista veterinario experto y asesor de salud canina para Huellitas Inteligentes.
        
        INSTRUCCIONES DE RESPUESTA:
        1. SÉ CONCISO Y DIRECTO AL PUNTO. Si el usuario pregunta por una ubicación (dónde comprar, clínicas), NO des consejos nutricionales generales; limítate a dar las opciones y los mapas. NUNCA generes ensayos extensos innecesarios.
        2. ENLACES A GOOGLE MAPS:
           Si preguntan dónde comprar o conseguir productos/servicios, incluye estos enlaces exactos sin modificar su formato:
           - [Petshops y Veterinarias Cercanas](https://www.google.com/maps/search/veterinaria+24+horas)
           - [Tiendas de Mascotas y Supermercados](https://www.google.com/maps/search/tienda+de+mascotas)
        3. Si la pregunta es sobre nutrición o alimentos tóxicos, cita fuentes científicas reales:
           - [ASPCA](https://www.aspca.org/pet-care/animal-poison-control)
           - [MSD Veterinary Manual](https://www.msdvetmanual.com)
           - [WSAVA](https://wsava.org)
        4. Usa formato Markdown limpio con negritas (**concepto**), viñetas (-) y tablas simples. No uses emojis excesivos dentro de los enlaces.
        5. Recuerda amablemente consultar al veterinario de confianza cuando sea una consulta médica.
        """;

    /** La clave viene de OPENROUTER_API_KEY_IA; ya no hay copia en el codigo. */
    private String getOpenRouterKey() {
        if (openRouterApiKey != null && openRouterApiKey.trim().startsWith("sk-or-v1")) {
            return openRouterApiKey.trim();
        }
        throw new IllegalStateException("Falta la variable de entorno OPENROUTER_API_KEY_IA");
    }

    /**
     * Responde una pregunta del usuario sobre el cuidado de su mascota,
     * enviándola junto con el contexto documental disponible a OpenRouter
     * (modelo GPT-4o-mini). Si la llamada falla o no hay clave configurada,
     * entrega una respuesta veterinaria genérica preescrita como respaldo.
     *
     * @param req pregunta del usuario y datos de la mascota (raza, edad, peso) y contexto documental opcional.
     * @return la respuesta generada (o de respaldo) y si se usó contexto documental.
     */
    @PostMapping("/preguntar")
    public ResponseEntity<?> preguntar(@RequestBody PreguntaRequest req) {
        String contexto = req.contextoRag() != null ? req.contextoRag() : "Sin contexto específico disponible.";
        boolean hayContexto = req.contextoRag() != null && !req.contextoRag().isBlank();

        String prompt = String.format("""
            DATOS DEL PACIENTE (PERRO):
            Raza / Tipo: %s
            Edad: %s
            Peso: %s kg
            
            CONTEXTO EXTRAÍDO DE BASE DE DATOS / PDFS:
            %s
            
            PREGUNTA DEL DUEÑO: %s
            """,
            orDefault(req.raza(), "No especificada"),
            orDefault(req.edad(), "No especificada"),
            req.peso() != null ? req.peso() : "No especificado",
            contexto,
            req.pregunta()
        );

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Authorization", "Bearer " + getOpenRouterKey());
            headers.set("HTTP-Referer", "http://localhost:4200");
            headers.set("X-Title", "Huellitas Inteligentes");

            Map<String, Object> body = Map.of(
                "model", "openai/gpt-4o-mini",
                "messages", List.of(
                    Map.of("role", "system", "content", SYSTEM_PROMPT),
                    Map.of("role", "user", "content", prompt)
                )
            );

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);
            String url = "https://openrouter.ai/api/v1/chat/completions";

            System.out.println("[OPENROUTER LOG] Conectando con OpenRouter (model: openrouter/free)...");
            @SuppressWarnings("rawtypes")
            ResponseEntity<Map> openRouterResp = restTemplate.postForEntity(url, entity, Map.class);

            if (openRouterResp.getStatusCode().is2xxSuccessful() && openRouterResp.getBody() != null) {
                try {
                    @SuppressWarnings("unchecked")
                    List<Map<String, Object>> choices = (List<Map<String, Object>>) openRouterResp.getBody().get("choices");
                    @SuppressWarnings("unchecked")
                    Map<String, Object> message = (Map<String, Object>) choices.get(0).get("message");
                    String texto = (String) message.get("content");
                    System.out.println("[OPENROUTER SUCCESS] Respuesta de OpenRouter obtenida con éxito!");
                    return ResponseEntity.ok(new GeminiResponse(texto, hayContexto));
                } catch (Exception e) {
                    System.err.println("[OPENROUTER] Error parseando respuesta: " + e.getMessage());
                }
            }
            
            return ResponseEntity.ok(new GeminiResponse(generarRespuestaFallbackVeterinaria(req.pregunta()), false));

        } catch (Exception e) {
            System.err.println("[OPENROUTER FALLBACK] Error o Timeout (" + e.getMessage() + "). Entregando respuesta veterinaria estandar...");
            return ResponseEntity.ok(new GeminiResponse(generarRespuestaFallbackVeterinaria(req.pregunta()), false));
        }
    }

    private String generarRespuestaFallbackVeterinaria(String pregunta) {
        String p = pregunta != null ? pregunta.toLowerCase() : "";
        if (p.contains("toxico") || p.contains("tóxico") || p.contains("veneno") || p.contains("malo")) {
            return """
                ⚠️ **Alimentos Tóxicos para Perros (Fuente: ASPCA / AVMA)**:
                
                - **Chocolate y Cafeína**: Contienen teobromina, tóxica para el corazón y sistema nervioso.
                - **Cebolla, Ajo y Puerro**: Provocan anemia hemolítica por destrucción de glóbulos rojos.
                - **Uvas y Pasas**: Producen insuficiencia renal aguda grave.
                - **Xilitol (Edulcorante)**: Causa hipoglucemia severa y fallo hepático.
                - **Aguacate**: Contiene persina, causante de malestar gastrointestinal.
                
                📚 *Fuentes Consultadas*:
                - [ASPCA Animal Poison Control Center](https://www.aspca.org/pet-care/animal-poison-control)
                - [AVMA - Toxic Foods for Pets](https://www.avma.org)
                """;
        } else if (p.contains("comer") || p.contains("alimento") || p.contains("ración") || p.contains("cuantas veces")) {
            return """
                🐾 **Guía de Alimentación Canina (Fuente: MSD Veterinary Manual / AAHA)**:
                
                - **Cachorros (< 6 meses)**: 3 a 4 porciones al día.
                - **Adultos (1 a 7 años)**: 2 porciones al día separadas por 8-12 horas.
                - **Agua**: Libre acceso a agua limpia constante (~50ml por kg de peso al día).
                
                📚 *Fuentes Consultadas*:
                - [MSD Veterinary Manual - Small Animal Nutrition](https://www.msdvetmanual.com)
                - [AAHA Canine Life Stage Guidelines](https://www.aaha.org)
                """;
        }
        return """
            🐾 **Recomendación Nutricional y de Salud Canina**:
            
            Para garantizar el bienestar de tu mascota, la dieta debe ser completa y equilibrada según su edad, peso y nivel de actividad.
            
            1. **Proteína de Alta Calidad**: Pollo, pavo, res o cordero como ingrediente principal.
            2. **Fibras y Carbohidratos Digestibles**: Arroz integral, avena o camote cocido.
            3. **Grasas Saludables**: Ácidos grasos Omega-3 y Omega-6 para piel y pelaje.
            
            📚 *Fuentes Científicas*:
            - [WSAVA Global Nutrition Guidelines](https://wsava.org/global-guidelines/global-nutrition-guidelines/)
            - [AVMA Pet Health Care](https://www.avma.org/resources-tools/pet-owners)
            
            ⚠️ *Consulta a tu médico veterinario antes de realizar cambios drásticos en la dieta.*
            """;
    }

    /**
     * Genera un dato curioso breve y amigable sobre la raza y edad de una mascota.
     *
     * @param req datos de la mascota: {@code nombre}, {@code raza} y {@code edad}.
     * @return el dato curioso generado, o un error 502 si la IA no responde.
     */
    @PostMapping("/dato-curioso")
    public ResponseEntity<?> datoCurioso(@RequestBody Map<String, Object> req) {
        String nombre = (String) req.getOrDefault("nombre", "tu perro");
        String raza   = (String) req.getOrDefault("raza", "mestizo");
        String edad   = (String) req.getOrDefault("edad", "desconocida");

        String prompt = String.format(
            "Genera un dato curioso, breve (máximo 2 oraciones) y amigable sobre perros de raza %s con %s de edad. " +
            "El perro se llama %s. Usa un tono cálido y positivo.",
            raza, edad, nombre
        );

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Authorization", "Bearer " + getOpenRouterKey());
            headers.set("HTTP-Referer", "http://localhost:4200");
            headers.set("X-Title", "Huellitas Inteligentes");

            Map<String, Object> body = Map.of("model", "openai/gpt-4o-mini", "messages", List.of(
                Map.of("role", "user", "content", prompt)
            ));
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);
            String url = "https://openrouter.ai/api/v1/chat/completions";
            @SuppressWarnings("rawtypes")
            ResponseEntity<Map> resp = restTemplate.postForEntity(url, entity, Map.class);
            if (resp.getStatusCode().is2xxSuccessful() && resp.getBody() != null) {
                @SuppressWarnings("unchecked")
                List<Map<String, Object>> choices = (List<Map<String, Object>>) resp.getBody().get("choices");
                @SuppressWarnings("unchecked")
                Map<String, Object> message = (Map<String, Object>) choices.get(0).get("message");
                return ResponseEntity.ok(Map.of("dato", message.get("content")));
            }
            return ResponseEntity.status(502).body(Map.of("error", "Sin respuesta de IA"));
        } catch (Exception e) {
            return ResponseEntity.status(502).body(Map.of("error", e.getMessage()));
        }
    }

    private String orDefault(String val, String def) {
        return (val == null || val.isBlank()) ? def : val;
    }
}
