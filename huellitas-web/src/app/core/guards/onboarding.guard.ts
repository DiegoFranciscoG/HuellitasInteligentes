import { inject } from '@angular/core';
import { Router, CanActivateFn } from '@angular/router';
import { AuthService } from '../services/auth.service';

/**
 * Guard de ruta que redirige a `/auth/onboarding` a los usuarios
 * autenticados (no administradores) que aún no completaron su perfil
 * (les falta nombre o no tienen una casa asociada), evitando que naveguen
 * al resto de la aplicación sin terminar la configuración inicial.
 */
export const onboardingGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  // Excluir la propia ruta de onboarding para evitar bucles
  if (state.url.includes('/onboarding')) {
    return true;
  }

  const user = authService.currentUser();
  
  // Si no está logueado, dejar que el RoleGuard lo maneje (o la ruta pública)
  if (!user) return true;

  // Si le falta el nombre o la casa (y no es ADMIN), enviarlo a onboarding
  const needsOnboarding = (!user.nombre || !user.casa_id) && user.rol !== 'ADMIN' && user.rol !== 'ADMINISTRADOR';

  if (needsOnboarding) {
    return router.parseUrl('/auth/onboarding');
  }

  return true;
};
