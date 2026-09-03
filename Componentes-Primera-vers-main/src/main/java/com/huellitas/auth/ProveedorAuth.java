package com.huellitas.auth;

/**
 * Identifica el proveedor con el que un usuario se autentica: contraseña
 * local gestionada por el sistema, o inicio de sesión federado con Google o Facebook.
 */
public enum ProveedorAuth {
    LOCAL, GOOGLE, FACEBOOK
}
