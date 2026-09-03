import { AbstractControl, ValidationErrors, ValidatorFn } from '@angular/forms';

/**
 * Colección de validadores y utilidades de formato reutilizables para los
 * formularios reactivos de la aplicación (nombres de personas, nombres de
 * entidades y capitalización de texto).
 */
export class CustomValidators {
  /**
   * Valida un nombre de persona.
   * Sin números ni símbolos raros, mínimo 2 caracteres.
   */
  static nombrePersona(): ValidatorFn {
    return (control: AbstractControl): ValidationErrors | null => {
      if (!control.value) return null;
      
      const value = control.value.trim().replace(/\s+/g, ' ');
      const patron = /^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]{2,60}$/;
      
      if (!patron.test(value)) {
        return { nombrePersonaInvalido: true };
      }
      return null;
    };
  }

  /**
   * Valida un nombre de entidad (Grupo, Casa).
   * No puede estar vacío, no puede contener puros símbolos, mínimo 2 caracteres alfanuméricos.
   */
  static nombreEntidad(): ValidatorFn {
    return (control: AbstractControl): ValidationErrors | null => {
      if (!control.value) return null;

      const value = control.value.trim();
      if (value.length < 2) {
        return { nombreEntidadCorto: true };
      }

      const alfanumericos = value.replace(/[^a-zA-Z0-9áéíóúÁÉÍÓÚñÑ]/g, '').length;
      if (alfanumericos < 2) {
        return { nombreEntidadSinLetras: true };
      }

      return null;
    };
  }

  /**
   * Formatea un texto a Title Case (capitaliza la primera letra de cada palabra).
   * Útil para usar en (input) o ngModelChange.
   */
  static capitalizeText(text: string): string {
    if (!text) return text;
    
    // Remueve múltiples espacios
    const limpio = text.replace(/\s+/g, ' ');
    
    // Divide en palabras y capitaliza la primera letra
    const palabras = limpio.split(' ');
    const formateado = palabras.map(palabra => {
      if (palabra.length > 0) {
        return palabra.charAt(0).toUpperCase() + palabra.slice(1).toLowerCase();
      }
      return palabra;
    });
    
    // Une con espacios y mantiene un espacio al final si el usuario lo escribió
    return formateado.join(' ') + (text.endsWith(' ') ? ' ' : '');
  }
}
