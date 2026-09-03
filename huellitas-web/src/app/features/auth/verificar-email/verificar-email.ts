import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { AuthService } from '../../../core/services/auth.service';
import { ToastService } from '../../../core/services/toast.service';
import { environment } from '../../../../environments/environment';

@Component({
  selector: 'app-verificar-email',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <div class="min-h-screen flex items-center justify-center bg-[var(--surface-cream)] p-4">
      <div class="card p-8 max-w-md w-full text-center">
        <h2 class="text-2xl font-serif text-[var(--primary)] font-bold mb-4">Verificación de Correo</h2>
        <div class="bg-[var(--primary-surface)] text-[var(--primary)] p-3.5 rounded-xl mb-5 text-xs font-medium border border-[var(--primary)] flex items-center justify-center gap-2">
          <span>Hemos enviado un código a tu correo. Si no lo encuentras, revisa tu carpeta de spam.</span>
        </div>

        @if (successMessage()) {
          <div class="bg-[var(--primary-surface)] text-[var(--primary)] p-4 rounded-xl mb-4 font-medium animate-fade-in-up">
            {{ successMessage() }}
          </div>
          <button routerLink="/dashboard" class="btn btn-primary w-full mt-2 font-bold py-3">Ir al Dashboard</button>
        } @else {
          <div class="space-y-4">
            <div class="form-group text-left">
              <label class="form-label text-xs font-semibold uppercase tracking-wider text-gray-500">Correo Electrónico</label>
              <input type="email" class="form-input" [(ngModel)]="email" placeholder="tu@correo.com">
            </div>
            
            <div class="form-group text-left">
              <label class="form-label text-xs font-semibold uppercase tracking-wider text-gray-500">Código de 6 dígitos</label>
              <input type="text" class="form-input text-center text-2xl tracking-widest uppercase font-mono font-bold" [(ngModel)]="codigo" maxlength="6" placeholder="000000">
            </div>

            @if (errorMessage()) {
              <div class="text-[var(--error)] text-xs font-medium bg-[var(--error-surface)] p-2.5 rounded-lg border border-[var(--error)]">{{ errorMessage() }}</div>
            }

            <button class="btn btn-primary w-full py-3 font-bold" (click)="verificar()" [disabled]="isLoading() || !codigo || !email">
              {{ isLoading() ? 'Verificando...' : 'Verificar Código' }}
            </button>

            <div class="pt-3 border-t border-gray-100 flex items-center justify-between text-xs">
              <span class="text-gray-500">¿No recibiste el correo?</span>
              <button type="button" (click)="reenviarCodigo()" [disabled]="isResending() || !email" class="text-[var(--primary)] font-bold hover:underline disabled:opacity-50">
                {{ isResending() ? 'Enviando...' : 'Reenviar código' }}
              </button>
            </div>
          </div>
        }
      </div>
    </div>
  `
})
/** Pantalla de verificación de correo mediante código de 6 dígitos, con opción de reenvío. */
export class VerificarEmail implements OnInit {
  private route = inject(ActivatedRoute);
  private http = inject(HttpClient);
  private authService = inject(AuthService);
  private toastService = inject(ToastService);

  email = '';
  codigo = '';
  isLoading = signal(false);
  isResending = signal(false);
  errorMessage = signal('');
  successMessage = signal('');

  /** Precarga el correo del usuario en sesión y avisa que se envió el código de verificación. */
  ngOnInit() {
    this.email = this.authService.currentUser()?.email || '';
    this.toastService.info('Se ha enviado un código de verificación de 6 dígitos a tu correo. Por favor revisa tu bandeja de entrada o SPAM.', 'Código Enviado');
  }

  /** Valida el código de 6 dígitos ingresado y, si es correcto, establece la sesión con la respuesta del backend. */
  verificar() {
    this.isLoading.set(true);
    this.errorMessage.set('');

    this.http.post<any>(`${environment.apiUrl}/auth/verificar-codigo`, {
      email: this.email,
      codigo: this.codigo
    }).subscribe({
      next: (res) => {
        this.authService.setSession(res);
        this.toastService.success('¡Tu correo ha sido verificado con éxito!', 'Verificación Completa');
        this.successMessage.set('¡Tu correo ha sido verificado con éxito!');
        this.isLoading.set(false);
      },
      error: (err) => {
        this.errorMessage.set(err.error?.message || 'Código inválido o expirado.');
        this.toastService.error(err.error?.message || 'Código inválido o expirado.');
        this.isLoading.set(false);
      }
    });
  }

  /** Solicita el reenvío del código de verificación al correo ingresado. */
  reenviarCodigo() {
    if (!this.email.trim()) {
      this.errorMessage.set('Por favor ingresa tu correo electrónico.');
      return;
    }
    this.isResending.set(true);
    this.http.post<any>(`${environment.apiUrl}/auth/reenviar-codigo`, { email: this.email }).subscribe({
      next: () => {
        this.toastService.success('Código de verificación reenviado. Revisa tu bandeja de entrada o spam.', 'Correo Enviado');
        this.isResending.set(false);
      },
      error: (err) => {
        this.toastService.error(err.error?.message || 'Error al reenviar el código.');
        this.isResending.set(false);
      }
    });
  }
}
