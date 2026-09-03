package com.huellitas.ia;

import org.springframework.http.ResponseEntity;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.web.bind.annotation.*;

/**
 * Controller para el chatbot IA + ingesta RAG.
 * Actualiza el GeminiProxyController para usar RAG real.
 */
@RestController
@RequestMapping("/api/huellitas/ia")
public class IaController {

    private final RagService ragService;
    private final GeminiProxyController geminiProxy;
    private final PlacesService placesService;

    public IaController(RagService ragService, GeminiProxyController geminiProxy, PlacesService placesService) {
        this.ragService = ragService;
        this.geminiProxy = geminiProxy;
        this.placesService = placesService;
    }

    /**
     * Chatbot de nutrición con RAG:
     * 1. Genera embedding de la pregunta
     * 2. Busca fragmentos similares en Postgres
     * 3. Llama a Gemini con el contexto recuperado
     */
    @PostMapping("/nutricion")
    public ResponseEntity<?> preguntarNutricion(@RequestBody GeminiProxyController.PreguntaRequest req) {
        // Recuperar contexto RAG real
        String contextoRag = ragService.buscarContexto(req.pregunta());

        // Construir request enriquecido con contexto
        var reqConContexto = new GeminiProxyController.PreguntaRequest(
            req.pregunta(),
            req.raza(),
            req.edad(),
            req.peso(),
            contextoRag.isBlank() ? null : contextoRag
        );

        return geminiProxy.preguntar(reqConContexto);
    }

    /**
     * Endpoint de ingesta — solo llamar una vez (o cuando se agreguen PDFs nuevos).
     * Proteger con autenticación en producción.
     */
    @PostMapping("/admin/ingestar-rag")
    public ResponseEntity<String> ingestarRag() {
        String resultado = ragService.ingestarTodo();
        return ResponseEntity.ok(resultado);
    }

    /**
     * Dato curioso cada hora — llama a Gemini con datos del perro.
     * En producción, esto genera una notificación en la tabla notificacion.
     * Disabled en dev — activa cambiando fixedDelay.
     */
    @Scheduled(fixedDelay = 3600000) // cada 1 hora
    public void generarDatosCuriosos() {
        // TODO Fase 6: por cada usuario con perros registrados,
        // llamar a /ia/dato-curioso e insertar en tabla notificacion
        // Por ahora solo log para confirmación
        System.out.println("[IA] Tick de datos curiosos — pendiente Fase 6 notificaciones");
    }

    /**
     * Busca negocios cercanos a una ubicación (tiendas de mascotas,
     * veterinarias, etc.) usando la API de Google Places.
     *
     * @param lat latitud de referencia.
     * @param lng longitud de referencia.
     * @param tipo tipo de negocio a buscar (por defecto {@code pet_store}).
     * @return un JSON (como texto) con los negocios encontrados.
     */
    @GetMapping("/negocios-cercanos")
    public ResponseEntity<?> negociosCercanos(
        @RequestParam double lat,
        @RequestParam double lng,
        @RequestParam(defaultValue = "pet_store") String tipo) {
        return ResponseEntity.ok(placesService.buscarNegociosCercanos(lat, lng, tipo));
    }
}