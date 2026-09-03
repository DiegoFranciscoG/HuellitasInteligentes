package com.huellitas.auth;

/** Señala que una IP superó el límite de peticiones permitido para una ruta protegida por rate limiting. */
public class RateLimitExceededException extends RuntimeException {
    public RateLimitExceededException(String message) {
        super(message);
    }
}
