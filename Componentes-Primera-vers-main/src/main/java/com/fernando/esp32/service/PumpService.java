package com.fernando.esp32.service;

import com.fernando.esp32.model.PumpState;
import org.springframework.stereotype.Service;

/**
 * Mantiene en memoria el estado de la bomba de agua del bebedero automático
 * y registra en la base de datos los cambios de encendido/apagado como
 * comandos de actuador.
 */
@Service
public class PumpService {

    private final PumpState pump = new PumpState();
    private final IotDatabaseService dbService;

    public PumpService(IotDatabaseService dbService) {
        this.dbService = dbService;
        pump.setEnabled(false);
    }

    /**
     * Consulta el estado actual de la bomba de agua.
     *
     * @return el estado actual de la bomba.
     */
    public PumpState getPump() {
        return pump;
    }

    /**
     * Enciende o apaga la bomba de agua y registra en la base de datos el
     * cambio respecto al estado anterior.
     *
     * @param enabled {@code true} para encender la bomba, {@code false} para apagarla.
     */
    public void updatePump(boolean enabled) {
        if (pump.isEnabled() != enabled) {
            dbService.registrarComando("PUMP_ROOM2", enabled);
        }
        pump.setEnabled(enabled);
    }

}