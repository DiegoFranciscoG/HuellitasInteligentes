package com.fernando.esp32.controller;

import com.fernando.esp32.model.DeviceState;
import com.fernando.esp32.service.*;

import org.springframework.web.bind.annotation.*;

/**
 * Punto de entrada agregado que consulta en una sola llamada el estado de
 * todos los dispositivos y sensores del ESP32 (servos, bomba, ventilador,
 * sensores ambientales, etc.), útil para pantallas de resumen en la web y la app.
 */
@RestController
@RequestMapping("/api/devices")
@CrossOrigin
public class DeviceController {

    private final ServoService servoService;
    private final Servo2Service servo2Service;
    private final Servo3Service servo3Service;
    private final StepperService stepperService;
    private final PumpService pumpService;
    private final MotionService motionService;
    private final LedService ledService;
    private final FanService fanService;
    private final DhtService dhtService;
    private final Mq135Service mq135Service;
    private final WaterLevelService waterLevelService;
    private final UltrasonicService ultrasonicService;
    private final AutomaticModeService automaticModeService;

    public DeviceController(
            ServoService servoService,
            Servo2Service servo2Service,
            Servo3Service servo3Service,
            StepperService stepperService,
            PumpService pumpService,
            MotionService motionService,
            LedService ledService,
            FanService fanService,
            DhtService dhtService,
            Mq135Service mq135Service,
            WaterLevelService waterLevelService,
            UltrasonicService ultrasonicService,
            AutomaticModeService automaticModeService) {

        this.servoService = servoService;
        this.servo2Service = servo2Service;
        this.servo3Service = servo3Service;
        this.stepperService = stepperService;
        this.pumpService = pumpService;
        this.motionService = motionService;
        this.ledService = ledService;
        this.fanService = fanService;
        this.dhtService = dhtService;
        this.mq135Service = mq135Service;
        this.waterLevelService = waterLevelService;
        this.ultrasonicService = ultrasonicService;
        this.automaticModeService = automaticModeService;

    }

    /**
     * Reúne el estado actual de todos los dispositivos controlados por el ESP32
     * (servos, motor paso a paso, bomba, sensor de movimiento, LED, ventilador,
     * DHT, MQ135, nivel de agua, ultrasónico) más el estado del modo automático.
     *
     * @return una instantánea consolidada con el estado de todos los dispositivos.
     */
    @GetMapping
    public DeviceState getDevices() {

        DeviceState state = new DeviceState(

                servoService.getServo(),

                servo2Service.getServo(),

                servo3Service.getServo(),

                stepperService.getStepper(),

                pumpService.getPump(),

                motionService.getMotion(),

                ledService.getLed(),

                fanService.getFan(),

                dhtService.getDht(),

                mq135Service.getMq135(),

                waterLevelService.getWater(),

                ultrasonicService.getUltrasonic()

        );
        state.setAutomaticMode(automaticModeService.isAutomaticMode());
        return state;

    }

}