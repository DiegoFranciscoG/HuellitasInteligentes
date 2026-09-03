package com.fernando.esp32.model;

/**
 * Datos enviados para mover el motor paso a paso a una nueva posición.
 */
public class StepperRequest {

    private int position;

    public StepperRequest() {
    }

    public int getPosition() {
        return position;
    }

    public void setPosition(int position) {
        this.position = position;
    }

}