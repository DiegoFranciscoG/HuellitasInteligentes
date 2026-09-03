package com.fernando.esp32.service;

import com.fernando.esp32.model.WaterLevelRequest;
import com.fernando.esp32.model.WaterLevelState;
import org.springframework.stereotype.Service;

/**
 * Mantiene en memoria la última lectura del sensor de nivel de agua del bebedero automático.
 */
@Service
public class WaterLevelService {

    private final WaterLevelState water =
            new WaterLevelState();

    /**
     * Obtiene la última lectura conocida del nivel de agua.
     *
     * @return el estado actual del sensor de nivel de agua.
     */
    public WaterLevelState getWater() {
        return water;
    }

    /**
     * Actualiza la lectura de nivel de agua con los datos reportados por el dispositivo.
     *
     * @param request nueva lectura enviada por el ESP32.
     */
    public void updateWater(WaterLevelRequest request) {

        water.setLevel(request.getLevel());

    }

}   