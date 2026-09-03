package com.fernando.esp32.model;

/**
 * Datos enviados para mover el servomotor principal a un nuevo ángulo.
 */
public class ServoRequest {

    private int angle;

    public ServoRequest() {
    }

    public int getAngle() {
        return angle;
    }

    public void setAngle(int angle) {
        this.angle = angle;
    }
}