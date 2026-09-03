package com.fernando.esp32.service;

import org.springframework.stereotype.Service;

/**
 * Mantiene el interruptor global del modo automático: cuando está activo,
 * los servicios de clima ({@link ClimateControlService}) y alimentación
 * ({@link FeedingService}) actúan solos según las lecturas de los sensores;
 * cuando está desactivado, el control queda en manos del usuario.
 */
@Service
public class AutomaticModeService {

    private boolean automaticMode = true; // Por defecto, activado

    /**
     * Consulta si el modo automático global está activo.
     *
     * @return {@code true} si el modo automático está activado.
     */
    public boolean isAutomaticMode() {
        return automaticMode;
    }

    /**
     * Activa o desactiva el modo automático global.
     *
     * @param enabled {@code true} para activarlo, {@code false} para pasar a control manual.
     */
    public void setAutomaticMode(boolean enabled) {
        this.automaticMode = enabled;
        System.out.println("🔄 Modo automático global: " + (enabled ? "ACTIVADO" : "DESACTIVADO"));
    }

    /**
     * Invierte el estado actual del modo automático global.
     */
    public void toggleAutomaticMode() {
        this.automaticMode = !this.automaticMode;
        System.out.println("🔄 Modo automático global: " + (this.automaticMode ? "ACTIVADO" : "DESACTIVADO"));
    }
}