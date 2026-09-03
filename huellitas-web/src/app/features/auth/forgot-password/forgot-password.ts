import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, FormsModule, Validators } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../../core/services/auth.service';
import { LucideAngularModule, Mail, ArrowLeft, Send } from 'lucide-angular';

@Component({
  selector: 'app-forgot-password',
  standalone: true,
  imports: [ReactiveFormsModule, FormsModule, RouterLink, CommonModule, LucideAngularModule],
  templateUrl: './forgot-password.html',
})
/** Formulario para solicitar el correo de recuperación de contraseña. */
export class ForgotPassword {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);

  emailControl = this.fb.control('', [Validators.required, Validators.email]);
  
  isLoading = signal(false);
  isSuccess = signal(false);
  errorMessage = signal('');

  // Lucide Icons
  Mail = Mail;
  ArrowLeft = ArrowLeft;
  Send = Send;

  /**
   * Envía la solicitud de recuperación. Por seguridad, siempre muestra el
   * mensaje de éxito aunque el correo no exista o la petición falle, para
   * no revelar qué correos están registrados.
   */
  onSubmit() {
    if (this.emailControl.valid && this.emailControl.value) {
      this.isLoading.set(true);
      this.errorMessage.set('');
      
      this.authService.solicitarReset(this.emailControl.value).subscribe({
        next: () => {
          this.isSuccess.set(true);
          this.isLoading.set(false);
        },
        error: (err) => {
          // Por seguridad, siempre mostramos éxito aunque falle, pero puedes manejar errores de red aquí
          this.isSuccess.set(true);
          this.isLoading.set(false);
        }
      });
    } else {
      this.emailControl.markAsTouched();
    }
  }
}
