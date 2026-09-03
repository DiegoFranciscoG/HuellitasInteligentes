package com.fernando.esp32.service;

import com.fernando.esp32.model.DhtRequest;
import com.fernando.esp32.model.DhtState;
import org.springframework.stereotype.Service;

/**
 * Mantiene en memoria la última lectura de temperatura y humedad reportada
 * por los sensores DHT del ESP32 para las dos salas monitoreadas.
 */
@Service
public class DhtService {

    private final DhtState dht = new DhtState();

    /**
     * Obtiene la última lectura conocida de temperatura y humedad.
     *
     * @return el estado actual del sensor DHT.
     */
    public DhtState getDht() {
        return dht;
    }

    /**
     * Actualiza la lectura de temperatura y humedad con los datos reportados por el dispositivo.
     *
     * @param request nueva lectura enviada por el ESP32.
     */
    public void updateDht(DhtRequest request) {

        dht.setTemperature1(request.getTemperature1());
        dht.setHumidity1(request.getHumidity1());

        dht.setTemperature2(request.getTemperature2());
        dht.setHumidity2(request.getHumidity2());

    }

}