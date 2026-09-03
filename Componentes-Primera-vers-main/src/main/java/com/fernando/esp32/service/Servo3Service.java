package com.fernando.esp32.service;

import com.fernando.esp32.model.Servo3State;
import org.springframework.stereotype.Service;

/**
 * Mantiene en memoria el estado del servomotor que orienta la cámara y
 * registra en la base de datos cada cambio de ángulo como comando de
 * actuador, igual que hacen {@link ServoService} y {@link Servo2Service}.
 */
@Service
public class Servo3Service {

    /** Identificador del dispositivo en la tabla {@code dispositivo} (columna {@code mac_address}). */
    private static final String DISPOSITIVO = "SERVO_CAMARA";

    private final Servo3State servo = new Servo3State();
    private final IotDatabaseService dbService;

    public Servo3Service(IotDatabaseService dbService) {
        this.dbService = dbService;
    }

    /**
     * Consulta el estado actual del servomotor de la cámara.
     *
     * @return el estado actual del servo.
     */
    public Servo3State getServo() {
        return servo;
    }

    /**
     * Reorienta la cámara al ángulo indicado y deja registrado el movimiento.
     * Solo escribe en la base de datos cuando el ángulo cambia de verdad, para
     * no llenar el historial con movimientos repetidos al mismo punto.
     *
     * @param angle ángulo destino; {@link Servo3State} lo recorta a 0–180.
     */
    public void updateAngle(int angle) {
        int anterior = servo.getAngle();
        servo.setAngle(angle);

        if (servo.getAngle() != anterior) {
            // El comando se marca como activación cuando la cámara se mueve
            // fuera de su posición de reposo.
            dbService.registrarComando(DISPOSITIVO, servo.getAngle() != 0);
            System.out.println("🎥 Servo 3 (Cámara) movido a: " + servo.getAngle() + "°");
        }
    }
}
