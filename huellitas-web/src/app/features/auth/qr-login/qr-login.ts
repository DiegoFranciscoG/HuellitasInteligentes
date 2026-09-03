import { Component, inject, OnInit, signal } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../../core/services/auth.service';
import { LucideAngularModule, QrCode, CheckCircle2, AlertCircle } from 'lucide-angular';

@Component({
  selector: 'app-qr-login',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  template: `
    <div class="min-h-screen bg-slate-900 flex items-center justify-center p-4">
      <div class="bg-white rounded-3xl p-8 max-w-md w-full text-center shadow-2xl space-y-6">
        <div class="w-16 h-16 bg-[var(--primary-surface)] text-[var(--primary)] rounded-2xl flex items-center justify-center mx-auto">
          <lucide-icon [img]="QrCode" class="w-8 h-8"></lucide-icon>
        </div>

        <h3 class="text-xl font-bold text-slate-800">Iniciando Sesión por QR</h3>

        @if (cargando()) {
          <div class="space-y-3">
            <div class="w-8 h-8 border-4 border-[var(--primary)] border-t-transparent rounded-full animate-spin mx-auto"></div>
            <p class="text-sm text-slate-500 font-medium">Validando token de acceso rápido...</p>
          </div>
        } @else if (error()) {
          <div class="bg-[var(--error-surface)] text-[var(--error)] p-4 rounded-2xl border border-[var(--error)] flex items-center gap-3 text-xs text-left">
            <lucide-icon [img]="AlertCircle" class="w-5 h-5 shrink-0"></lucide-icon>
            <span>{{ error() }}</span>
          </div>
          <button (click)="irALogin()" class="btn bg-[var(--primary)] hover:bg-[var(--primary)] text-white w-full py-3 rounded-xl font-bold text-xs">
            Volver a Login Principal
          </button>
        } @else {
          <div class="bg-[var(--primary-surface)] text-[var(--primary)] p-4 rounded-2xl border border-[var(--primary)] flex items-center gap-3 text-xs text-left">
            <lucide-icon [img]="CheckCircle2" class="w-5 h-5 shrink-0"></lucide-icon>
            <span>Acceso concedido exitosamente. Redirigiendo a tu panel...</span>
          </div>
        }
      </div>
    </div>
  `
})
/**
 * Página de acceso directo por enlace/QR: toma el token de la URL, lo
 * valida contra el backend e inicia sesión, redirigiendo según el rol del
 * usuario al panel de administración o al dashboard.
 */
export class QrLoginComponent implements OnInit {
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private authService = inject(AuthService);

  readonly QrCode = QrCode;
  readonly CheckCircle2 = CheckCircle2;
  readonly AlertCircle = AlertCircle;

  cargando = signal(true);
  error = signal('');

  /** Valida el token QR de la URL e inicia sesión, redirigiendo según el rol del usuario. */
  ngOnInit() {
    this.route.queryParams.subscribe(params => {
      const token = params['token'];
      if (!token) {
        this.cargando.set(false);
        this.error.set('No se proporcionó ningún token QR en la URL.');
        return;
      }

      this.authService.validarQrToken(token).subscribe({
        next: (res: any) => {
          this.cargando.set(false);
          const rol = res?.usuario?.rol;
          setTimeout(() => {
            if (rol === 'ADMINISTRADOR' || rol === 'ADMIN') {
              this.router.navigate(['/admin/dashboard']);
            } else {
              this.router.navigate(['/dashboard']);
            }
          }, 800);
        },
        error: (err) => {
          this.cargando.set(false);
          this.error.set(err?.error?.error || 'El código QR es inválido, ya fue usado o expiro.');
        }
      });
    });
  }

  /** Vuelve a la pantalla de login principal. */
  irALogin() {
    this.router.navigate(['/auth/login']);
  }
}
