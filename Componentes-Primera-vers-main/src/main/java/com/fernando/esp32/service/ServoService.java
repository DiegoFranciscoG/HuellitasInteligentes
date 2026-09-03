package com.fernando.esp32.service;

import com.fernando.esp32.model.ServoState;
import org.springframework.stereotype.Service;

/**
 * Mantiene en memoria el estado del servomotor principal (ventana de la sala 1)
 * y registra en la base de datos los cambios de ángulo como comandos de actuador.
 */
@Service
public class ServoService {

    private final ServoState servo = new ServoState();
    private final IotDatabaseService dbService;

    public ServoService(IotDatabaseService dbService) {
        this.dbService = dbService;
    }

    /**
     * Consulta el estado actual del servomotor principal.
     *
     * @return el estado actual del servo.
     */
    public ServoState getServo() {
        return servo;
    }

    /**
     * Actualiza el ángulo del servomotor principal y registra en la base de
     * datos el cambio respecto al ángulo anterior.
     *
     * @param angle nuevo ángulo deseado para el servo.
     */
    public void updateAngle(int angle) {
        if (servo.getAngle() != angle) {
            dbService.registrarComando("SERVO_ROOM1", angle == 0); // 0 = abrir/activar
        }
        servo.setAngle(angle);
    }
}