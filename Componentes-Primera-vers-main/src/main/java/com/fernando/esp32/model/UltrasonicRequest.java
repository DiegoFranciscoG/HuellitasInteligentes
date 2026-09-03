package com.fernando.esp32.model;

/**
 * Datos de una lectura de distancia reportada por el sensor ultrasónico.
 */
public class UltrasonicRequest {

    private double distance;

    public UltrasonicRequest() {
    }

    public double getDistance() {
        return distance;
    }

    public void setDistance(double distance) {
        this.distance = distance;
    }

}