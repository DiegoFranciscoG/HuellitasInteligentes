package com.huellitas.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Expone como recursos web estáticos los archivos guardados localmente en la
 * carpeta {@code uploads} (por ejemplo, imágenes subidas antes de migrar a
 * almacenamiento en la nube), accesibles bajo la ruta {@code /uploads/**}.
 */
@Configuration
public class WebConfig implements WebMvcConfigurer {

    /**
     * Registra el mapeo entre la ruta pública {@code /uploads/**} y la carpeta local {@code uploads}.
     *
     * @param registry registro de manejadores de recursos de Spring MVC.
     */
    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        Path uploadDir = Paths.get("uploads");
        String uploadPath = uploadDir.toFile().getAbsolutePath();
        registry.addResourceHandler("/uploads/**")
                .addResourceLocations("file:/" + uploadPath + "/");
    }
}
