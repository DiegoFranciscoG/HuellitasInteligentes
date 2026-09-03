import { CanActivateFn, Router } from '@angular/router';
import { inject } from '@angular/core';
import { AuthService } from '../services/auth.service';

/**
 * Guard de ruta que exige sesión iniciada y, si la ruta declara
 * `data.roles`, restringe el acceso a los roles permitidos. Además aplica
 * una restricción adicional para el rol `MIEMBRO`, limitándolo a las
 * secciones de dispositivos y alertas.
 */
export const roleGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);
  
  const user = authService.currentUser();
  
  if (!user) {
    router.navigate(['/auth/login']);
    return false;
  }

  const expectedRoles = route.data['roles'] as Array<string>;
  
  if (expectedRoles && expectedRoles.length > 0) {
    if (expectedRoles.includes(user.rol)) {
      return true;
    } else {
      const redirectPath = user.rol === 'MIEMBRO' ? '/dispositivos' : '/dashboard';
      router.navigate([redirectPath]);
      return false;
    }
  }

  if (user.rol === 'MIEMBRO') {
    const allowedForMiembro = ['/dispositivos', '/alertas'];
    const currentPath = state.url.split('?')[0];
    if (!allowedForMiembro.some(path => currentPath.startsWith(path))) {
      router.navigate(['/dispositivos']);
      return false;
    }
  }

  return true;
};
