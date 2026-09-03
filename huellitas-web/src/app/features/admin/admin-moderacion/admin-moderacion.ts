import { Component, inject, OnInit, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LucideAngularModule, ShieldAlert, CheckCircle, XCircle, AlertTriangle, RefreshCw, AlertCircle, Bot, Undo2 } from 'lucide-angular';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../../environments/environment';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-admin-moderacion',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
  templateUrl: './admin-moderacion.html'
})
/**
 * Cola de moderación de denuncias de la comunidad: permite filtrar por
 * estado, resolver una denuncia (aplicando strike, eliminando el contenido
 * o descartándola) y revertir decisiones automáticas tomadas por la IA.
 */
export class AdminModeracionComponent implements OnInit {
  private http = inject(HttpClient);
  private authService = inject(AuthService);

  user = this.authService.currentUser;

  ShieldAlert = ShieldAlert;
  CheckCircle = CheckCircle;
  XCircle = XCircle;
  AlertTriangle = AlertTriangle;
  RefreshCw = RefreshCw;
  AlertCircle = AlertCircle;
  Bot = Bot;
  Undo2 = Undo2;

  reportes = signal<any[]>([]);
  isLoading = signal(true);
  mensajeModal = signal('');

  // Filtros
  filtroEstado = signal<'PENDIENTE' | 'RESUELTO' | 'DESCARTADO' | 'TODOS'>('PENDIENTE');

  // Modal State
  reporteSeleccionado = signal<any>(null);
  decisionSeleccionada = signal<'STRIKE' | 'ELIMINAR_SIN_STRIKE' | 'DESCARTADO'>('STRIKE');
  comentarioAdmin = signal('');

  /** Reportes visibles según el filtro de estado seleccionado (`PENDIENTE`, `RESUELTO`, `DESCARTADO` o `TODOS`). */
  reportesFiltrados = computed(() => {
    const list = this.reportes();
    const filtro = this.filtroEstado();
    if (filtro === 'TODOS') return list;
    return list.filter(r => (r.estado || 'PENDIENTE') === filtro);
  });

  ngOnInit() {
    this.cargarReportes();
  }

  /** Obtiene todos los reportes/denuncias de la comunidad. */
  cargarReportes() {
    this.isLoading.set(true);
    this.http.get<any[]>(`${environment.apiUrl}/admin/reportes`).subscribe({
      next: (data) => {
        this.reportes.set(data || []);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  /**
   * Abre el modal de resolución de una denuncia con la decisión preseleccionada.
   * @param reporte Denuncia a resolver.
   * @param decision Acción propuesta (aplicar strike, eliminar sin strike o descartar).
   */
  abrirModal(reporte: any, decision: 'STRIKE' | 'ELIMINAR_SIN_STRIKE' | 'DESCARTADO') {
    this.reporteSeleccionado.set(reporte);
    this.decisionSeleccionada.set(decision);
    this.comentarioAdmin.set('');
  }

  /** Cierra el modal de resolución de denuncia sin aplicar cambios. */
  cerrarModal() {
    this.reporteSeleccionado.set(null);
  }

  /**
   * Revierte una decisión de moderación tomada automáticamente por la IA,
   * devolviendo la denuncia a estado pendiente para revisión manual.
   * @param reporteId Identificador del reporte a revertir.
   */
  revertirDecisionIa(reporteId: number) {
    if (!confirm('¿Deseas revertir esta decisión automática de la IA y devolverla a revisión manual?')) return;

    this.http.post<any>(`${environment.apiUrl}/admin/reportes/${reporteId}/revertir`, {}).subscribe({
      next: () => {
        this.mensajeModal.set('Decisión automática de IA revertida. La denuncia vuelve a estar pendiente.');
        this.cargarReportes();
        setTimeout(() => this.mensajeModal.set(''), 4000);
      },
      error: (err) => {
        this.mensajeModal.set('Error al revertir: ' + (err.error?.message || err.message));
        setTimeout(() => this.mensajeModal.set(''), 4000);
      }
    });
  }

  /** Envía la decisión de moderación tomada por el administrador para la denuncia seleccionada. */
  confirmarResolucion() {
    if (!this.comentarioAdmin().trim() || !this.reporteSeleccionado()) return;

    const payload = {
      adminId: this.user()?.id ?? null,
      decision: this.decisionSeleccionada(),
      comentarioAdmin: this.comentarioAdmin().trim()
    };

    const id = this.reporteSeleccionado().id;
    this.http.post<any>(`${environment.apiUrl}/admin/reportes/${id}/resolver`, payload).subscribe({
      next: () => {
        this.mensajeModal.set(`Denuncia resuelta (${this.decisionSeleccionada()}). Notificación enviada al usuario.`);
        this.cerrarModal();
        this.cargarReportes();
        setTimeout(() => this.mensajeModal.set(''), 4000);
      },
      error: (err) => {
        this.mensajeModal.set('Error al resolver: ' + (err.error?.message || err.message));
        setTimeout(() => this.mensajeModal.set(''), 4000);
      }
    });
  }
}
