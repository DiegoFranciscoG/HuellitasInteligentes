package com.huellitas.ia;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.List;
import java.util.Map;

/**
 * Busca negocios cercanos a una ubicación geográfica (tiendas de mascotas,
 * veterinarias, etc.) a través de la API de Google Places.
 */
@Service
public class PlacesService {

    @Value("${google.places.api.key:}")
    private String placesApiKey;

    private final RestTemplate restTemplate = new RestTemplate();

    /**
     * Busca negocios de un tipo dado dentro de un radio de 20 km alrededor de una coordenada.
     *
     * @param lat latitud de referencia.
     * @param lng longitud de referencia.
     * @param tipo tipo de negocio según la taxonomía de Google Places (por ejemplo, {@code pet_store}).
     * @return la respuesta de Google Places en formato JSON (como texto), o un JSON de error si la API no está configurada o falla.
     */
    public String buscarNegociosCercanos(double lat, double lng, String tipo) {
        if (placesApiKey == null || placesApiKey.isBlank()) {
            return "{\"error\": \"Places API no configurada\"}";
        }

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("X-Goog-Api-Key", placesApiKey);
            headers.set("X-Goog-FieldMask", "places.id,places.displayName,places.formattedAddress,places.rating,places.regularOpeningHours,places.currentOpeningHours,places.googleMapsUri,places.location");

            Map<String, Object> body = Map.of(
                "includedTypes", List.of(tipo),
                "maxResultCount", 8,
                "locationRestriction", Map.of(
                    "circle", Map.of(
                        "center", Map.of(
                            "latitude", lat,
                            "longitude", lng
                        ),
                        "radius", 20000.0
                    )
                )
            );

            HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);
            String url = "https://places.googleapis.com/v1/places:searchNearby";

            ResponseEntity<String> response = restTemplate.postForEntity(url, entity, String.class);

            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                return response.getBody();
            }
            return "{\"error\": \"Places API request failed\"}";
        } catch (Exception e) {
            return "{\"error\": \"Places API no configurada\"}";
        }
    }
}
