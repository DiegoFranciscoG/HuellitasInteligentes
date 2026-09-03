package com.fernando.esp32.service;

import com.fernando.esp32.model.Servo2Request;
import com.fernando.esp32.model.Servo2State;
import org.springframework.stereotype.Service;

/**
 * Mantiene en memoria el estado del segundo servomotor (ventana de la sala 2)
 * y registra en la base de datos los cambios de ángulo como comandos de actuador.
 */
@Service
public class Servo2Service {

    private final Servo2State servo2 = new Servo2State();
    private final IotDatabaseService dbService;

    public Servo2Service(IotDatabaseService dbService) {
        this.dbService = dbService;
    }

    /**
     * Consulta el estado actual del segundo servomotor.
     *
     * @return el estado actual del servo.
     */
    public Servo2State getServo() {
        return servo2;
    }

    /**
     * Actualiza el ángulo del segundo servomotor, acotándolo al rango válido
     * de 0 a 180 grados, y registra en la base de datos el cambio respecto
     * al ángulo anterior.
     *
     * @param request contiene el ángulo deseado para el servo.
     */
    public void updateServo(Servo2Request request) {

        int angle = request.getAngle();

        if(angle < 0)
            angle = 0;

        if(angle > 180)
            angle = 180;

        if (servo2.getAngle() != request.getAngle()) {
            dbService.registrarComando("SERVO_ROOM2", request.getAngle() == 0); // 0 = abrir/activar
        }
        servo2.setAngle(angle);

    }

    // AGREGAR ESTE MÉTODO NUEVO
    /**
     * Actualiza el ángulo del segundo servomotor directamente (sin pasar por
     * un {@link Servo2Request}), acotándolo al rango válido de 0 a 180
     * grados, y registra en la base de datos el cambio respecto al ángulo anterior.
     *
     * @param angle nuevo ángulo deseado para el servo.
     */
    public void updateAngle(int angle) {
        if(angle < 0)
            angle = 0;
        if(angle > 180)
            angle = 180;
            
        if (servo2.getAngle() != angle) {
            dbService.registrarComando("SERVO_ROOM2", angle == 0);
        }
        servo2.setAngle(angle);
    }

}