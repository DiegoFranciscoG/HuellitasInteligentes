package com.huellitas.auth;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Traduce las excepciones lanzadas por cualquier controlador REST del
 * sistema a respuestas HTTP consistentes con un cuerpo JSON uniforme
 * ({@code ok}/{@code error}/{@code message}), evitando exponer trazas
 * internas al cliente. {@code error} y {@code message} llevan siempre el
 * mismo texto — el interceptor HTTP del frontend solo lee {@code message},
 * así que duplicarlo aquí evita el bug de "Datos inválidos" genérico que
 * aparecía cuando un endpoint solo mandaba {@code error}.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static ResponseEntity<?> body(HttpStatus status, String mensaje) {
        return ResponseEntity.status(status).body(Map.of(
            "ok", false,
            "error", mensaje,
            "message", mensaje
        ));
    }

    /**
     * Maneja argumentos inválidos recibidos por los controladores.
     *
     * @param ex excepción capturada.
     * @return respuesta HTTP 400 con el mensaje de la excepción.
     */
    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<?> handleIllegalArgument(IllegalArgumentException ex) {
        return body(HttpStatus.BAD_REQUEST, ex.getMessage() != null ? ex.getMessage() : "Parámetro o argumento inválido");
    }

    /**
     * Maneja la búsqueda de una entidad (mascota, casa, usuario, etc.) que no existe.
     *
     * @param ex excepción capturada.
     * @return respuesta HTTP 404 con el mensaje de la excepción.
     */
    @ExceptionHandler(jakarta.persistence.EntityNotFoundException.class)
    public ResponseEntity<?> handleEntityNotFound(jakarta.persistence.EntityNotFoundException ex) {
        return body(HttpStatus.NOT_FOUND, ex.getMessage() != null ? ex.getMessage() : "Recurso no encontrado");
    }

    /**
     * Maneja intentos de acceso a un recurso sin los permisos necesarios.
     *
     * @param ex excepción capturada.
     * @return respuesta HTTP 403 con un mensaje genérico de acceso denegado.
     */
    @ExceptionHandler(org.springframework.security.access.AccessDeniedException.class)
    public ResponseEntity<?> handleAccessDenied(org.springframework.security.access.AccessDeniedException ex) {
        return body(HttpStatus.FORBIDDEN, "Acceso denegado. No cuentas con los permisos suficientes.");
    }

    /**
     * Maneja las peticiones bloqueadas por el límite de intentos (rate limiting).
     *
     * @param ex excepción capturada.
     * @return respuesta HTTP 429 indicando que se debe reintentar más tarde.
     */
    @ExceptionHandler(RateLimitExceededException.class)
    public ResponseEntity<?> handleRateLimitExceeded(RateLimitExceededException ex) {
        return body(HttpStatus.TOO_MANY_REQUESTS, ex.getMessage() != null ? ex.getMessage() : "Demasiados intentos. Espera un momento antes de volver a intentarlo.");
    }

    /**
     * Maneja peticiones a rutas que no existen (Spring las reporta como
     * "recurso estático no encontrado" al no coincidir con ningún
     * controlador). Sin este manejador, caerían en {@link #handleGenericException}
     * y se reportarían como error 500 en vez de 404.
     *
     * @param ex excepción capturada.
     * @return respuesta HTTP 404 indicando que la ruta no existe.
     */
    @ExceptionHandler(org.springframework.web.servlet.resource.NoResourceFoundException.class)
    public ResponseEntity<?> handleNoResourceFound(org.springframework.web.servlet.resource.NoResourceFoundException ex) {
        return body(HttpStatus.NOT_FOUND, "La ruta solicitada no existe.");
    }

    /**
     * Códigos de error de negocio que las funciones SQL (PL/pgSQL) lanzan
     * con {@code RAISE EXCEPTION 'CODIGO'}, mapeados al código HTTP que le
     * corresponde a cada uno. JDBC envuelve ese mensaje en una traza larga
     * ("JDBC exception executing SQL [...] [ERROR: CODIGO ...]"), así que
     * se detecta por coincidencia de substring — igual que antes — pero
     * ahora la respuesta nunca incluye esa traza cruda, solo el código.
     */
    private static final Map<String, HttpStatus> CODIGOS_NEGOCIO = new LinkedHashMap<>();
    static {
        // 401 — credenciales o token inválido/expirado
        for (String c : new String[]{"CREDENCIALES_INVALIDAS", "CUENTA_BLOQUEADA", "CUENTA_SANCIONADA",
                "TOKEN_EXPIRADO", "TOKEN_INVALIDO", "TOKEN_USADO", "CODIGO_EXPIRADO", "CODIGO_INVALIDO"}) {
            CODIGOS_NEGOCIO.put(c, HttpStatus.UNAUTHORIZED);
        }
        // 403 — autenticado pero sin permiso sobre ese recurso puntual
        for (String c : new String[]{"NO_AUTORIZADO", "NO_ES_MIEMBRO", "NO_SE_PUEDE_EXPULSAR_AL_CREADOR",
                "TIEMPO_EDICION_EXPIRADO"}) {
            CODIGOS_NEGOCIO.put(c, HttpStatus.FORBIDDEN);
        }
        // 404 — el recurso referenciado no existe
        for (String c : new String[]{"USUARIO_NO_ENCONTRADO", "GRUPO_NO_ENCONTRADO", "PLAN_NO_ENCONTRADO",
                "PUBLICACION_NO_ENCONTRADA", "SALA_NO_ENCONTRADA", "COMENTARIO_NO_ENCONTRADO",
                "DISPOSITIVO_NO_REGISTRADO"}) {
            CODIGOS_NEGOCIO.put(c, HttpStatus.NOT_FOUND);
        }
        // 400 — dato inválido o conflicto con el estado actual
        for (String c : new String[]{"EMAIL_YA_REGISTRADO", "EMAIL_YA_VERIFICADO", "CASA_YA_TIENE_MIEMBRO",
                "MAC_YA_REGISTRADA", "PLAN_INVALIDO", "PLAN_YA_EXISTE", "USUARIO_YA_TIENE_CASA",
                "USUARIO_NO_ENCONTRADO_O_YA_TIENE_PASSWORD", "NOMBRE_INVALIDO", "TEXTO_INCOHERENTE",
                "GRUPO_NOMBRE_DUPLICADO"}) {
            CODIGOS_NEGOCIO.put(c, HttpStatus.BAD_REQUEST);
        }
    }

    /**
     * Maneja cualquier otra excepción no capturada por los manejadores
     * anteriores. Reconoce los códigos de error de negocio que lanzan las
     * funciones SQL y responde con el código HTTP correcto para cada uno,
     * sin filtrar la traza JDBC cruda al cliente; lo que no coincide con
     * ningún código conocido se reporta como error 500 genérico.
     *
     * @param ex excepción capturada.
     * @return respuesta HTTP con el código apropiado según el tipo de error detectado.
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<?> handleGenericException(Exception ex) {
        String msg = ex.getMessage();
        if (msg != null) {
            if (msg.contains("grupo_nombre_key")) {
                return body(HttpStatus.BAD_REQUEST, "GRUPO_NOMBRE_DUPLICADO");
            }
            for (Map.Entry<String, HttpStatus> entry : CODIGOS_NEGOCIO.entrySet()) {
                if (msg.contains(entry.getKey())) {
                    return body(entry.getValue(), entry.getKey());
                }
            }
        }
        return body(HttpStatus.INTERNAL_SERVER_ERROR, "Error interno del servidor");
    }
}
