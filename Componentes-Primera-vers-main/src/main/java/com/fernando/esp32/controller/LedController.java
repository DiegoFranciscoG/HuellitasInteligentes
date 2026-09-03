package com.fernando.esp32.controller;

import com.fernando.esp32.model.LedRequest;
import com.fernando.esp32.model.LedState;
import com.fernando.esp32.service.LedService;
import org.springframework.web.bind.annotation.*;

/**
 * Controla el LED indicador del dispositivo ESP32 (por ejemplo, para señales
 * visuales de estado hacia el dueño de la mascota).
 */
@RestController
@RequestMapping("/api/led")
@CrossOrigin
public class LedController {

    private final LedService ledService;
    private final org.springframework.jdbc.core.JdbcTemplate jdbcTemplate;

    public LedController(LedService ledService, org.springframework.jdbc.core.JdbcTemplate jdbcTemplate) {
        this.ledService = ledService;
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * Consulta el estado actual del LED.
     *
     * @return el estado (encendido/apagado) del LED.
     */
    @GetMapping
    public LedState getLed() {

        return ledService.getLed();

    }

    /**
     * Actualiza el estado del LED.
     *
     * @param request nuevo estado deseado para el LED.
     * @return el estado del LED luego de aplicar el cambio.
     */
    @PostMapping
    public LedState updateLed(@RequestBody LedRequest request) {

        ledService.updateLed(request);

        return ledService.getLed();

    }
}