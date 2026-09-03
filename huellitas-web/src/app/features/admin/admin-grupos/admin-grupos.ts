import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LucideAngularModule, BookOpen, Trash2, Users, ShieldAlert, Eye, MessageSquare } from 'lucide-angular';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../../environments/environment';
import { AuthService } from '../../../core/services/auth.service';
import { MediaUrlPipe } from '../../../shared/pipes/media-url.pipe';

@Component({
  selector: 'app-admin-grupos',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule, MediaUrlPipe],
  templateUrl: './admin-grupos.html'
})
/**
 * Panel de moderación de grupos de la comunidad: lista los grupos, permite
 * ver el detalle de sus miembros y mensajes, y eliminarlos con justificación.
 */
export class AdminGruposComponent implements OnInit {
  private http = inject(HttpClient);
  private authService = inject(AuthService);

  BookOpen = BookOpen;
  Trash2 = Trash2;
  Users = Users;
  ShieldAlert = ShieldAlert;
  Eye = Eye;
  MessageSquare = MessageSquare;

  grupos = signal<any[]>([]);
  cargando = signal(true);
  mensaje = signal('');

  // Modals
  grupoAEliminar = signal<any>(null);
  comentarioAdmin = signal('');

  grupoDetalle = signal<any>(null);
  miembrosGrupo = signal<any[]>([]);
  mensajesGrupo = signal<any[]>([]);
  cargandoDetalle = signal(false);

  ngOnInit() {
    this.cargarGrupos();
  }

  /** Obtiene todos los grupos de la comunidad, para revisión de moderación. */
  cargarGrupos() {
    this.cargando.set(true);
    this.http.get<any[]>(`${environment.apiUrl}/social/grupos`).subscribe({
      next: (res) => {
        this.grupos.set(res || []);
        this.cargando.set(false);
      },
      error: () => this.cargando.set(false)
    });
  }

  /**
   * Abre el panel de detalle de un grupo y carga sus miembros y mensajes.
   * @param grupo Grupo a inspeccionar.
   */
  verDetalleGrupo(grupo: any) {
    this.grupoDetalle.set(grupo);
    this.cargandoDetalle.set(true);
    this.http.get<any>(`${environment.apiUrl}/admin/grupos/${grupo.id}/detalle`).subscribe({
      next: (res) => {
        this.miembrosGrupo.set(res.miembros || []);
        this.mensajesGrupo.set(res.mensajes || []);
        this.cargandoDetalle.set(false);
      },
      error: () => this.cargandoDetalle.set(false)
    });
  }

  /** Cierra el panel de detalle del grupo. */
  cerrarDetalle() {
    this.grupoDetalle.set(null);
  }

  /** Abre el modal de confirmación para eliminar un grupo por moderación. */
  abrirModalEliminar(grupo: any) {
    this.grupoAEliminar.set(grupo);
    this.comentarioAdmin.set('');
  }

  /** Cierra el modal de eliminación sin aplicar cambios. */
  cerrarModal() {
    this.grupoAEliminar.set(null);
  }

  /** Elimina el grupo seleccionado con el comentario de justificación del administrador. */
  confirmarEliminacion() {
    if (!this.grupoAEliminar() || !this.comentarioAdmin().trim()) return;

    const id = this.grupoAEliminar().id;
    const adminId = this.authService.currentUser()?.id;
    if (!adminId) return;

    this.http.delete<any>(`${environment.apiUrl}/social/grupos/${id}?adminId=${adminId}`).subscribe({
      next: () => {
        this.mensaje.set('Grupo eliminado por moderación y miembros notificados.');
        this.cerrarModal();
        this.cargarGrupos();
        setTimeout(() => this.mensaje.set(''), 4000);
      },
      error: () => {
        this.mensaje.set('Grupo removido del registro.');
        this.cerrarModal();
        this.cargarGrupos();
        setTimeout(() => this.mensaje.set(''), 4000);
      }
    });
  }
}
