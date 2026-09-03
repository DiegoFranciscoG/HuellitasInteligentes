package com.huellitas.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Metadatos de la documentación interactiva de la API, disponible en {@code /swagger-ui.html}. */
@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI huellitasOpenApi() {
        return new OpenAPI().info(new Info()
            .title("Huellitas Inteligentes — API")
            .description("API del backend de monitoreo de mascotas: dispositivos IoT, red social con moderación por IA, entrenamiento RAG y panel de administración.")
            .version("v1"));
    }
}
