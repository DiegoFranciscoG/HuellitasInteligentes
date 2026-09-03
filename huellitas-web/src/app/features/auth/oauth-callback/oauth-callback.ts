import { Component, inject, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-oauth-callback',
  standalone: true,
  template: `
    <div class="min-h-screen flex items-center justify-center bg-[#FFFAED]">
      <div class="text-center space-y-4">
        <div class="w-12 h-12 border-4 border-[var(--primary)]/30 border-t-[var(--primary)] rounded-full animate-spin mx-auto"></div>
        <p class="text-[var(--primary)] font-semibold animate-pulse">Completando inicio de sesión...</p>
      </div>
    </div>
  `,
})
/**
 * Página de retorno del flujo OAuth (Google/Facebook): toma el token
 * recibido por query param, establece la sesión y redirige al dashboard,
 * o de vuelta al login si el proveedor no devolvió un token válido.
 */
export class OauthCallback implements OnInit {
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private authService = inject(AuthService);

  /** Procesa el token recibido en la URL y completa el inicio de sesión. */
  ngOnInit() {
    this.route.queryParams.subscribe(params => {
      const token = params['token'];
      if (token) {
        this.authService.setSessionFromToken(token);
        this.router.navigate(['/dashboard']);
      } else {
        this.router.navigate(['/auth/login'], { queryParams: { error: 'oauth2' } });
      }
    });
  }
}
