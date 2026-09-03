import { HttpInterceptorFn, HttpErrorResponse } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';
import { AuthService } from '../services/auth.service';

/**
 * Interceptor HTTP que centraliza el manejo de errores de red y del
 * servidor: traduce cada respuesta fallida a un mensaje legible, cierra la
 * sesión y redirige al login ante un 401, y propaga un `Error` con el
 * mensaje resultante para que los componentes lo muestren (p. ej. vía toasts).
 */
export const errorInterceptor: HttpInterceptorFn = (req, next) => {
  const router = inject(Router);
  const authService = inject(AuthService);

  return next(req).pipe(
    catchError((error: HttpErrorResponse) => {
      let errorMsg = 'Algo salió mal.';

      if (error.error instanceof ErrorEvent) {
        // Client side error
        errorMsg = `Error: ${error.error.message}`;
      } else {
        // Server side error
        switch (error.status) {
          case 0:
            errorMsg = 'No se pudo conectar al servidor.';
            break;
          case 401:
            // Solo es una sesión que expiró si de verdad había una sesión.
            // Sin esto, cualquier 401 —incluido el de una pantalla pública
            // como verificar-email, que a propósito todavía no tiene
            // token— sacaba al usuario al login de golpe.
            if (authService.currentUser()) {
              authService.logout();
              router.navigate(['/auth/login']);
              errorMsg = 'Sesión expirada. Por favor, inicia sesión nuevamente.';
            } else {
              errorMsg = 'No tienes permiso para hacer esto.';
            }
            break;
          case 400:
          case 422:
            // Extract business logic message
            if (error.error && error.error.message) {
              errorMsg = error.error.message;
            } else if (typeof error.error === 'string') {
               errorMsg = error.error;
            } else {
              errorMsg = 'Datos inválidos.';
            }
            break;
          case 500:
            errorMsg = 'Error interno del servidor.';
            break;
          default:
            errorMsg = `Error del servidor: ${error.status}`;
        }
      }
      
      // Pass the extracted error message for components to use
      return throwError(() => new Error(errorMsg));
    })
  );
};
