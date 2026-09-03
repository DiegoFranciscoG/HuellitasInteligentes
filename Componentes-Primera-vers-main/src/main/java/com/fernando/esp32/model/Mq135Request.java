package com.fernando.esp32.model;

/**
 * Datos de una lectura de calidad de aire reportada por el sensor MQ135.
 */
public class Mq135Request {

    private int airQuality1;
    private int airQuality2;

    public Mq135Request() {
    }

    public int getAirQuality1() {
        return airQuality1;
    }

    public void setAirQuality1(int airQuality1) {
        this.airQuality1 = airQuality1;
    }

    public int getAirQuality2() {
        return airQuality2;
    }

    public void setAirQuality2(int airQuality2) {
        this.airQuality2 = airQuality2;
    }

}