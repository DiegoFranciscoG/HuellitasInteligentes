package com.huellitas.alerta;

/**
 * Medio por el que se entrega una {@link Notificacion} al usuario: push al
 * dispositivo móvil, correo electrónico, o en tiempo real vía WebSocket.
 */
public enum CanalNotificacion {
    PUSH, EMAIL, WEBSOCKET
}
