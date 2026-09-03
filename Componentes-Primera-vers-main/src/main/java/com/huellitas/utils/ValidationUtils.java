package com.huellitas.utils;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.util.regex.Pattern;

/**
 * Reglas de validación y formateo compartidas por los distintos
 * controladores (nombres de personas y entidades, correos electrónicos,
 * contraseñas), usadas para rechazar datos inválidos o de spam antes de
 * llegar a la base de datos.
 */
public class ValidationUtils {

    private static final Pattern PATRON_NOMBRE_PERSONA = Pattern.compile("^[a-zA-ZáéíóúÁÉÍÓÚñÑ\\s]{2,60}$");
    private static final Pattern PATRON_EMAIL = Pattern.compile("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,6}$");

    /**
     * Valida y formatea un nombre de persona.
     * Capitaliza la primera letra de cada palabra y la convierte a minúscula el resto.
     * Lanza error si contiene números o símbolos raros, o si tiene < 2 caracteres.
     */
    public static String formatearYValidarNombrePersona(String nombre) {
        if (nombre == null || nombre.trim().isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El nombre no puede estar vacío");
        }
        
        String nombreLimpio = nombre.trim().replaceAll("\\s+", " ");
        
        if (!PATRON_NOMBRE_PERSONA.matcher(nombreLimpio).matches()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El nombre debe contener solo letras y tener al menos 2 caracteres");
        }

        // Capitalizar (Title Case)
        String[] palabras = nombreLimpio.split(" ");
        StringBuilder nombreFormateado = new StringBuilder();
        for (String palabra : palabras) {
            if (!palabra.isEmpty()) {
                nombreFormateado.append(Character.toUpperCase(palabra.charAt(0)))
                                .append(palabra.substring(1).toLowerCase())
                                .append(" ");
            }
        }
        return nombreFormateado.toString().trim();
    }

    /**
     * Valida un nombre de entidad (Grupo, Casa, Mascota).
     * Asegura que tenga al menos 2 caracteres alfanuméricos.
     */
    public static String validarNombreEntidad(String nombre) {
        if (nombre == null || nombre.trim().isEmpty()) {
            throw new IllegalArgumentException("El nombre no puede estar vacío");
        }
        
        String nombreLimpio = nombre.trim();
        if (nombreLimpio.length() < 4) {
            throw new IllegalArgumentException("El nombre debe tener al menos 4 caracteres");
        }
        if (nombreLimpio.length() > 50) {
            throw new IllegalArgumentException("El nombre no puede exceder los 50 caracteres");
        }
        
        // Evitar secuencias repetitivas (ej. "aaaa" o "asdasdasd")
        if (nombreLimpio.matches(".*(.)\\1{2,}.*")) {
            throw new IllegalArgumentException("El nombre contiene caracteres repetitivos inválidos");
        }

        if (nombreLimpio.toLowerCase().matches(".*(asd|qwe|zxc|test|prueba).*")) {
            throw new IllegalArgumentException("El nombre parece ser spam o texto de prueba");
        }
        
        // Si el nombre tiene al menos 5 letras y es solo alfabético, asegurar que tenga alguna vocal
        if (nombreLimpio.length() >= 5 && nombreLimpio.matches("[a-zA-ZáéíóúÁÉÍÓÚñÑ]+")) {
            if (!nombreLimpio.matches(".*[aAeEiIoOuUáéíóúÁÉÍÓÚüÜ].*")) {
                throw new IllegalArgumentException("El nombre parece no ser válido (sin vocales)");
            }
        }

        // Evitar puros emojis o símbolos comprobando que haya al menos 3 letras o números
        long alfanumericos = nombreLimpio.chars().filter(Character::isLetterOrDigit).count();
        if (alfanumericos < 3) {
            throw new IllegalArgumentException("El nombre debe contener al menos 3 letras o números");
        }
        
        return nombreLimpio;
    }

    /**
     * Valida el formato de un correo electrónico.
     */
    public static String validarEmail(String email) {
        if (email == null || email.trim().isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El email no puede estar vacío");
        }
        String emailLimpio = email.trim().toLowerCase();
        if (!PATRON_EMAIL.matcher(emailLimpio).matches()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "El formato del email es inválido");
        }
        return emailLimpio;
    }

    /**
     * Valida la longitud de la contraseña.
     */
    public static void validarPassword(String password) {
        if (password == null || password.length() < 6) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "La contraseña debe tener al menos 6 caracteres");
        }
    }
}
