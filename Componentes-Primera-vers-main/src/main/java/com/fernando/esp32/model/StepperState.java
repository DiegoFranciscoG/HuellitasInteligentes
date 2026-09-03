package com.fernando.esp32.model;

/**
 * Estado actual (posición) del motor paso a paso del dispensador de alimento.
 * La posición se recorta al recorrido físico del mecanismo, de modo que una
 * petición fuera de rango no lo fuerce contra su tope.
 */
public class StepperState {

    /** Recorrido máximo del dispensador, en pasos. */
    public static final int MAX_POSITION = 200;

    private int position = 0;

    public StepperState() {
    }

    /**
     * Consulta la posición actual del dispensador.
     *
     * @return la posición, siempre entre 0 y {@link #MAX_POSITION}.
     */
    public int getPosition() {
        return position;
    }

    /**
     * Expone el recorrido máximo en la respuesta de la API para que la web y
     * la aplicación no tengan que llevar el número repetido por su cuenta: si
     * el recorrido del dispensador cambia, cambia en un solo sitio.
     *
     * @return el tope de pasos admitido por el mecanismo.
     */
    public int getMaxPosition() {
        return MAX_POSITION;
    }

    /**
     * Mueve el dispensador a la posición indicada, recortándola al recorrido
     * admitido.
     *
     * @param position posición deseada; por debajo de 0 se guarda 0 y por encima de {@link #MAX_POSITION} se guarda ese máximo.
     */
    public void setPosition(int position) {
        if (position < 0) {
            this.position = 0;
        } else if (position > MAX_POSITION) {
            this.position = MAX_POSITION;
        } else {
            this.position = position;
        }
    }

}