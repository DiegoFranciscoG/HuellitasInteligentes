package com.fernando.esp32.model;

/**
 * Estado actual del servomotor principal. El ángulo se acota automáticamente
 * al rango válido de 0 a 180 grados al asignarlo.
 */
public class ServoState {

    private int angle;
    private String status;

    public ServoState() {
        this.angle = 90;
        this.status = "OK";
    }

    public ServoState(int angle) {
        this.angle = angle;
        this.status = "OK";
    }

    public int getAngle() {
        return angle;
    }

    public void setAngle(int angle) {

        if(angle < 0)
            angle = 0;

        if(angle > 180)
            angle = 180;

        this.angle = angle;
    }

    public String getStatus() {
        return status;
    }
}