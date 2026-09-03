package com.fernando.esp32.service;

import com.fernando.esp32.model.LedRequest;
import com.fernando.esp32.model.LedState;
import org.springframework.stereotype.Service;

/**
 * Mantiene en memoria el estado de las luces LED de cada sala y registra en
 * la base de datos los cambios de encendido/apagado como comandos de
 * actuador. También es usado por {@link MotionService} para encender o
 * apagar las luces automáticamente según la detección de movimiento.
 */
@Service
public class LedService {

    private final LedState led = new LedState();
    private final IotDatabaseService dbService;

    public LedService(IotDatabaseService dbService) {
        this.dbService = dbService;
    }

    /**
     * Consulta el estado actual de las luces LED.
     *
     * @return el estado actual de las luces LED.
     */
    public LedState getLed() {
        return led;
    }

    /**
     * Actualiza el estado de las luces LED (encendido y modo automático) y
     * registra en la base de datos los cambios respecto al estado anterior.
     *
     * @param request nuevo estado deseado para las luces LED.
     */
    public void updateLed(LedRequest request) {

        if (led.isRoom1Led() != request.isRoom1Led()) {
            dbService.registrarComando("LED_ROOM1", request.isRoom1Led());
        }
        if (led.isRoom2Led() != request.isRoom2Led()) {
            dbService.registrarComando("LED_ROOM2", request.isRoom2Led());
        }

        led.setRoom1Led(request.isRoom1Led());
        led.setRoom2Led(request.isRoom2Led());
        led.setAutomatic(request.isAutomatic());

    }

    /**
     * Fuerza el estado de la luz de la sala 1 sin pasar por el registro de
     * comandos (usado por el control automático basado en movimiento).
     *
     * @param value {@code true} para encender la luz, {@code false} para apagarla.
     */
    public void setRoom1Led(boolean value) {
        led.setRoom1Led(value);
    }

    /**
     * Fuerza el estado de la luz de la sala 2 sin pasar por el registro de
     * comandos (usado por el control automático basado en movimiento).
     *
     * @param value {@code true} para encender la luz, {@code false} para apagarla.
     */
    public void setRoom2Led(boolean value) {
        led.setRoom2Led(value);
    }

}