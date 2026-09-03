package com.fernando.esp32.model;

/**
 * Última lectura conocida de calidad de aire del sensor MQ135.
 */
public class Mq135State {

    private int airQuality1;
    private int airQuality2;

    public Mq135State() {
    }

    public Mq135State(int airQuality1, int airQuality2) {
        this.airQuality1 = airQuality1;
        this.airQuality2 = airQuality2;
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