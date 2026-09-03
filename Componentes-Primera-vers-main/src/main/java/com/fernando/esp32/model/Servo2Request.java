package com.fernando.esp32.model;

/**
 * Datos enviados para mover el segundo servomotor a un nuevo ángulo.
 */
public class Servo2Request {

    private int angle;

    public Servo2Request() {
    }

    public int getAngle() {
        return angle;
    }

    public void setAngle(int angle) {
        this.angle = angle;
    }

}