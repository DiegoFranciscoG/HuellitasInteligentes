package com.fernando.esp32.model;

/**
 * Datos de una lectura de nivel de agua reportada por el sensor del bebedero.
 */
public class WaterLevelRequest {

    private int level;

    public WaterLevelRequest() {
    }

    public int getLevel() {
        return level;
    }

    public void setLevel(int level) {
        this.level = level;
    }

}