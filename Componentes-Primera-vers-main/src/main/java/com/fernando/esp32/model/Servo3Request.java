package com.fernando.esp32.model;

/**
 * Petición para reorientar la cámara: lleva el ángulo destino del tercer
 * servomotor.
 */
public class Servo3Request {

    private int angle;

    public Servo3Request() {
    }

    /**
     * Consulta el ángulo pedido por el cliente.
     *
     * @return el ángulo destino, sin recortar; el recorte lo hace {@link Servo3State}.
     */
    public int getAngle() {
        return angle;
    }

    public void setAngle(int angle) {
        this.angle = angle;
    }
}
