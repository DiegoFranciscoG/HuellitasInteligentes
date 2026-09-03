package com.fernando.esp32.service;

import com.fernando.esp32.model.FanRequest;
import com.fernando.esp32.model.FanState;
import org.springframework.stereotype.Service;

/**
 * Mantiene en memoria el estado de los ventiladores y registra en la base de
 * datos los cambios de encendido/apagado como comandos de actuador.
 */
@Service
public class FanService {

    private final FanState fan = new FanState();
    private final IotDatabaseService dbService;

    public FanService(IotDatabaseService dbService) {
        this.dbService = dbService;
    }

    /**
     * Consulta el estado actual de los ventiladores.
     *
     * @return el estado actual de los ventiladores.
     */
    public FanState getFan() {
        return fan;
    }

    /**
     * Actualiza el estado de los ventiladores y registra en la base de datos
     * los cambios respecto al estado anterior.
     *
     * @param request nuevo estado deseado para los ventiladores.
     */
    public void updateFan(FanRequest request) {

        if (fan.isFan1() != request.isFan1()) {
            dbService.registrarComando("FAN_ROOM1", request.isFan1());
        }
        if (fan.isFan2() != request.isFan2()) {
            dbService.registrarComando("FAN_ROOM2", request.isFan2());
        }

        fan.setFan1(request.isFan1());
        fan.setFan2(request.isFan2());
        fan.setAutomatic(request.isAutomatic());

    }

}