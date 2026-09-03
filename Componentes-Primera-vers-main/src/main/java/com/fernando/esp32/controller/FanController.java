package com.fernando.esp32.controller;

import com.fernando.esp32.model.FanRequest;
import com.fernando.esp32.model.FanState;
import com.fernando.esp32.service.FanService;
import org.springframework.web.bind.annotation.*;

/**
 * Controla el ventilador del sistema IoT, usado para regular la temperatura
 * ambiente de la mascota.
 */
@RestController
@RequestMapping("/api/fan")
@CrossOrigin
public class FanController {

    private final FanService service;

    public FanController(FanService service) {
        this.service = service;
    }

    /**
     * Consulta el estado actual del ventilador.
     *
     * @return el estado (encendido/apagado, velocidad, etc.) del ventilador.
     */
    @GetMapping
    public FanState getFan() {

        return service.getFan();

    }

    /**
     * Actualiza el estado del ventilador (por ejemplo, encenderlo o apagarlo).
     *
     * @param request nuevo estado deseado para el ventilador.
     * @return el estado del ventilador luego de aplicar el cambio.
     */
    @PostMapping
    public FanState updateFan(
            @RequestBody FanRequest request) {

        service.updateFan(request);

        return service.getFan();

    }

}