package com.fernando.esp32.controller;

import com.fernando.esp32.model.DhtRequest;
import com.fernando.esp32.model.DhtState;
import com.fernando.esp32.service.DhtService;
import org.springframework.web.bind.annotation.*;

/**
 * Expone las lecturas del sensor de temperatura y humedad DHT usado para
 * monitorear el ambiente donde se encuentra la mascota.
 */
@RestController
@RequestMapping("/api/dht")
@CrossOrigin
public class DhtController {

    private final DhtService dhtService;

    public DhtController(DhtService dhtService) {

        this.dhtService = dhtService;

    }

    /**
     * Obtiene la última lectura conocida de temperatura y humedad.
     *
     * @return el estado actual del sensor DHT.
     */
    @GetMapping
    public DhtState getDht() {

        return dhtService.getDht();

    }

    /**
     * Registra una nueva lectura de temperatura y humedad reportada por el ESP32.
     *
     * @param request datos de la lectura enviados por el dispositivo.
     * @return el estado del sensor DHT luego de actualizarlo.
     */
    @PostMapping
    public DhtState update(@RequestBody DhtRequest request) {

        dhtService.updateDht(request);

        return dhtService.getDht();

    }

}