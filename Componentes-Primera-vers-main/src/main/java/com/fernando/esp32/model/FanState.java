package com.fernando.esp32.model;

/**
 * Estado actual de los ventiladores del sistema IoT.
 */
public class FanState {

    private boolean fan1 = false;

    private boolean fan2 = false;

    private boolean automatic = false;

    public FanState() {
    }

    public boolean isFan1() {
        return fan1;
    }

    public void setFan1(boolean fan1) {
        this.fan1 = fan1;
    }

    public boolean isFan2() {
        return fan2;
    }

    public void setFan2(boolean fan2) {
        this.fan2 = fan2;
    }

    public boolean isAutomatic() {
        return automatic;
    }

    public void setAutomatic(boolean automatic) {
        this.automatic = automatic;
    }

}