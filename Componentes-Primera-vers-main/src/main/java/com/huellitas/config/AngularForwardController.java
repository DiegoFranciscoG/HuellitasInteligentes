package com.huellitas.config;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;

@Controller
public class AngularForwardController {

    // Redirige cualquier peticion que no sea /api/... ni /actuator/... hacia index.html
    // Esto es necesario para que Angular (SPA) pueda manejar las rutas del frontend.
    @RequestMapping(value = {
            "/",
            "/{path:[^\\.]*}",
            "/**/{path:[^\\.]*}"
    })
    public String forward() {
        return "forward:/index.html";
    }
}
