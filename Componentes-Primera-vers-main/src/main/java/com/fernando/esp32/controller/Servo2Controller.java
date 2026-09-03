package com.fernando.esp32.controller;

import com.fernando.esp32.model.Servo2Request;
import com.fernando.esp32.model.Servo2State;
import com.fernando.esp32.service.Servo2Service;
import org.springframework.web.bind.annotation.*;

/**
 * Controla el segundo servomotor del sistema IoT (independiente del servo
 * principal), usado como actuador auxiliar del dispensador/mecanismo físico.
 */
@RestController
@RequestMapping("/api/servo2")
@CrossOrigin("*")
public class Servo2Controller {

    private final Servo2Service service;

    public Servo2Controller(Servo2Service service) {
        this.service = service;
    }

    /**
     * Consulta el estado actual del segundo servomotor.
     *
     * @return el estado (ángulo actual, etc.) del servo.
     */
    @GetMapping
    public Servo2State getServo() {
        return service.getServo();
    }

    /**
     * Actualiza la posición del segundo servomotor.
     *
     * @param request nueva posición/ángulo deseado para el servo.
     * @return el estado del servo luego de aplicar el cambio.
     */
    @PostMapping
    public Servo2State updateServo(
            @RequestBody Servo2Request request) {

        service.updateServo(request);

        return service.getServo();

    }

}