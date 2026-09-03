import { Component, inject, OnInit, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../../core/services/auth.service';
import { LucideAngularModule, Lock, Eye, EyeOff, CheckCircle2 } from 'lucide-angular';

@Component({
  selector: 'app-reset-password',
  standalone: true,
  imports: [ReactiveFormsModule, RouterLink, CommonModule, LucideAngularModule],
  templateUrl: './reset-password.html',
})
/** Formulario para establecer una nueva contraseña a partir del token recibido por correo. */
export class ResetPassword implements OnInit {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private route = inject(ActivatedRoute);
  private router = inject(Router);

  token = '';
  
  resetForm = this.fb.nonNullable.group({
    password: ['', [Validators.required, Validators.minLength(6)]],
    confirmPassword: ['', [Validators.required]]
  }, { validators: this.passwordMatchValidator });
  
  isLoading = signal(false);
  isSuccess = signal(false);
  errorMessage = signal('');
  showPassword = signal(false);
  showConfirm = signal(false);

  // Lucide Icons
  Lock = Lock;
  Eye = Eye;
  EyeOff = EyeOff;
  CheckCircle2 = CheckCircle2;

  /** Extrae el token de recuperación de la URL; sin él, muestra un error de enlace inválido. */
  ngOnInit() {
    this.route.queryParams.subscribe(params => {
      this.token = params['token'];
      if (!this.token) {
        this.errorMessage.set('Enlace de recuperación inválido o expirado.');
      }
    });
  }

  /** Validador de formulario: exige que contraseña y confirmación coincidan. */
  passwordMatchValidator(g: any) {
    return g.get('password').value === g.get('confirmPassword').value
      ? null : { mismatch: true };
  }

  /**
   * Alterna la visibilidad del texto de un campo de contraseña.
   * @param field Campo a alternar (`password` o `confirm`).
   */
  togglePassword(field: 'password' | 'confirm') {
    if (field === 'password') this.showPassword.update(v => !v);
    else this.showConfirm.update(v => !v);
  }

  /** Indica si un campo del formulario es inválido y ya fue tocado/modificado. */
  isFieldInvalid(field: string): boolean {
    const ctrl = this.resetForm.get(field);
    return !!(ctrl && ctrl.invalid && (ctrl.dirty || ctrl.touched));
  }

  /** Envía la nueva contraseña junto con el token, y redirige al login al confirmar. */
  onSubmit() {
    if (this.resetForm.valid && this.token) {
      this.isLoading.set(true);
      this.errorMessage.set('');
      
      const newPassword = this.resetForm.get('password')?.value;
      if (!newPassword) return;

      this.authService.resetearPassword(this.token, newPassword).subscribe({
        next: () => {
          this.isSuccess.set(true);
          this.isLoading.set(false);
          setTimeout(() => this.router.navigate(['/auth/login']), 2500);
        },
        error: (err) => {
          this.errorMessage.set(err?.error?.error || err?.message || 'Error al restablecer la contraseña. El enlace puede haber expirado.');
          this.isLoading.set(false);
        }
      });
    } else {
      this.resetForm.markAllAsTouched();
    }
  }
}
