package com.fernando.esp32.service;

import com.fernando.esp32.model.*;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * Automatiza la alimentación de la mascota: revisa periódicamente el nivel
 * de comida (sensor ultrasónico) y de agua (sensor de nivel), y dispensa
 * automáticamente usando el motor paso a paso o la bomba de agua cuando
 * detecta niveles bajos, respetando un tiempo de espera entre dispensados.
 */
@Service
public class FeedingService {

    private final UltrasonicService ultrasonicService;
    private final WaterLevelService waterLevelService;
    private final StepperService stepperService;
    private final PumpService pumpService;
    private final AutomaticModeService automaticModeService;

    // Umbrales de comida. Son dos y no uno: con un solo umbral, una lectura
    // que oscila justo en el borde enciende y apaga el dispensador en ciclo.
    // Se dispensa al superar el de "vacío" y no se vuelve a armar hasta bajar
    // del de "lleno".
    private static final double FOOD_EMPTY_THRESHOLD = 15.5; // cm — plato vacío (distancia grande)
    private static final double FOOD_FULL_THRESHOLD = 13.0;  // cm — plato lleno (distancia corta)
    private static final long DISPENSE_FOOD_DURATION = 3000; // 3 segundos girando

    // Umbrales de agua
    private static final int WATER_LOW_THRESHOLD = 1000;      // Valor analógico bajo = poca agua
    private static final long DISPENSE_WATER_DURATION = 3000; // 3 segundos de bomba

    // Estados anteriores
    private boolean lastDispensingFood = false;
    private boolean lastDispensingWater = false;

    // Tiempo de dispensado
    private static final long DISPENSE_COOLDOWN = 30000; // 30 segundos entre dispensados
    private long lastFoodDispenseTime = 0;
    private long lastWaterDispenseTime = 0;

    public FeedingService(UltrasonicService ultrasonicService,
                           WaterLevelService waterLevelService,
                           StepperService stepperService,
                           PumpService pumpService,
                           AutomaticModeService automaticModeService) {
        this.ultrasonicService = ultrasonicService;
        this.waterLevelService = waterLevelService;
        this.stepperService = stepperService;
        this.pumpService = pumpService;
        this.automaticModeService = automaticModeService;
    }

    /**
     * Verifica cada 10 segundos los niveles de comida y agua
     */
    @Scheduled(fixedRate = 10000)
    public void checkFeedingLevels() {

        // Verificar el modo global ANTES de hacer cualquier cosa
        if (!automaticModeService.isAutomaticMode()) {
            return;
        }

        checkFoodLevel();
        checkWaterLevel();
    }

    /**
     * Verifica el nivel de comida usando el sensor ultrasónico, con dos
     * umbrales para evitar que el dispensador oscile cuando la lectura queda
     * justo en el borde.
     */
    private void checkFoodLevel() {

        UltrasonicState ultrasonic = ultrasonicService.getUltrasonic();
        double distance = ultrasonic.getDistance();

        // Distancia grande significa plato vacío.
        if (distance > FOOD_EMPTY_THRESHOLD && !lastDispensingFood) {

            // Verificar cooldown
            long currentTime = System.currentTimeMillis();
            if (currentTime - lastFoodDispenseTime < DISPENSE_COOLDOWN) {
                return; // Esperar cooldown
            }

            System.out.println("⚠️ Nivel de comida BAJO (VACÍO). Distancia: " + distance + "cm");
            System.out.println("🍖 Activando dispensador de alimento...");

            // Activar motor paso a paso para dispensar comida
            dispenseFood();

            lastFoodDispenseTime = currentTime;
            lastDispensingFood = true;

        } else if (distance <= FOOD_FULL_THRESHOLD && lastDispensingFood) {
            // Solo se rearma al llegar al umbral de lleno, no al de vacío.
            lastDispensingFood = false;
            System.out.println("✅ Nivel de comida RESTABLECIDO (LLENO). Distancia: " + distance + "cm");
        }
    }

    /**
     * Verifica el nivel de agua
     */
    private void checkWaterLevel() {
        
        WaterLevelState water = waterLevelService.getWater();
        int waterLevel = water.getLevel();

        // Si el nivel de agua es bajo (valor analógico bajo)
        if (waterLevel < WATER_LOW_THRESHOLD && !lastDispensingWater) {
            
            // Verificar cooldown
            long currentTime = System.currentTimeMillis();
            if (currentTime - lastWaterDispenseTime < DISPENSE_COOLDOWN) {
                return; // Esperar cooldown
            }

            System.out.println("⚠️ Nivel de agua BAJO. Valor: " + waterLevel);
            System.out.println("💧 Activando bomba de agua...");

            // Activar bomba de agua
            dispenseWater();
            
            lastWaterDispenseTime = currentTime;
            lastDispensingWater = true;
            
        } else if (waterLevel >= WATER_LOW_THRESHOLD && lastDispensingWater) {
            lastDispensingWater = false;
            System.out.println("✅ Nivel de agua RESTABLECIDO");
        }
    }

    /**
     * Dispensa comida llevando el motor paso a paso hasta el final de su
     * recorrido y devolviéndolo al reposo pasados unos segundos. El destino
     * es {@link StepperState#MAX_POSITION}, el mismo tope que el modelo
     * aplica al recortar, para que la lógica y el límite físico no se
     * contradigan.
     */
    private void dispenseFood() {

        StepperState stepper = stepperService.getStepper();
        int currentPosition = stepper.getPosition();

        // Si ya está al final del recorrido, no hay nada que mover.
        if (currentPosition >= StepperState.MAX_POSITION) {
            System.out.println("ℹ️ Dispensador ya en posición máxima: " + currentPosition);
            return;
        }

        stepperService.updatePosition(StepperState.MAX_POSITION);
        System.out.println("🍖 Dispensador movido a posición: " + StepperState.MAX_POSITION);

        // Programar retorno a posición inicial
        new Thread(() -> {
            try {
                Thread.sleep(DISPENSE_FOOD_DURATION);
                stepperService.updatePosition(0);
                System.out.println("🍖 Dispensador regresado a posición inicial");
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }).start();
    }

    /**
     * Dispensa agua activando la bomba por 3 segundos
     */
    private void dispenseWater() {
        
        pumpService.updatePump(true);
        System.out.println("💧 Bomba de agua ENCENDIDA");
        
        // Programar apagado después del tiempo de dispensado
        new Thread(() -> {
            try {
                Thread.sleep(DISPENSE_WATER_DURATION);
                pumpService.updatePump(false);
                System.out.println("💧 Bomba de agua APAGADA");
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }).start();
    }
}