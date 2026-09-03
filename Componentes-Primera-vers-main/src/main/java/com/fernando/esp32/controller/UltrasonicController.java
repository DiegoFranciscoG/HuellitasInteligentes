package com.fernando.esp32.controller;

import com.fernando.esp32.model.UltrasonicRequest;
import com.fernando.esp32.model.UltrasonicState;
import com.fernando.esp32.service.UltrasonicService;
import org.springframework.web.bind.annotation.*;

/**
 * Recibe las lecturas del sensor ultrasónico del sistema IoT, usado para medir
 * distancias (por ejemplo, nivel de alimento o presencia de la mascota).
 */
@RestController
@RequestMapping("/api/ultrasonic")
@CrossOrigin
public class UltrasonicController {

    private final UltrasonicService ultrasonicService;

    public UltrasonicController(
            UltrasonicService ultrasonicService) {

        this.ultrasonicService = ultrasonicService;

    }

    /**
     * Registra una nueva lectura de distancia reportada por el ESP32.
     *
     * @param request datos de la lectura enviados por el dispositivo.
     * @return el estado del sensor ultrasónico luego de actualizarlo.
     */
    @PostMapping
    public UltrasonicState update(
            @RequestBody UltrasonicRequest request){

        ultrasonicService.update(request);

        return ultrasonicService.getUltrasonic();

    }

}