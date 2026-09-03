package com.fernando.esp32.model;

/**
 * Última lectura conocida del sensor ultrasónico.
 */
public class UltrasonicState {

    private double distance;

    public UltrasonicState() {
    }

    public double getDistance() {
        return distance;
    }

    public void setDistance(double distance) {
        this.distance = distance;
    }

}