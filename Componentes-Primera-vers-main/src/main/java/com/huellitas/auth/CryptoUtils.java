package com.huellitas.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * Utilidades criptográficas simples usadas para calcular huellas (hash) de
 * cadenas de texto, por ejemplo para almacenar tokens de forma segura.
 */
public class CryptoUtils {

    /**
     * Calcula el hash SHA-256 de una cadena y lo devuelve como texto hexadecimal.
     *
     * @param input texto de entrada; si es {@code null} se devuelve cadena vacía.
     * @return el hash SHA-256 en formato hexadecimal, o el propio {@code input} si ocurre un error inesperado.
     */
    public static String sha256(String input) {
        if (input == null) return "";
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] hash = md.digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : hash) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (Exception e) {
            return input;
        }
    }
}
