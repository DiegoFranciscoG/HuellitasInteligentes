package com.huellitas.auth;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.Map;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.core.type.TypeReference;

/**
 * Genera y decodifica los tokens JWT (JSON Web Token) que autentican a los
 * usuarios frente a la API, y ofrece utilidades para extraer el identificador
 * del usuario y de la casa autenticados a partir del encabezado {@code Authorization}.
 */
@Component
public class JwtUtil {

    @Value("${jwt.secret:HuellitasSecretKey12345678901234567890}")
    private String secret;

    @Value("${jwt.expiration:86400000}")
    private long expirationTime;

    private SecretKey getSigningKey() {
        return Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * Valida la firma y expiración de un JWT y devuelve sus claims — a
     * diferencia de {@link #getAuthenticatedUserId}, que solo decodifica el
     * payload sin comprobar que el token sea genuino. Este es el método que
     * debe usarse para decidir si una petición está autenticada.
     *
     * @param authHeader valor del encabezado {@code Authorization} (formato {@code Bearer <token>}).
     * @return los claims del token si la firma es válida y no expiró, o {@code null} en cualquier otro caso.
     */
    public Claims validarYObtenerClaims(String authHeader) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) return null;
        try {
            String token = authHeader.substring(7).trim();
            return Jwts.parser()
                .verifyWith(getSigningKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();
        } catch (JwtException | IllegalArgumentException e) {
            return null;
        }
    }

    /**
     * Extrae el objeto "usuario" de una respuesta JSON que puede venir
     * envuelta en un objeto contenedor (por ejemplo, el resultado de una
     * función de login que devuelve {@code {"usuario": {...}}}).
     *
     * @param jsonResponse respuesta JSON original.
     * @return el JSON del usuario si se pudo extraer, o el {@code jsonResponse} original en caso contrario.
     */
    public String extractUserJson(String jsonResponse) {
        try {
            ObjectMapper mapper = new ObjectMapper();
            Map<String, Object> map = mapper.readValue(jsonResponse, new TypeReference<Map<String, Object>>() {});
            if (map.containsKey("usuario") && map.get("usuario") instanceof Map) {
                return mapper.writeValueAsString(map.get("usuario"));
            }
            return jsonResponse;
        } catch (Exception e) {
            return jsonResponse;
        }
    }

    /**
     * Construye y firma un JWT a partir de los datos de un usuario en
     * formato JSON (identificador, nombre, email, rol, casa y estado de
     * verificación de correo), con la expiración configurada en {@code jwt.expiration}.
     *
     * @param userJson datos del usuario en JSON, ya sea directo o envuelto en {@code {"usuario": {...}}}.
     * @return el token JWT firmado.
     * @throws RuntimeException si el JSON es inválido o falla la firma — antes se devolvía silenciosamente
     *         un token vacío, que ningún llamador comprobaba, así que un login roto se veía como 200 OK.
     */
    @SuppressWarnings("deprecation")
    public String generateTokenFromJsonUser(String userJson) {
        try {
            ObjectMapper mapper = new ObjectMapper();
            Map<String, Object> map = mapper.readValue(userJson, new TypeReference<Map<String, Object>>() {});
            
            Map<String, Object> userMap = map;
            if (map.containsKey("usuario") && map.get("usuario") instanceof Map) {
                userMap = (Map<String, Object>) map.get("usuario");
            }
            
            return Jwts.builder()
                    .claim("usuario_id", userMap.get("id"))
                    .claim("nombre", userMap.get("nombre"))
                    .claim("email", userMap.get("email"))
                    .claim("rol", userMap.get("rol"))
                    .claim("casa_id", userMap.get("casa_id"))
                    .claim("email_verificado", Boolean.TRUE.equals(userMap.get("email_verificado")))
                    .setIssuedAt(new Date(System.currentTimeMillis()))
                    .setExpiration(new Date(System.currentTimeMillis() + expirationTime))
                    .signWith(getSigningKey())
                    .compact();
        } catch (Exception e) {
            throw new RuntimeException("No se pudo generar el token de sesión: " + e.getMessage(), e);
        }
    }

    /**
     * Extrae el identificador del usuario autenticado a partir del token JWT
     * enviado en el encabezado {@code Authorization}, sin validar la firma
     * (decodificación directa del payload).
     *
     * @param authHeader valor del encabezado {@code Authorization} (formato {@code Bearer <token>}).
     * @return el identificador del usuario, o {@code null} si el encabezado no es válido o no contiene el dato.
     */
    public Long getAuthenticatedUserId(String authHeader) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) return null;
        try {
            String token = authHeader.replace("Bearer ", "").trim();
            String[] parts = token.split("\\.");
            if (parts.length < 2) return null;
            String payload = new String(java.util.Base64.getUrlDecoder().decode(parts[1]), StandardCharsets.UTF_8);
            if (payload.contains("\"usuario_id\":")) {
                String val = payload.split("\"usuario_id\":")[1].split("[,}]")[0].replaceAll("[^0-9]", "");
                return val.isEmpty() ? null : Long.parseLong(val);
            } else if (payload.contains("\"id\":")) {
                String val = payload.split("\"id\":")[1].split("[,}]")[0].replaceAll("[^0-9]", "");
                return val.isEmpty() ? null : Long.parseLong(val);
            } else if (payload.contains("\"sub\":")) {
                String val = payload.split("\"sub\":")[1].split("[,}]")[0].replaceAll("[^0-9]", "");
                return val.isEmpty() ? null : Long.parseLong(val);
            }
        } catch (Exception ignored) {}
        return null;
    }

    /**
     * Extrae el identificador de la casa asociada al usuario autenticado a
     * partir del token JWT enviado en el encabezado {@code Authorization}.
     *
     * @param authHeader valor del encabezado {@code Authorization} (formato {@code Bearer <token>}).
     * @return el identificador de la casa, o {@code null} si el encabezado no es válido o no contiene el dato.
     */
    public Long getAuthenticatedCasaId(String authHeader) {
        if (authHeader == null || !authHeader.startsWith("Bearer ")) return null;
        try {
            String token = authHeader.replace("Bearer ", "").trim();
            String[] parts = token.split("\\.");
            if (parts.length < 2) return null;
            String payload = new String(java.util.Base64.getUrlDecoder().decode(parts[1]), StandardCharsets.UTF_8);
            if (payload.contains("\"casa_id\":")) {
                String val = payload.split("\"casa_id\":")[1].split("[,}]")[0].replaceAll("[^0-9]", "");
                return val.isEmpty() ? null : Long.parseLong(val);
            }
        } catch (Exception ignored) {}
        return null;
    }
}
