package com.fernando.esp32.service;

import com.fernando.esp32.model.MotionRequest;
import com.fernando.esp32.model.MotionState;
import org.springframework.stereotype.Service;

/**
 * Interpreta las lecturas de los sensores de movimiento (PIR) de entrada y
 * salida de cada sala como una máquina de estados: detecta la secuencia
 * "entrada seguida de salida" (la mascota se queda en la sala) para encender
 * la luz, y "salida seguida de entrada" (la mascota se va) para apagarla.
 * Solo actúa si el modo automático global y el modo automático de luces
 * están activos.
 */
@Service
public class MotionService {

    private final MotionState motion = new MotionState();

    private final LedService ledService;
    private final AutomaticModeService automaticModeService;

    public MotionService(LedService ledService, AutomaticModeService automaticModeService) {
        this.ledService = ledService;
        this.automaticModeService = automaticModeService;
    }

    // Estados anteriores
    private boolean lastRoom1Entry = false;
    private boolean lastRoom1Exit = false;

    private boolean lastRoom2Entry = false;
    private boolean lastRoom2Exit = false;

    // Máquina de estados
    private boolean waitingRoom1Exit = false;
    private boolean waitingRoom1Entry = false;

    private boolean waitingRoom2Exit = false;
    private boolean waitingRoom2Entry = false;

    /**
     * Consulta el último estado conocido de los sensores de movimiento.
     *
     * @return el estado actual de los sensores de movimiento.
     */
    public MotionState getMotion() {
        return motion;
    }

    /**
     * Procesa una nueva lectura de los sensores de movimiento, actualiza el
     * estado y, si corresponde según el modo automático, enciende o apaga
     * las luces de las salas mediante {@link LedService}.
     *
     * @param request nueva lectura enviada por el ESP32.
     */
    public void updateMotion(MotionRequest request) {

        motion.setRoom1Entry(request.isRoom1Entry());
        motion.setRoom1Exit(request.isRoom1Exit());

        motion.setRoom2Entry(request.isRoom2Entry());
        motion.setRoom2Exit(request.isRoom2Exit());

        // Verificar el modo automático global antes que nada
        if (!automaticModeService.isAutomaticMode()) {

            updateLastStates(request);

            return;

        }

        // Si el usuario está en modo manual para las luces,
        // ignoramos completamente los sensores.

        if (!ledService.getLed().isAutomatic()) {

            updateLastStates(request);

            return;

        }

        processRoom1(request);

        processRoom2(request);

        updateLastStates(request);

    }

    private void processRoom1(MotionRequest request) {

        // Entrada

        if (!lastRoom1Entry && request.isRoom1Entry()) {

            waitingRoom1Exit = true;

        }

        // Entrada -> Salida

        if (waitingRoom1Exit &&
                !lastRoom1Exit &&
                request.isRoom1Exit()) {

            ledService.setRoom1Led(true);

            waitingRoom1Exit = false;

        }

        // Salida

        if (!lastRoom1Exit && request.isRoom1Exit()) {

            waitingRoom1Entry = true;

        }

        // Salida -> Entrada

        if (waitingRoom1Entry &&
                !lastRoom1Entry &&
                request.isRoom1Entry()) {

            ledService.setRoom1Led(false);

            waitingRoom1Entry = false;

        }

    }

    private void processRoom2(MotionRequest request) {

        if (!lastRoom2Entry && request.isRoom2Entry()) {

            waitingRoom2Exit = true;

        }

        if (waitingRoom2Exit &&
                !lastRoom2Exit &&
                request.isRoom2Exit()) {

            ledService.setRoom2Led(true);

            waitingRoom2Exit = false;

        }

        if (!lastRoom2Exit && request.isRoom2Exit()) {

            waitingRoom2Entry = true;

        }

        if (waitingRoom2Entry &&
                !lastRoom2Entry &&
                request.isRoom2Entry()) {

            ledService.setRoom2Led(false);

            waitingRoom2Entry = false;

        }

    }

    private void updateLastStates(MotionRequest request) {

        lastRoom1Entry = request.isRoom1Entry();
        lastRoom1Exit = request.isRoom1Exit();

        lastRoom2Entry = request.isRoom2Entry();
        lastRoom2Exit = request.isRoom2Exit();

    }

}