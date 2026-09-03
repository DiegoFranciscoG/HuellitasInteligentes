package com.fernando.esp32.model;

/**
 * Último estado conocido de los sensores de movimiento (PIR) de cada habitación.
 */
public class MotionState {

    private boolean room1Entry;
    private boolean room1Exit;

    private boolean room2Entry;
    private boolean room2Exit;

    public MotionState() {
    }

    public boolean isRoom1Entry() {
        return room1Entry;
    }

    public void setRoom1Entry(boolean room1Entry) {
        this.room1Entry = room1Entry;
    }

    public boolean isRoom1Exit() {
        return room1Exit;
    }

    public void setRoom1Exit(boolean room1Exit) {
        this.room1Exit = room1Exit;
    }

    public boolean isRoom2Entry() {
        return room2Entry;
    }

    public void setRoom2Entry(boolean room2Entry) {
        this.room2Entry = room2Entry;
    }

    public boolean isRoom2Exit() {
        return room2Exit;
    }

    public void setRoom2Exit(boolean room2Exit) {
        this.room2Exit = room2Exit;
    }

}