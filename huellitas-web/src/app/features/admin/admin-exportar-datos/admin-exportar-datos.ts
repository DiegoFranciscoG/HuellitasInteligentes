import { Component, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient, HttpParams } from '@angular/common/http';
import { LucideAngularModule, Search, Calendar, FileDown, FileText, Clock, ShieldCheck, TrendingUp, Database, Eye, X, Lock } from 'lucide-angular';
import { environment } from '../../../../environments/environment';

interface RegistroExplorador {
  categoria: string;
  id: number;
  nombre: string;
  correo: string | null;
  estado: string;
  camaras_conectadas: number | null;
  iot_implementado: string | null;
  mascotas: number | null;
  plan: string | null;
  detalle: string | null;
  ultima_actividad: string;
  fecha_registro: string;
}

@Component({
  selector: 'app-admin-exportar-datos',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
  templateUrl: './admin-exportar-datos.html',
})
/**
 * "Explorador de Datos Avanzado": vista unificada y filtrable de usuarios,
 * dispositivos IoT, suscripciones y grupos, con exportación a CSV/PDF y
 * envío del reporte por correo. Todos los datos, filtros y métricas vienen
 * del backend real — nada de filas ni cifras de ejemplo.
 *
 * El flujo es intencional: hasta que el administrador presiona "Buscar" no
 * hay resultados ni exportación disponible, para que lo que se descargue
 * sea siempre un conjunto de datos que el admin pidió a propósito, no "todo
 * el sistema" por accidente.
 */
export class AdminExportarDatosComponent {
  Search = Search;
  Calendar = Calendar;
  FileDown = FileDown;
  FileText = FileText;
  Clock = Clock;
  ShieldCheck = ShieldCheck;
  TrendingUp = TrendingUp;
  Database = Database;
  Eye = Eye;
  X = X;
  Lock = Lock;

  // Los 3 únicos estados reales del sistema (ver AdminController#EXPLORADOR_QUERY):
  // un usuario nunca queda "Eliminado", solo Activa / Sancionado (3 strikes) / Bloqueado.
  readonly categoriasDisponibles = ['Todos', 'Usuario', 'Dispositivo IoT', 'Suscripción', 'Grupo'];
  readonly estadosDisponibles = ['Todos', 'Activa', 'Sancionado', 'Bloqueado'];

  registros = signal<RegistroExplorador[]>([]);
  isLoading = signal(false);
  busquedaRealizada = signal(false);
  errorBusqueda = signal('');

  totalRegistros = signal<number | null>(null);
  tasaCrecimiento = signal<number | null>(null);

  // Campos del formulario de búsqueda (lo que el admin está escribiendo,
  // separado de lo que ya se buscó — así el filtro solo se aplica al
  // presionar "Buscar", no en cada tecla).
  busqueda = signal('');
  categoria = signal('Todos');
  estado = signal('Todos');
  fechaDesde = signal('');
  fechaHasta = signal('');

  // Programar Reporte (modal)
  modalReporteAbierto = signal(false);
  emailReporte = signal('');
  formatoReporte = signal<'csv' | 'pdf'>('csv');
  enviandoReporte = signal(false);
  reporteMensaje = signal('');

  // Exportar CSV/PDF (botones del sidebar)
  exportando = signal<'csv' | 'pdf' | null>(null);
  errorExportar = signal('');

  detalleAbierto = signal<RegistroExplorador | null>(null);

  constructor(private http: HttpClient) {
    this.cargarMetricas();
  }

  private cargarMetricas() {
    this.http.get<{ total_registros: number; tasa_crecimiento_pct: number | null }>(
      `${environment.apiUrl}/admin/explorador/metricas`
    ).subscribe({
      next: (res) => {
        this.totalRegistros.set(res?.total_registros ?? null);
        this.tasaCrecimiento.set(res?.tasa_crecimiento_pct ?? null);
      },
      error: () => {},
    });
  }

  /** Arma los query params del filtro actual, para reutilizarlos en la búsqueda y en cada exportación. */
  private paramsFiltro(): HttpParams {
    let params = new HttpParams();
    if (this.categoria() !== 'Todos') params = params.set('categoria', this.categoria());
    if (this.estado() !== 'Todos') params = params.set('estado', this.estado());
    if (this.busqueda().trim()) params = params.set('q', this.busqueda().trim());
    if (this.fechaDesde()) params = params.set('fechaDesde', this.fechaDesde());
    if (this.fechaHasta()) params = params.set('fechaHasta', this.fechaHasta());
    return params;
  }

  /** Ejecuta la búsqueda con el filtro actual. Es la única forma de poblar la tabla y desbloquear la exportación. */
  buscar() {
    this.isLoading.set(true);
    this.errorBusqueda.set('');
    this.http.get<RegistroExplorador[]>(`${environment.apiUrl}/admin/explorador`, { params: this.paramsFiltro() }).subscribe({
      next: (res) => {
        this.registros.set(res || []);
        this.busquedaRealizada.set(true);
        this.isLoading.set(false);
      },
      error: () => {
        this.errorBusqueda.set('No se pudo conectar con el servidor. Verifica que el backend esté encendido.');
        this.isLoading.set(false);
      },
    });
  }

  /** Clase de color del chip de estado, en tonos orgánicos (verde musgo / arcilla). */
  claseEstado(estado: string): string {
    const e = (estado || '').toLowerCase();
    if (e === 'activa') return 'bg-[var(--accent)]/15 text-[var(--accent-dark)]';
    if (e === 'bloqueado') return 'bg-[var(--error-surface)] text-[var(--error)]';
    if (e === 'sancionado') return 'bg-[rgba(253,192,3,0.15)] text-[#8a6a00]';
    return 'bg-[var(--primary)]/8 text-[var(--primary)]';
  }

  abrirModalReporte() {
    this.reporteMensaje.set('');
    this.modalReporteAbierto.set(true);
  }

  cerrarModalReporte() {
    this.modalReporteAbierto.set(false);
  }

  /**
   * Descarga el CSV o PDF filtrado como archivo real (no un <a href> directo):
   * así se puede mostrar un error claro si la descarga falla, en vez de que
   * el botón simplemente "no haga nada" sin ninguna pista de qué pasó.
   */
  descargar(formato: 'csv' | 'pdf') {
    this.exportando.set(formato);
    this.errorExportar.set('');
    this.http.get(`${environment.apiUrl}/admin/explorador/${formato}`, {
      params: this.paramsFiltro(),
      responseType: 'blob',
    }).subscribe({
      next: (blob) => {
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `explorador-datos.${formato}`;
        document.body.appendChild(a);
        a.click();
        a.remove();
        window.URL.revokeObjectURL(url);
        this.exportando.set(null);
      },
      error: () => {
        this.errorExportar.set(`No se pudo descargar el ${formato.toUpperCase()}. Verifica que el backend esté encendido.`);
        this.exportando.set(null);
      },
    });
  }

  /**
   * Envía el reporte (con el filtro activo) ahora mismo por correo. Es un
   * envío inmediato: todavía no hay una tarea programada (cron) conectada
   * para reenviarlo automáticamente cada cierto tiempo.
   */
  enviarReporte() {
    if (!this.emailReporte().includes('@')) {
      this.reporteMensaje.set('Ingresa un correo válido.');
      return;
    }
    this.enviandoReporte.set(true);
    this.reporteMensaje.set('');
    this.http.post<{ ok: boolean }>(`${environment.apiUrl}/admin/explorador/enviar-reporte`, {
      email: this.emailReporte(),
      formato: this.formatoReporte(),
      categoria: this.categoria() !== 'Todos' ? this.categoria() : null,
      estado: this.estado() !== 'Todos' ? this.estado() : null,
      q: this.busqueda().trim() || null,
      fechaDesde: this.fechaDesde() || null,
      fechaHasta: this.fechaHasta() || null,
    }).subscribe({
      next: (res) => {
        this.enviandoReporte.set(false);
        this.reporteMensaje.set(res?.ok ? 'Reporte enviado correctamente.' : 'No se pudo enviar el reporte.');
      },
      error: () => {
        this.enviandoReporte.set(false);
        this.reporteMensaje.set('No se pudo enviar el reporte.');
      },
    });
  }
}
