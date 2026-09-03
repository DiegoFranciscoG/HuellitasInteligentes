package com.fernando.esp32.service;

import com.fernando.esp32.model.StepperState;
import org.springframework.stereotype.Service;

/**
 * Mantiene en memoria la posición del motor paso a paso utilizado por el
 * dosificador de alimento.
 */
@Service
public class StepperService {

    private final StepperState stepper = new StepperState();

    /**
     * Consulta el estado actual del motor paso a paso.
     *
     * @return el estado actual del stepper.
     */
    public StepperState getStepper() {
        return stepper;
    }

    /**
     * Mueve el motor paso a paso a la posición indicada.
     *
     * @param position nueva posición deseada para el motor.
     */
    public void updatePosition(int position) {
        stepper.setPosition(position);
    }

}