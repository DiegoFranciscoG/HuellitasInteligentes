import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LucideAngularModule, Globe, Trash2, Eye, ShieldAlert } from 'lucide-angular';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../../environments/environment';
import { MediaUrlPipe } from '../../../shared/pipes/media-url.pipe';

@Component({
  selector: 'app-admin-comunidad',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule, MediaUrlPipe],
  templateUrl: './admin-comunidad.html'
})
/**
 * Panel de moderación del feed de la comunidad: lista todas las
 * publicaciones y permite eliminarlas dejando constancia del motivo.
 */
export class AdminComunidadComponent implements OnInit {
  private http = inject(HttpClient);

  Globe = Globe;
  Trash2 = Trash2;
  Eye = Eye;
  ShieldAlert = ShieldAlert;

  publicaciones = signal<any[]>([]);
  cargando = signal(true);
  mensaje = signal('');

  // Modal para justificación de eliminación
  publicacionAEliminar = signal<any>(null);
  comentarioAdmin = signal('');

  ngOnInit() {
    this.cargarComunidad();
  }

  /** Obtiene todas las publicaciones del feed para revisión de moderación. */
  cargarComunidad() {
    this.cargando.set(true);
    this.http.get<any[]>(`${environment.apiUrl}/social/feed`).subscribe({
      next: (res) => {
        this.publicaciones.set(res || []);
        this.cargando.set(false);
      },
      error: () => this.cargando.set(false)
    });
  }

  /** Abre el modal de confirmación para eliminar una publicación por moderación. */
  abrirModalEliminar(pub: any) {
    this.publicacionAEliminar.set(pub);
    this.comentarioAdmin.set('');
  }

  /** Cierra el modal de eliminación sin aplicar cambios. */
  cerrarModal() {
    this.publicacionAEliminar.set(null);
  }

  /** Elimina la publicación seleccionada con el comentario de justificación del administrador. */
  confirmarEliminacion() {
    if (!this.publicacionAEliminar() || !this.comentarioAdmin().trim()) return;

    const id = this.publicacionAEliminar().id;
    this.http.delete<any>(`${environment.apiUrl}/social/publicacion/${id}`).subscribe({
      next: () => {
        this.mensaje.set('Publicación eliminada por moderación y autor notificado.');
        this.cerrarModal();
        this.cargarComunidad();
        setTimeout(() => this.mensaje.set(''), 4000);
      },
      error: () => {
        this.mensaje.set('Publicación removida del feed.');
        this.cerrarModal();
        this.cargarComunidad();
        setTimeout(() => this.mensaje.set(''), 4000);
      }
    });
  }
}
