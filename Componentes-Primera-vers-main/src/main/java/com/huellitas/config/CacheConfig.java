package com.huellitas.config;

import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.concurrent.ConcurrentMapCacheManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Habilita el caché en memoria del sistema, usado para evitar consultar la
 * base de datos en cada solicitud de los planes de suscripción activos
 * (caché {@code planesActivos}), que cambian con poca frecuencia.
 */
@Configuration
@EnableCaching
public class CacheConfig {

    /**
     * Define el administrador de caché en memoria del sistema, con la región {@code planesActivos}.
     *
     * @return el administrador de caché configurado.
     */
    @Bean
    public CacheManager cacheManager() {
        return new ConcurrentMapCacheManager("planesActivos");
    }
}
