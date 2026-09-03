package com.fernando.esp32.service;

import com.fernando.esp32.model.UltrasonicRequest;
import com.fernando.esp32.model.UltrasonicState;
import org.springframework.stereotype.Service;

/**
 * Mantiene en memoria la última lectura del sensor ultrasónico, usada para
 * estimar el nivel de alimento disponible en el dispensador.
 */
@Service
public class UltrasonicService {

    private final UltrasonicState ultrasonic =
            new UltrasonicState();

    /**
     * Obtiene la última lectura conocida del sensor ultrasónico.
     *
     * @return el estado actual del sensor ultrasónico.
     */
    public UltrasonicState getUltrasonic() {
        return ultrasonic;
    }

    /**
     * Actualiza la lectura de distancia con los datos reportados por el dispositivo.
     *
     * @param request nueva lectura enviada por el ESP32.
     */
    public void update(UltrasonicRequest request) {

        ultrasonic.setDistance(
                request.getDistance()
        );

    }

}