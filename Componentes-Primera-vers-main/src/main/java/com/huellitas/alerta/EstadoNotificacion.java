package com.huellitas.alerta;

/**
 * Estado de entrega de una {@link Notificacion}: en espera de ser enviada,
 * ya enviada con éxito, o fallida.
 */
public enum EstadoNotificacion {
    PENDIENTE, ENVIADA, FALLIDA
}
