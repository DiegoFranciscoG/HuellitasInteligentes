import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators, FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../../core/services/auth.service';
import { environment } from '../../../../environments/environment';
import { LucideAngularModule, Mail, Lock, X, Eye, EyeOff, QrCode } from 'lucide-angular';
import { QrCameraScannerComponent } from '../../../shared/components/qr-camera-scanner/qr-camera-scanner';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [ReactiveFormsModule, FormsModule, RouterLink, CommonModule, LucideAngularModule, QrCameraScannerComponent],
  templateUrl: './login.html',
  styleUrls: ['./login.scss']
})
/**
 * Pantalla de inicio de sesión: soporta email/contraseña, acceso rápido
 * por código QR (escaneado o pegado) y login social (Google/Facebook), con
 * accesos de demostración cuando `environment.demoMode` está activo.
 */
export class Login {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);

  // Icons
  readonly MailIcon = Mail;
  readonly LockIcon = Lock;
  readonly XIcon = X;
  readonly EyeIcon = Eye;
  readonly EyeOffIcon = EyeOff;
  readonly QrCodeIcon = QrCode;

  loginForm = this.fb.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, Validators.minLength(6)]],
    rememberMe: [false]
  });

  isLoading = signal(false);
  errorMessage = signal('');
  showPassword = signal(false);
  demoMode = signal(environment.demoMode);

  // QR Login State
  showQrMode = signal(false);
  qrTokenInput = signal('');
  showScanner = signal(false);

  /** Muestra/oculta el escáner de cámara para leer el código QR de acceso. */
  toggleScanner() {
    this.showScanner.update(v => !v);
    this.errorMessage.set('');
  }

  /** Se dispara cuando la cámara reconoce un QR: valida el acceso directamente. */
  onQrScanned(texto: string) {
    this.showScanner.set(false);
    this.qrTokenInput.set(this.extraerToken(texto));
    this.submitQrLogin();
  }

  /**
   * El QR puede contener el token pelado o una URL del tipo
   * `.../auth/qr-login?token=XXXX`. Aceptamos ambos para que dé igual desde
   * dónde se haya generado el código.
   */
  private extraerToken(texto: string): string {
    const limpio = texto.trim();
    try {
      const url = new URL(limpio);
      return url.searchParams.get('token') ?? limpio;
    } catch {
      return limpio;
    }
  }

  /** Inicia sesión con email y contraseña, y redirige al dashboard si tiene éxito. */
  onSubmit() {
    if (this.loginForm.valid) {
      this.isLoading.set(true);
      this.errorMessage.set('');
      const { email, password } = this.loginForm.getRawValue();
      
      this.authService.login(email, password).subscribe({
        next: () => {
          this.router.navigate(['/dashboard']);
          this.isLoading.set(false);
        },
        error: (err) => {
          this.errorMessage.set(err?.error?.message || err?.error?.error || 'Credenciales incorrectas. Verifica tu correo y contraseña.');
          this.isLoading.set(false);
        }
      });
    } else {
      this.loginForm.markAllAsTouched();
    }
  }

  /** Alterna entre el formulario de email/contraseña y el de acceso por QR. */
  toggleQrMode() {
    this.showQrMode.update(v => !v);
    this.errorMessage.set('');
  }

  /** Valida el token QR ingresado/escaneado e inicia sesión con él. */
  submitQrLogin() {
    const token = this.qrTokenInput().trim();
    if (!token) {
      this.errorMessage.set('Por favor ingresa o escanea el código QR de acceso.');
      return;
    }

    this.isLoading.set(true);
    this.errorMessage.set('');
    this.authService.validarQrToken(token).subscribe({
      next: () => {
        this.router.navigate(['/dashboard']);
        this.isLoading.set(false);
      },
      error: (err) => {
        this.errorMessage.set(err?.error?.error || 'Token QR inválido, expirado o ya utilizado.');
        this.isLoading.set(false);
      }
    });
  }

  /** Redirige al flujo OAuth de Google. */
  loginWithGoogle() {
    window.location.href = `${environment.apiUrl}/auth/google/login`;
  }

  /** Redirige al flujo OAuth de Facebook. */
  loginWithFacebook() {
    window.location.href = `${environment.apiUrl}/auth/facebook/login`;
  }

  /**
   * Inicia sesión con una cuenta simulada (solo disponible en modo demo),
   * sin pasar por el backend.
   * @param role Rol de la cuenta de demostración a usar.
   */
  loginDemo(role: 'PROPIETARIO' | 'ADMIN') {
    if (!this.demoMode()) return;
    
    this.isLoading.set(true);
    setTimeout(() => {
      sessionStorage.setItem('token', 'mock-demo-token-' + Date.now());
      if (role === 'ADMIN') {
        sessionStorage.setItem('user', JSON.stringify({ nombre: 'Admin Huellitas', email: 'admin@huellitas.com', rol: 'ADMIN', casa_id: null }));
      } else {
        sessionStorage.setItem('user', JSON.stringify({ nombre: 'Diego García', email: 'diego@huellitas.com', rol: 'PROPIETARIO', casa_id: 1 }));
      }
      this.router.navigate(['/dashboard']);
      this.isLoading.set(false);
    }, 800);
  }

  /** Indica si un campo del formulario de login es inválido y ya fue tocado/modificado. */
  isFieldInvalid(field: string): boolean {
    const ctrl = this.loginForm.get(field);
    return !!(ctrl && ctrl.invalid && (ctrl.dirty || ctrl.touched));
  }

  /** Alterna la visibilidad del texto de la contraseña. */
  togglePassword() {
    this.showPassword.update(v => !v);
  }
}
