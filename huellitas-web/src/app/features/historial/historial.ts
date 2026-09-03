import { Component, signal, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { LucideAngularModule, Activity, Clock, User, Shield, Key, Sparkles, Filter, ExternalLink } from 'lucide-angular';
import { AuthService } from '../../core/services/auth.service';
import { environment } from '../../../environments/environment';
import { Router } from '@angular/router';

@Component({
  selector: 'app-historial',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  templateUrl: './historial.html'
})
/**
 * Muestra el historial de actividad (bitácora) del usuario en la
 * plataforma, con un ícono según el tipo de acción y navegación directa
 * al elemento relacionado (publicación, mensaje de grupo o dispositivo).
 */
export class Historial implements OnInit {
  authService = inject(AuthService);
  http = inject(HttpClient);
  router = inject(Router);
  user = this.authService.currentUser;

  Activity = Activity;
  Clock = Clock;
  User = User;
  Shield = Shield;
  Key = Key;
  Sparkles = Sparkles;
  Filter = Filter;

  logs = signal<any[]>([]);
  isLoading = signal(true);
  vistaHogar = signal(false);

  /** Carga el historial de actividad del usuario en sesión. */
  ngOnInit() {
    this.cargarHistorial();
  }

  /** Obtiene el registro de actividad (bitácora): la propia, o la de todo el hogar si `vistaHogar` está activo. */
  cargarHistorial() {
    if (!this.user()) return;
    this.isLoading.set(true);
    const url = this.vistaHogar()
      ? `${environment.apiUrl}/historial/casa`
      : `${environment.apiUrl}/historial?usuarioId=${this.user().id}`;
    this.http.get<any[]>(url).subscribe({
      next: (data) => {
        this.logs.set(data);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  /** Alterna entre ver la actividad propia y la de todo el hogar (solo disponible para el PROPIETARIO). */
  cambiarVista(hogar: boolean) {
    if (this.vistaHogar() === hogar) return;
    this.vistaHogar.set(hogar);
    this.cargarHistorial();
  }

  /**
   * Elige el ícono representativo para una entrada del historial según el tipo de acción.
   * @param accion Código de la acción registrada (ej. `"LOGIN"`, `"STRIKE"`).
   */
  getIconForAccion(accion: string) {
    if (accion.includes('LOGIN') || accion.includes('AUTH')) return Key;
    if (accion.includes('STRIKE') || accion.includes('MODERACION')) return Shield;
    if (accion.includes('CREAR') || accion.includes('PUBLICACION')) return Sparkles;
    return Activity;
  }

  /**
   * Navega a la pantalla asociada a una entrada del historial (grupo,
   * publicación de la comunidad o historial de dispositivos), según su
   * entidad y acción registradas.
   * @param log Entrada del historial sobre la que se hizo clic.
   */
  navegarAElemento(log: any) {
    if (!log) return;
    const entidad = (log.entidad || '').toLowerCase();
    const accion = (log.accion || '').toUpperCase();

    if (entidad.includes('publicacion_grupo') || accion.includes('GRUPO')) {
      this.router.navigate(['/grupos'], { queryParams: { grupo: 1, msg: log.entidad_id } });
    } else if (entidad.includes('publicacion') || accion.includes('PUBLICACION')) {
      this.router.navigate(['/comunidad'], { queryParams: { post: log.entidad_id } });
    } else if (entidad.includes('dispositivo') || accion.includes('IOT')) {
      this.router.navigate(['/historial-dispositivos']);
    }
  }
}
