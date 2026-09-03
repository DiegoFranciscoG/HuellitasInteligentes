package com.fernando.esp32.controller;

import com.fernando.esp32.service.AutomaticModeService;
import org.springframework.web.bind.annotation.*;

/**
 * Expone el control del modo automático del sistema IoT (ESP32), que permite
 * que los actuadores (bomba, ventilador, servos, etc.) reaccionen solos a las
 * lecturas de los sensores sin intervención manual del usuario.
 */
@RestController
@RequestMapping("/api/automatic-mode")
@CrossOrigin(origins = "*")
public class AutomaticModeController {

    private final AutomaticModeService automaticModeService;

    public AutomaticModeController(AutomaticModeService automaticModeService) {
        this.automaticModeService = automaticModeService;
    }

    /**
     * Consulta si el modo automático está actualmente activo.
     *
     * @return {@code true} si el sistema está operando en modo automático.
     */
    @GetMapping
    public boolean getAutomaticMode() {
        return automaticModeService.isAutomaticMode();
    }

    /**
     * Activa o desactiva el modo automático.
     *
     * @param enabled {@code true} para habilitar el modo automático, {@code false} para pasar a control manual.
     * @return el estado del modo automático luego de aplicar el cambio.
     */
    @PostMapping
    public boolean setAutomaticMode(@RequestBody boolean enabled) {
        automaticModeService.setAutomaticMode(enabled);
        return automaticModeService.isAutomaticMode();
    }

    /**
     * Invierte el estado actual del modo automático (de activo a inactivo o viceversa).
     *
     * @return el estado del modo automático luego de invertirlo.
     */
    @PostMapping("/toggle")
    public boolean toggleAutomaticMode() {
        automaticModeService.toggleAutomaticMode();
        return automaticModeService.isAutomaticMode();
    }
}