package com.fernando.esp32.service;

import com.fernando.esp32.model.Mq135Request;
import com.fernando.esp32.model.Mq135State;
import org.springframework.stereotype.Service;

/**
 * Mantiene en memoria la última lectura de calidad de aire reportada por los
 * sensores MQ135 del ESP32 para las dos salas monitoreadas.
 */
@Service
public class Mq135Service {

    private final Mq135State mq135 = new Mq135State();

    /**
     * Obtiene la última lectura conocida de calidad de aire.
     *
     * @return el estado actual del sensor MQ135.
     */
    public Mq135State getMq135() {
        return mq135;
    }

    /**
     * Actualiza la lectura de calidad de aire con los datos reportados por el dispositivo.
     *
     * @param request nueva lectura enviada por el ESP32.
     */
    public void updateMq135(Mq135Request request) {

        mq135.setAirQuality1(request.getAirQuality1());
        mq135.setAirQuality2(request.getAirQuality2());

    }

}