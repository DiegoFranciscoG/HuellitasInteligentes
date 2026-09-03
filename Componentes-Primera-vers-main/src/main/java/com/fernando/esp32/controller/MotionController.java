package com.fernando.esp32.controller;

import com.fernando.esp32.model.MotionRequest;
import com.fernando.esp32.model.MotionState;
import com.fernando.esp32.service.MotionService;
import org.springframework.web.bind.annotation.*;

/**
 * Expone las lecturas del sensor de movimiento (PIR) usado para detectar
 * actividad de la mascota en su zona de monitoreo.
 */
@RestController
@RequestMapping("/api/motion")
@CrossOrigin
public class MotionController {

    private final MotionService motionService;

    public MotionController(MotionService motionService) {
        this.motionService = motionService;
    }

    /**
     * Consulta la última lectura del sensor de movimiento.
     *
     * @return el estado actual del sensor de movimiento.
     */
    @GetMapping
    public MotionState getMotion() {

        return motionService.getMotion();

    }

    /**
     * Registra una nueva lectura de movimiento reportada por el ESP32.
     *
     * @param request datos de la lectura enviados por el dispositivo.
     * @return el estado del sensor de movimiento luego de actualizarlo.
     */
    @PostMapping
    public MotionState updateMotion(@RequestBody MotionRequest request) {

        motionService.updateMotion(request);

        return motionService.getMotion();

    }

}