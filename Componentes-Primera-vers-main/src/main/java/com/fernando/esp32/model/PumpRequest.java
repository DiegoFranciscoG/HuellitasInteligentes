package com.fernando.esp32.model;

/**
 * Datos enviados para encender o apagar la bomba de agua.
 */
public class PumpRequest {

    private boolean enabled;

    public PumpRequest() {
    }

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

}