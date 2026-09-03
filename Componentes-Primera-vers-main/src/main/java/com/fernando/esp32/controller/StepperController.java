package com.fernando.esp32.controller;

import com.fernando.esp32.model.StepperRequest;
import com.fernando.esp32.model.StepperState;
import com.fernando.esp32.service.StepperService;
import org.springframework.web.bind.annotation.*;

/**
 * Controla el motor paso a paso (stepper) del sistema IoT, usado para
 * mecanismos que requieren posicionamiento preciso, como el dosificador de alimento.
 */
@RestController
@RequestMapping("/api/stepper")
@CrossOrigin
public class StepperController {

    private final StepperService stepperService;

    public StepperController(StepperService stepperService) {
        this.stepperService = stepperService;
    }

    /**
     * Consulta el estado actual del motor paso a paso.
     *
     * @return el estado (posición actual) del stepper.
     */
    @GetMapping
    public StepperState getStepper() {
        return stepperService.getStepper();
    }

    /**
     * Mueve el motor paso a paso a la posición indicada.
     *
     * @param request contiene la posición deseada para el motor.
     * @return el estado del motor luego de aplicar el cambio.
     */
    @PostMapping
    public StepperState updateStepper(@RequestBody StepperRequest request) {

        stepperService.updatePosition(request.getPosition());

        return stepperService.getStepper();

    }

}