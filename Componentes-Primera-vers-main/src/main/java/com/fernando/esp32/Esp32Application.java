package com.fernando.esp32;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Punto de arranque del módulo Spring Boot que integra el sistema con el
 * hardware ESP32: expone los endpoints REST usados por el firmware para
 * reportar lecturas de sensores y recibir órdenes para los actuadores
 * (bomba, servos, ventiladores, LEDs, etc.), y habilita las tareas
 * programadas y asíncronas que implementan el modo automático de cuidado
 * de la mascota (clima y alimentación).
 */
@SpringBootApplication
@EnableScheduling
@EnableAsync
public class Esp32Application {

    /**
     * Arranca el contexto de Spring Boot de este módulo.
     *
     * @param args argumentos de línea de comandos.
     */
    public static void main(String[] args) {
        SpringApplication.run(Esp32Application.class, args);
    }

}