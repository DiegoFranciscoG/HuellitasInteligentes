package com.huellitas.config;

import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

/**
 * Este módulo se encarga de escanear todos los componentes del paquete com.huellitas.
 * Esto es necesario porque la clase principal de la aplicación (@SpringBootApplication)
 * está en el paquete com.fernando.esp32, el cual no escanea paquetes hermanos por defecto.
 * 
 * Gracias a META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports,
 * Spring Boot cargará esta clase automáticamente al iniciar, inyectando todo el backend
 * de Huellitas (incluyendo SecurityConfig) sin modificar el código del ESP32.
 */
@Configuration
@ComponentScan(basePackages = "com.huellitas")
@EntityScan(basePackages = {"com.fernando.esp32", "com.huellitas"})
@EnableJpaRepositories(basePackages = {"com.fernando.esp32", "com.huellitas"})
public class HuellitasModuleConfig {
}
