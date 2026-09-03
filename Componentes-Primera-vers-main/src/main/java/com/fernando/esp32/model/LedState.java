package com.fernando.esp32.model;

/**
 * Estado actual de las luces LED de las habitaciones, incluyendo si su
 * control es automático (por sensores PIR) o manual.
 */
public class LedState {

    private boolean room1Led;
    private boolean room2Led;

    // true = sensores PIR controlan las luces
    // false = control manual desde la web
    private boolean automatic = true;

    public LedState() {
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