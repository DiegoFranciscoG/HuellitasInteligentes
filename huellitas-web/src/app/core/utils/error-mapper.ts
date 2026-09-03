/**
 * Tabla de traducción de códigos/mensajes de error crudos del backend a
 * mensajes en español amigables para el usuario final.
 */
export const ERROR_TRANSLATIONS: Record<string, string> = {
  'EMAIL_YA_REGISTRADO': 'Ese correo ya está registrado en el sistema. Por favor utiliza uno diferente.',
  'CASA_YA_TIENE_MIEMBRO': 'Tu casa ya cuenta con un miembro registrado.',
  'NOMBRE_INVALIDO': 'El nombre del miembro solo puede contener letras y espacios (sin números ni caracteres especiales).',
  'Token QR no proporcionado': 'Por favor ingresa o escanea el código QR de acceso.',
  'Token QR inválido, usado o expirado': 'Este código QR ya fue utilizado, expiró o es inválido. Genera uno nuevo.',
  'No autorizado o sin casa vinculada': 'No tienes permisos o no cuentas con una casa registrada.',
  'Miembro no encontrado o no pertenece a tu casa': 'El miembro seleccionado no fue encontrado en tu casa.',
  'GRUPO_NOMBRE_DUPLICADO': 'Ya existe un grupo con ese nombre. Por favor elige un nombre diferente.',
  'TEXTO_INCOHERENTE': 'El nombre o contenido ingresado no parece válido en español. Intenta con algo más descriptivo.'
};

/**
 * Extrae el mensaje de error de una respuesta HTTP fallida y lo traduce a
 * un mensaje en español legible usando `ERROR_TRANSLATIONS`, ya sea por
 * coincidencia exacta o porque el mensaje crudo contiene el código.
 * @param err Objeto de error recibido (típicamente un `HttpErrorResponse`).
 * @param defaultMsg Mensaje a usar cuando no se puede extraer ninguno del error.
 * @returns Mensaje de error listo para mostrar al usuario.
 */
export function mapBackendError(err: any, defaultMsg: string = 'Ocurrió un error al procesar la solicitud.'): string {
  if (!err) return defaultMsg;
  const rawMsg = err.error?.error || err.error?.message || (typeof err.error === 'string' ? err.error : null) || err.message;
  if (!rawMsg) return defaultMsg;

  if (ERROR_TRANSLATIONS[rawMsg]) {
    return ERROR_TRANSLATIONS[rawMsg];
  }

  for (const [code, translation] of Object.entries(ERROR_TRANSLATIONS)) {
    if (rawMsg.includes(code)) {
      return translation;
    }
  }

  return rawMsg;
}
