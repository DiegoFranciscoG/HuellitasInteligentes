package com.fernando.esp32.model;

/**
 * Datos de una lectura de temperatura y humedad reportada por el sensor DHT del ESP32.
 */
public class DhtRequest {

    private float temperature1;
    private float humidity1;

    private float temperature2;
    private float humidity2;

    public DhtRequest() {
    }

    public float getTemperature1() {
        return temperature1;
    }

    public void setTemperature1(float temperature1) {
        this.temperature1 = temperature1;
    }

    public float getHumidity1() {
        return humidity1;
    }

    public void setHumidity1(float humidity1) {
        this.humidity1 = humidity1;
    }

    public float getTemperature2() {
        return temperature2;
    }

    public void setTemperature2(float temperature2) {
        this.temperature2 = temperature2;
    }

    public float getHumidity2() {
        return humidity2;
    }

    public void setHumidity2(float humidity2) {
        this.humidity2 = humidity2;
    }

}