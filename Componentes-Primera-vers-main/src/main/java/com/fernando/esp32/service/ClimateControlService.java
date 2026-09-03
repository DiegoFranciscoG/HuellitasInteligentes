package com.fernando.esp32.service;

import com.fernando.esp32.model.*;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * Automatiza el control climático de las dos salas monitoreadas: revisa
 * periódicamente temperatura, humedad y calidad del aire, y enciende
 * ventiladores o abre las ventanas (servos) cuando se superan los umbrales
 * configurados, evitando repetir la misma acción si el estado no cambió.
 */
@Service
public class ClimateControlService {

    private final DhtService dhtService;
    private final Mq135Service mq135Service;
    private final FanService fanService;
    private final ServoService servoService;    // Ventana Sala 1
    private final Servo2Service servo2Service;  // Ventana Sala 2
    private final AutomaticModeService automaticModeService;

    // Umbrales de temperatura y humedad
    private static final float TEMP_THRESHOLD = 28.0f;     // °C
    private static final float HUMIDITY_THRESHOLD = 70.0f; // %
    private static final int AIR_QUALITY_THRESHOLD = 2000; // Valor MQ135

    // Estados anteriores para evitar cambios innecesarios
    private boolean lastFan1State = false;
    private boolean lastFan2State = false;
    private boolean lastWindow1Open = false;
    private boolean lastWindow2Open = false;

    public ClimateControlService(DhtService dhtService,
                                  Mq135Service mq135Service,
                                  FanService fanService,
                                  ServoService servoService,
                                  Servo2Service servo2Service,
                                  AutomaticModeService automaticModeService) {
        this.dhtService = dhtService;
        this.mq135Service = mq135Service;
        this.fanService = fanService;
        this.servoService = servoService;
        this.servo2Service = servo2Service;
        this.automaticModeService = automaticModeService;
    }

    /**
     * Se ejecuta cada 5 segundos para verificar condiciones ambientales
     * y activar/desactivar ventiladores y ventanas automáticamente
     */
    @Scheduled(fixedRate = 5000)
    public void checkClimateConditions() {

        // Solo actuar si el modo automático global está activado
        if (!automaticModeService.isAutomaticMode()) {
            return;
        }

        DhtState dht = dhtService.getDht();
        Mq135State mq135 = mq135Service.getMq135();

        // =============================================
        // PROCESAR SALA 1 (Descanso y Confort)
        // =============================================
        processRoom1(dht, mq135);

        // =============================================
        // PROCESAR SALA 2 (Alimentación)
        // =============================================
        processRoom2(dht, mq135);
    }

    private void processRoom1(DhtState dht, Mq135State mq135) {
        
        boolean needVentilation = false;

        // Verificar temperatura Sala 1
        if (dht.getTemperature1() > TEMP_THRESHOLD) {
            needVentilation = true;
            System.out.println("⚠️ Sala 1: Temperatura alta detectada: " + 
                             dht.getTemperature1() + "°C");
        }

        // Verificar humedad Sala 1
        if (dht.getHumidity1() > HUMIDITY_THRESHOLD) {
            needVentilation = true;
            System.out.println("⚠️ Sala 1: Humedad alta detectada: " + 
                             dht.getHumidity1() + "%");
        }

        // Verificar calidad del aire Sala 1
        if (mq135.getAirQuality1() > AIR_QUALITY_THRESHOLD) {
            needVentilation = true;
            System.out.println("⚠️ Sala 1: Calidad de aire deficiente: " + 
                             mq135.getAirQuality1());
        }

        // Activar/desactivar ventilador 1
        if (needVentilation && !lastFan1State) {
            fanService.getFan().setFan1(true);
            lastFan1State = true;
            System.out.println("✅ Ventilador Sala 1 ENCENDIDO (Automático)");
        } else if (!needVentilation && lastFan1State) {
            fanService.getFan().setFan1(false);
            lastFan1State = false;
            System.out.println("✅ Ventilador Sala 1 APAGADO (Automático)");
        }

        // Activar/desactivar ventana Sala 1 (Servo 1)
        if (needVentilation && !lastWindow1Open) {
            servoService.updateAngle(180); // Abrir ventana
            lastWindow1Open = true;
            System.out.println("✅ Ventana Sala 1 ABIERTA (Automático)");
        } else if (!needVentilation && lastWindow1Open) {
            servoService.updateAngle(0); // Cerrar ventana
            lastWindow1Open = false;
            System.out.println("✅ Ventana Sala 1 CERRADA (Automático)");
        }
    }

    private void processRoom2(DhtState dht, Mq135State mq135) {
        
        boolean needVentilation = false;

        // Verificar temperatura Sala 2
        if (dht.getTemperature2() > TEMP_THRESHOLD) {
            needVentilation = true;
            System.out.println("⚠️ Sala 2: Temperatura alta detectada: " + 
                             dht.getTemperature2() + "°C");
        }

        // Verificar humedad Sala 2
        if (dht.getHumidity2() > HUMIDITY_THRESHOLD) {
            needVentilation = true;
            System.out.println("⚠️ Sala 2: Humedad alta detectada: " + 
                             dht.getHumidity2() + "%");
        }

        // Verificar calidad del aire Sala 2
        if (mq135.getAirQuality2() > AIR_QUALITY_THRESHOLD) {
            needVentilation = true;
            System.out.println("⚠️ Sala 2: Calidad de aire deficiente: " + 
                             mq135.getAirQuality2());
        }

        // Activar/desactivar ventilador 2
        if (needVentilation && !lastFan2State) {
            fanService.getFan().setFan2(true);
            lastFan2State = true;
            System.out.println("✅ Ventilador Sala 2 ENCENDIDO (Automático)");
        } else if (!needVentilation && lastFan2State) {
            fanService.getFan().setFan2(false);
            lastFan2State = false;
            System.out.println("✅ Ventilador Sala 2 APAGADO (Automático)");
        }

        // Activar/desactivar ventana Sala 2 (Servo 2)
        if (needVentilation && !lastWindow2Open) {
            servo2Service.getServo().setAngle(180); // Abrir ventana
            lastWindow2Open = true;
            System.out.println("✅ Ventana Sala 2 ABIERTA (Automático)");
        } else if (!needVentilation && lastWindow2Open) {
            servo2Service.getServo().setAngle(0); // Cerrar ventana
            lastWindow2Open = false;
            System.out.println("✅ Ventana Sala 2 CERRADA (Automático)");
        }
    }
}