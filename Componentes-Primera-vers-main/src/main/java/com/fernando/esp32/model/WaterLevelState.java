package com.fernando.esp32.model;

/**
 * Estado actual (nivel) del agua en el bebedero automático.
 */
public class WaterLevelState {

    private int level;

    public WaterLevelState() {
    }

    public WaterLevelState(int level) {
        this.level = level;
    }

    public int getLevel() {
        return level;
    }

    public void setLevel(int level) {
        this.level = level;
    }

}