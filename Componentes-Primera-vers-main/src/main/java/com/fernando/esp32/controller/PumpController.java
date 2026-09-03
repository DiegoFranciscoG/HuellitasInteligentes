package com.fernando.esp32.controller;

import com.fernando.esp32.model.PumpRequest;
import com.fernando.esp32.model.PumpState;
import com.fernando.esp32.service.PumpService;
import org.springframework.web.bind.annotation.*;

/**
 * Controla la bomba de agua del sistema IoT, encargada de rellenar el
 * bebedero automático de la mascota.
 */
@RestController
@RequestMapping("/api/pump")
@CrossOrigin
public class PumpController {

    private final PumpService pumpService;

    public PumpController(PumpService pumpService) {
        this.pumpService = pumpService;
    }

    /**
     * Consulta el estado actual de la bomba de agua.
     *
     * @return el estado (encendida/apagada) de la bomba.
     */
    @GetMapping
    public PumpState getPump() {
        return pumpService.getPump();
    }

    /**
     * Enciende o apaga la bomba de agua.
     *
     * @param request indica si la bomba debe quedar habilitada o no.
     * @return el estado de la bomba luego de aplicar el cambio.
     */
    @PostMapping
    public PumpState updatePump(@RequestBody PumpRequest request) {

        pumpService.updatePump(request.isEnabled());

        return pumpService.getPump();

    }

}