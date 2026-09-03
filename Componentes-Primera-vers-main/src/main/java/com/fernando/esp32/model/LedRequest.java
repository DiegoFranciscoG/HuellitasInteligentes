package com.fernando.esp32.model;

/**
 * Datos enviados para actualizar el estado de las luces LED de las habitaciones.
 */
public class LedRequest {

    private boolean room1Led;
    private boolean room2Led;
    private boolean automatic;

    public LedRequest() {
    }

    public boolean isRoom1Led() {
        return room1Led;
    }

    public void setRoom1Led(boolean room1Led) {
        this.room1Led = room1Led;
    }

    public boolean isRoom2Led() {
        return room2Led;
    }

    public void setRoom2Led(boolean room2Led) {
        this.room2Led = room2Led;
    }

    public boolean isAutomatic() {
        return automatic;
    }

    public void setAutomatic(boolean automatic) {
        this.automatic = automatic;
    }

}