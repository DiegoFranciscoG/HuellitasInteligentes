package com.fernando.esp32.controller;

import com.fernando.esp32.model.Servo3Request;
import com.fernando.esp32.model.Servo3State;
import com.fernando.esp32.service.Servo3Service;
import org.springframework.web.bind.annotation.*;

/**
 * Controla el servomotor que orienta la cámara de la vivienda, para poder
 * girarla desde la web o la aplicación móvil sin salir de la vista de video.
 */
@RestController
@RequestMapping("/api/servo3")
@CrossOrigin
public class Servo3Controller {

    private final Servo3Service servo3Service;

    public Servo3Controller(Servo3Service servo3Service) {
        this.servo3Service = servo3Service;
    }

    /**
     * Consulta hacia dónde está apuntando la cámara.
     *
     * @return el estado (ángulo actual) del servo de la cámara.
     */
    @GetMapping
    public Servo3State getServo() {
        return servo3Service.getServo();
    }

    /**
     * Gira la cámara al ángulo indicado.
     *
     * @param request contiene el ángulo deseado.
     * @return el estado del servo luego de aplicar el cambio, ya recortado a 0–180.
     */
    @PostMapping
    public Servo3State updateServo(@RequestBody Servo3Request request) {
        servo3Service.updateAngle(request.getAngle());
        return servo3Service.getServo();
    }
}
