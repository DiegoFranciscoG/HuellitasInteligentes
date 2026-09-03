package com.fernando.esp32.controller;

import com.fernando.esp32.model.Mq135Request;
import com.fernando.esp32.model.Mq135State;
import com.fernando.esp32.service.Mq135Service;
import org.springframework.web.bind.annotation.*;

/**
 * Expone las lecturas del sensor de calidad de aire MQ135, usado para
 * monitorear gases y olores en el ambiente de la mascota.
 */
@RestController
@RequestMapping("/api/mq135")
@CrossOrigin
public class Mq135Controller {

    private final Mq135Service mq135Service;

    public Mq135Controller(Mq135Service mq135Service) {
        this.mq135Service = mq135Service;
    }

    /**
     * Consulta la última lectura del sensor de calidad de aire.
     *
     * @return el estado actual del sensor MQ135.
     */
    @GetMapping
    public Mq135State getMq135() {

        return mq135Service.getMq135();

    }

    /**
     * Registra una nueva lectura de calidad de aire reportada por el ESP32.
     *
     * @param request datos de la lectura enviados por el dispositivo.
     * @return el estado del sensor MQ135 luego de actualizarlo.
     */
    @PostMapping
    public Mq135State updateMq135(
            @RequestBody Mq135Request request) {

        mq135Service.updateMq135(request);

        return mq135Service.getMq135();

    }

}