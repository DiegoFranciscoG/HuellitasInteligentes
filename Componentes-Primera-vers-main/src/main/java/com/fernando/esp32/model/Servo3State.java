package com.fernando.esp32.model;

/**
 * Estado actual del tercer servomotor, el que orienta la cámara de la
 * vivienda. El ángulo se recorta entre 0 y 180 grados dentro del propio
 * {@code setter}, para que un valor fuera de rango no fuerce al servo contra
 * su tope físico.
 */
public class Servo3State {

    /** Ángulo inicial. Es el valor con el que se montó y probó el hardware. */
    private int angle = 0;
    private String status = "OK";

    public Servo3State() {
    }

    public Servo3State(int angle) {
        setAngle(angle);
        this.status = "OK";
    }

    /**
     * Consulta el ángulo actual de la cámara.
     *
     * @return el ángulo, siempre entre 0 y 180.
     */
    public int getAngle() {
        return angle;
    }

    /**
     * Fija el ángulo de la cámara, recortándolo al rango admitido por el servo.
     *
     * @param angle ángulo deseado; por debajo de 0 se guarda 0 y por encima de 180 se guarda 180.
     */
    public void setAngle(int angle) {
        if (angle < 0) {
            angle = 0;
        }
        if (angle > 180) {
            angle = 180;
        }
        this.angle = angle;
    }

    /**
     * Consulta el estado reportado por el servo.
     *
     * @return la etiqueta de estado, {@code "OK"} mientras no haya fallo.
     */
    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }
}
