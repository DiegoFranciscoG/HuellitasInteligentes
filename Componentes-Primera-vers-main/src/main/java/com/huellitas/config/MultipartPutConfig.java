package com.huellitas.config;

import org.apache.catalina.connector.Connector;
import org.springframework.boot.web.embedded.tomcat.TomcatServletWebServerFactory;
import org.springframework.boot.web.server.WebServerFactoryCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Tomcat solo analiza cuerpos multipart en peticiones POST por defecto
 * (parseBodyMethods = "POST"). Varios endpoints de la app suben archivos por
 * PUT — actualizar foto de perfil (PUT /auth/perfil) y editar mascota
 * (PUT /perro/{id}) — y en esos casos el archivo y los @RequestParam llegaban
 * vacíos, provocando "Error al actualizar perfil" y que las fotos nunca se
 * sincronizaran entre la web y la app.
 *
 * Habilitar PUT aquí arregla ambas plataformas de una sola vez, sin tener que
 * cambiar el contrato de la API ni el código de los clientes.
 */
@Configuration
public class MultipartPutConfig {

    /**
     * Registra el ajuste que habilita a Tomcat a analizar cuerpos multipart
     * también en peticiones PUT y PATCH, no solo POST.
     *
     * @return el personalizador del conector Tomcat.
     */
    @Bean
    public WebServerFactoryCustomizer<TomcatServletWebServerFactory> allowMultipartOnPut() {
        return factory -> factory.addConnectorCustomizers(this::enablePutBodyParsing);
    }

    /**
     * Amplía los métodos HTTP para los que Tomcat procesa el cuerpo de la petición.
     *
     * @param connector conector Tomcat a configurar.
     */
    private void enablePutBodyParsing(Connector connector) {
        connector.setParseBodyMethods("POST,PUT,PATCH");
    }
}
