import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LucideAngularModule, Users, Search, RefreshCw, Eye, ShieldAlert, CreditCard, MessageSquare, AlertCircle } from 'lucide-angular';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../../environments/environment';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-admin-usuarios',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
  templateUrl: './admin-usuarios.html',
})
/**
 * Panel de administración de usuarios: listado con búsqueda y un panel de
 * detalle con la actividad de cada usuario (publicaciones, resoluciones de
 * moderación y suscripciones).
 */
export class AdminUsuariosComponent implements OnInit {
  private http = inject(HttpClient);
  private authService = inject(AuthService);

  user = this.authService.currentUser;

  Users = Users;
  Search = Search;
  RefreshCw = RefreshCw;
  Eye = Eye;
  ShieldAlert = ShieldAlert;
  CreditCard = CreditCard;
  MessageSquare = MessageSquare;
  AlertCircle = AlertCircle;

  usuarios = signal<any[]>([]);
  isLoading = signal(true);
  searchTerm = signal('');

  // User Activity Drawer State
  usuarioDetalle = signal<any>(null);
  cargandoActividad = signal(false);
  actividadPublicaciones = signal<any[]>([]);
  actividadResoluciones = signal<any[]>([]);
  actividadSuscripciones = signal<any[]>([]);

  ngOnInit() {
    this.cargarUsuarios();
  }

  /** Obtiene el listado completo de usuarios registrados. */
  cargarUsuarios() {
    this.isLoading.set(true);
    this.http.get<any[]>(`${environment.apiUrl}/admin/usuarios`).subscribe({
      next: (data) => {
        this.usuarios.set(data || []);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  /**
   * Abre el panel de detalle de un usuario y carga su historial de
   * publicaciones, resoluciones de moderación y suscripciones.
   * @param u Usuario a inspeccionar.
   */
  verActividadUsuario(u: any) {
    this.usuarioDetalle.set(u);
    this.cargandoActividad.set(true);
    this.http.get<any>(`${environment.apiUrl}/admin/usuarios/${u.id}/actividad`).subscribe({
      next: (res) => {
        this.actividadPublicaciones.set(res.publicaciones || []);
        this.actividadResoluciones.set(res.resoluciones || []);
        this.actividadSuscripciones.set(res.suscripciones || []);
        this.cargandoActividad.set(false);
      },
      error: () => this.cargandoActividad.set(false)
    });
  }

  /** Cierra el panel de detalle de actividad del usuario. */
  cerrarDetalle() {
    this.usuarioDetalle.set(null);
  }

  /** Usuarios filtrados por el término de búsqueda (nombre o email), sin distinguir mayúsculas/minúsculas. */
  get usuariosFiltrados() {
    const term = this.searchTerm().toLowerCase();
    if (!term) return this.usuarios();
    return this.usuarios().filter(u =>
      u.nombre?.toLowerCase().includes(term) || u.email?.toLowerCase().includes(term)
    );
  }
}
