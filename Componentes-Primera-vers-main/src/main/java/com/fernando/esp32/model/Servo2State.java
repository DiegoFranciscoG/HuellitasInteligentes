package com.fernando.esp32.model;

/**
 * Estado actual (ángulo) del segundo servomotor.
 */
public class Servo2State {

    private int angle = 90;

    public Servo2State() {
    }

    public Servo2State(int angle) {
        this.angle = angle;
    }

    public int getAngle() {
        return angle;
    }

    public void setAngle(int angle) {
        this.angle = angle;
    }

}