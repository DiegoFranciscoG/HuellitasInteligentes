import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LucideAngularModule, Bell, Send, Megaphone, CheckCircle } from 'lucide-angular';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../../environments/environment';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-admin-avisos',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
  templateUrl: './admin-avisos.html'
})
/**
 * Permite al administrador redactar y enviar avisos/anuncios que llegan a
 * la campanita de notificaciones de todos los usuarios de la plataforma.
 */
export class AdminAvisosComponent implements OnInit {
  private http = inject(HttpClient);
  private authService = inject(AuthService);

  user = this.authService.currentUser;

  Bell = Bell;
  Send = Send;
  Megaphone = Megaphone;
  CheckCircle = CheckCircle;

  titulo = signal('');
  mensaje = signal('');
  tipo = signal('INFO');
  cargando = signal(false);
  feedback = signal('');

  anunciosPrevios = signal<any[]>([]);

  ngOnInit() {
    this.cargarAnunciosPrevios();
  }

  /** Obtiene el historial de avisos enviados anteriormente. */
  cargarAnunciosPrevios() {
    this.http.get<any[]>(`${environment.apiUrl}/admin/anuncios`).subscribe({
      next: (res) => this.anunciosPrevios.set(res || []),
      error: () => {}
    });
  }

  /** Envía el aviso redactado a todos los usuarios y refresca el historial. */
  enviarAviso() {
    if (!this.titulo().trim() || !this.mensaje().trim()) return;

    this.cargando.set(true);
    const params = new HttpParams()
      .set('adminId', this.user()?.id ?? '')
      .set('titulo', this.titulo().trim())
      .set('mensaje', this.mensaje().trim())
      .set('tipo', this.tipo());

    this.http.post<any>(`${environment.apiUrl}/admin/anuncios`, null, { params }).subscribe({
      next: () => {
        this.feedback.set('¡Aviso enviado a la campanita de todos los usuarios!');
        this.titulo.set('');
        this.mensaje.set('');
        this.cargando.set(false);
        this.cargarAnunciosPrevios();
        setTimeout(() => this.feedback.set(''), 4000);
      },
      error: (err) => {
        this.feedback.set('Error: ' + (err.error?.message || err.message));
        this.cargando.set(false);
        setTimeout(() => this.feedback.set(''), 4000);
      }
    });
  }
}
