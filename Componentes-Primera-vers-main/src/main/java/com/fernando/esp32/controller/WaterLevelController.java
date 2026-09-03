package com.fernando.esp32.controller;

import com.fernando.esp32.model.WaterLevelRequest;
import com.fernando.esp32.model.WaterLevelState;
import com.fernando.esp32.service.WaterLevelService;

import org.springframework.web.bind.annotation.*;

/**
 * Expone las lecturas del sensor de nivel de agua, usado para monitorear la
 * cantidad de agua disponible en el bebedero automático de la mascota.
 */
@RestController
@RequestMapping("/api/water")
@CrossOrigin
public class WaterLevelController {

    private final WaterLevelService service;

    public WaterLevelController(
            WaterLevelService service) {

        this.service = service;

    }

    /**
     * Consulta la última lectura del nivel de agua.
     *
     * @return el estado actual del sensor de nivel de agua.
     */
    @GetMapping
    public WaterLevelState getWater() {

        return service.getWater();

    }

    /**
     * Registra una nueva lectura de nivel de agua reportada por el ESP32.
     *
     * @param request datos de la lectura enviados por el dispositivo.
     * @return el estado del sensor de nivel de agua luego de actualizarlo.
     */
    @PostMapping
    public WaterLevelState updateWater(

            @RequestBody WaterLevelRequest request) {

        service.updateWater(request);

        return service.getWater();

    }

}