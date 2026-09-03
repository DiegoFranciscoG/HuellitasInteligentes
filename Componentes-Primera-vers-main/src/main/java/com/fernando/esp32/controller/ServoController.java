package com.fernando.esp32.controller;

import com.fernando.esp32.model.ServoRequest;
import com.fernando.esp32.model.ServoState;
import com.fernando.esp32.service.ServoService;
import org.springframework.web.bind.annotation.*;

/**
 * Controla el servomotor principal del sistema IoT, usado como actuador del
 * mecanismo físico (por ejemplo, la compuerta del dispensador de alimento).
 */
@RestController
@RequestMapping("/api/servo")
@CrossOrigin
public class ServoController {

    private final ServoService servoService;

    public ServoController(ServoService servoService) {
        this.servoService = servoService;
    }

    /**
     * Consulta el estado actual del servomotor principal.
     *
     * @return el estado (ángulo actual) del servo.
     */
    @GetMapping
    public ServoState getServo() {
        return servoService.getServo();
    }

    /**
     * Mueve el servomotor principal al ángulo indicado.
     *
     * @param request contiene el ángulo deseado para el servo.
     * @return el estado del servo luego de aplicar el cambio.
     */
    @PostMapping
    public ServoState updateServo(@RequestBody ServoRequest request) {

        servoService.updateAngle(request.getAngle());

        return servoService.getServo();
    }

}