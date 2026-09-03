package com.huellitas.ia;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.apache.pdfbox.Loader;
import org.jsoup.Jsoup;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Servicio RAG: ingesta PDFs y URLs, genera embeddings con Gemini,
 * y los guarda en Postgres (pgvector) para búsqueda semántica.
 */
@Service
public class RagService {

    @Value("${gemini.api.key:}")
    private String geminiApiKey;

    private static final String EMBEDDING_URL =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent";

    private static final String PDF_DIR = "C:/Users/diego/Desktop/Huellitas-Inteligentes/IA_PDFS";

    private static final List<String> URLS_NUTRICION = List.of(
        "https://patitasco.com/blog/perros/alimentacion-canina.html",
        "https://www.jardiland.com/es/consejos-ideas/la-nutricion-canina",
        "https://www.almonature.com/es/consiglio-nutrizionale-cane",
        "https://postgradoveterinaria.com/comida-natural-para-perros/",
        "https://www.medivetgroup.com/es-es/cuidado-de-mascotas/consejos-sobre-mascotas/guia-de-nutricion-para-perros/"
    );

    private final JdbcTemplate jdbc;
    private final RestTemplate restTemplate = new RestTemplate();

    public RagService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    // ── Ingesta Manual (llamar desde el endpoint de admin) ────────────────

    /** La clave viene de GEMINI_API_KEY; ya no hay copia en el codigo. */
    private String getApiKey() {
        if (geminiApiKey != null && geminiApiKey.trim().startsWith("AIzaSy")) {
            return geminiApiKey.trim();
        }
        throw new IllegalStateException("Falta la variable de entorno GEMINI_API_KEY");
    }

    /**
     * Ingesta todas las fuentes de conocimiento configuradas (PDFs locales y
     * URLs de nutrición canina): extrae su texto, lo trocea en fragmentos, genera un
     * embedding por fragmento con Gemini y los guarda en la base de datos para búsqueda semántica.
     *
     * @return un mensaje con el total de fragmentos insertados, o un mensaje de error si falta la clave de Gemini.
     */
    public String ingestarTodo() {
        String key = getApiKey();
        if (key == null || key.isBlank()) {
            return "ERROR: GEMINI_API_KEY no configurada";
        }
        int total = 0;
        total += ingestarPdfs();
        total += ingestarUrls();
        return "Ingesta completa: " + total + " fragmentos insertados";
    }

    private int ingestarPdfs() {
        int count = 0;
        File dir = new File(PDF_DIR);
        if (!dir.exists()) return 0;
        for (File pdf : dir.listFiles((d, n) -> n.endsWith(".pdf"))) {
            try {
                PDDocument doc = Loader.loadPDF(pdf);
                PDFTextStripper stripper = new PDFTextStripper();
                String texto = stripper.getText(doc);
                doc.close();
                List<String> fragmentos = trocear(texto, 800, 100);
                for (String frag : fragmentos) {
                    float[] embedding = generarEmbedding(frag);
                    if (embedding != null) {
                        insertarFragmento(pdf.getName(), frag, embedding);
                        count++;
                    }
                    try { Thread.sleep(800); } catch (InterruptedException ignored) {}
                }
            } catch (Exception e) {
                System.err.println("[RAG] Error procesando PDF " + pdf.getName() + ": " + e.getMessage());
            }
        }
        return count;
    }

    private int ingestarUrls() {
        int count = 0;
        for (String url : URLS_NUTRICION) {
            try {
                String texto = Jsoup.connect(url)
                    .timeout(10000)
                    .userAgent("Mozilla/5.0")
                    .get()
                    .select("article, main, .content, p")
                    .text();
                if (texto.length() < 200) continue;
                List<String> fragmentos = trocear(texto, 800, 100);
                for (String frag : fragmentos) {
                    float[] embedding = generarEmbedding(frag);
                    if (embedding != null) {
                        insertarFragmento(url, frag, embedding);
                        count++;
                    }
                    try { Thread.sleep(800); } catch (InterruptedException ignored) {}
                }
            } catch (Exception e) {
                System.err.println("[RAG] Error scraping " + url + ": " + e.getMessage());
            }
        }
        return count;
    }

    // ── Ingesta real desde el panel de admin (un archivo/URL a la vez) ─────

    /**
     * Extrae, trocea, genera embeddings e inserta en la base de conocimiento
     * el texto de un PDF recién subido desde el panel de admin — a
     * diferencia de {@link #ingestarPdfs()}, no depende de una carpeta fija
     * en disco: recibe los bytes del archivo tal como llegaron en la
     * petición HTTP.
     *
     * @param nombreArchivo nombre original del archivo (se usa como "fuente" de cada fragmento).
     * @param bytesPdf contenido del PDF.
     * @return la cantidad real de fragmentos insertados.
     * @throws IllegalStateException si falta la clave de Gemini.
     */
    public int ingestarPdfBytes(String nombreArchivo, byte[] bytesPdf) {
        getApiKey(); // valida temprano que haya clave, para fallar rápido con un mensaje claro
        borrarFragmentosDeFuente(nombreArchivo); // evita duplicados si se vuelve a subir el mismo archivo
        int count = 0;
        try (PDDocument doc = Loader.loadPDF(bytesPdf)) {
            PDFTextStripper stripper = new PDFTextStripper();
            String texto = stripper.getText(doc);
            List<String> fragmentos = trocear(texto, 800, 100);
            for (String frag : fragmentos) {
                float[] embedding = generarEmbedding(frag);
                if (embedding != null) {
                    insertarFragmento(nombreArchivo, frag, embedding);
                    count++;
                }
                try { Thread.sleep(800); } catch (InterruptedException ignored) {}
            }
        } catch (Exception e) {
            System.err.println("[RAG] Error procesando PDF subido " + nombreArchivo + ": " + e.getMessage());
        }
        return count;
    }

    /**
     * Scrapea, trocea, genera embeddings e inserta en la base de
     * conocimiento el texto de una URL recién agregada como fuente
     * confiable desde el panel de admin — a diferencia de
     * {@link #ingestarUrls()}, no depende de una lista fija en el código.
     *
     * @param url URL de la fuente confiable.
     * @return la cantidad real de fragmentos insertados.
     */
    public int ingestarUrl(String url) {
        getApiKey();
        borrarFragmentosDeFuente(url);
        int count = 0;
        try {
            String texto = Jsoup.connect(url)
                .timeout(10000)
                .userAgent("Mozilla/5.0")
                .get()
                .select("article, main, .content, p")
                .text();
            if (texto.length() < 200) {
                System.err.println("[RAG] La URL " + url + " no tiene suficiente texto extraíble (" + texto.length() + " caracteres)");
                return 0;
            }
            List<String> fragmentos = trocear(texto, 800, 100);
            for (String frag : fragmentos) {
                float[] embedding = generarEmbedding(frag);
                if (embedding != null) {
                    insertarFragmento(url, frag, embedding);
                    count++;
                }
                try { Thread.sleep(800); } catch (InterruptedException ignored) {}
            }
        } catch (Exception e) {
            System.err.println("[RAG] Error scrapeando " + url + ": " + e.getMessage());
        }
        return count;
    }

    /** Borra los fragmentos ya existentes de una fuente, para poder reprocesarla sin duplicar contenido. */
    public void borrarFragmentosDeFuente(String fuente) {
        jdbc.update("DELETE FROM rag_fragmento WHERE fuente = ?", fuente);
    }

    /** Cuenta los fragmentos reales que hay en la base de conocimiento para una fuente dada. */
    public int contarFragmentos(String fuente) {
        Integer total = jdbc.queryForObject("SELECT COUNT(*) FROM rag_fragmento WHERE fuente = ?", Integer.class, fuente);
        return total != null ? total : 0;
    }

    // ── Búsqueda semántica ────────────────────────────────────────────────

    /**
     * Busca los fragmentos de conocimiento más relevantes para una pregunta
     * del usuario, generando su embedding y comparándolo por similitud
     * vectorial contra los fragmentos ya ingeridos.
     *
     * @param pregunta pregunta del usuario.
     * @return los 4 fragmentos más relevantes concatenados, o cadena vacía si no hay resultados o falla la búsqueda.
     */
    public String buscarContexto(String pregunta) {
        try {
            float[] qEmbedding = generarEmbedding(pregunta);
            if (qEmbedding == null) return "";

            String vectorStr = toPostgresVector(qEmbedding);
            List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT contenido FROM rag_fragmento " +
                "WHERE embedding IS NOT NULL " +
                "ORDER BY embedding <=> '" + vectorStr + "'::vector LIMIT 4"
            );
            if (rows.isEmpty()) return "";

            StringBuilder sb = new StringBuilder();
            for (Map<String, Object> row : rows) {
                sb.append(row.get("contenido")).append("\n\n---\n\n");
            }
            return sb.toString().trim();
        } catch (Exception e) {
            System.err.println("[RAG] Error búsqueda semántica: " + e.getMessage());
            return "";
        }
    }

    // ── Embedding via Gemini ──────────────────────────────────────────────

    /**
     * Genera el vector de embedding de un texto usando el modelo
     * {@code gemini-embedding-001}, para indexarlo o compararlo semánticamente.
     *
     * @param texto texto a convertir en embedding.
     * @return el vector de embedding (768 dimensiones), o {@code null} si la llamada a Gemini falla.
     */
    public float[] generarEmbedding(String texto) {
        try {
            String apiKey = getApiKey();
            System.out.println("[RAG DEBUG] Generando embedding con key: " + apiKey.substring(0, 10) + "...");
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            Map<String, Object> body = Map.of(
                "model", "models/gemini-embedding-001",
                "content", Map.of("parts", List.of(Map.of("text", texto))),
                "outputDimensionality", 768
            );
            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);
            String url = EMBEDDING_URL + "?key=" + apiKey;

            ResponseEntity<Map> resp = restTemplate.postForEntity(url, entity, Map.class);
            if (resp.getStatusCode().is2xxSuccessful() && resp.getBody() != null) {
                @SuppressWarnings("unchecked")
                Map<String, Object> embeddingObj = (Map<String, Object>) resp.getBody().get("embedding");
                @SuppressWarnings("unchecked")
                List<Double> values = (List<Double>) embeddingObj.get("values");
                float[] arr = new float[values.size()];
                for (int i = 0; i < values.size(); i++) arr[i] = values.get(i).floatValue();
                return arr;
            }
        } catch (Exception e) {
            System.err.println("[RAG] Error generando embedding: " + e.getMessage());
        }
        return null;
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private void insertarFragmento(String fuente, String contenido, float[] embedding) {
        String vectorStr = toPostgresVector(embedding);
        jdbc.update(
            "INSERT INTO rag_fragmento (fuente, contenido, embedding) VALUES (?, ?, ?::vector)",
            fuente, contenido, vectorStr
        );
    }

    private String toPostgresVector(float[] arr) {
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < arr.length; i++) {
            sb.append(arr[i]);
            if (i < arr.length - 1) sb.append(",");
        }
        sb.append("]");
        return sb.toString();
    }

    /**
     * Divide texto en fragmentos con overlap para mejor contexto.
     * @param texto    texto completo
     * @param tamano   caracteres por fragmento (~800 ≈ 200 tokens)
     * @param overlap  caracteres de solapamiento entre fragmentos
     */
    private List<String> trocear(String texto, int tamano, int overlap) {
        List<String> fragmentos = new ArrayList<>();
        int i = 0;
        while (i < texto.length()) {
            int fin = Math.min(i + tamano, texto.length());
            String frag = texto.substring(i, fin).trim();
            if (frag.length() > 100) fragmentos.add(frag);
            i += tamano - overlap;
        }
        return fragmentos;
    }
}
