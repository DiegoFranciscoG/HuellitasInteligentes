package com.fernando.esp32.model;

/**
 * Estado actual de la bomba de agua del bebedero automático.
 */
public class PumpState {

    private boolean enabled;

    public PumpState() {
        this.enabled = false;
    }

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

}