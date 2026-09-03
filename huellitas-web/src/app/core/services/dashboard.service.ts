import { Injectable, signal, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { environment } from '../../../environments/environment';

/**
 * Centraliza la carga de los datos del dashboard tanto para
 * propietarios/miembros (resumen de su casa) como para administradores
 * (resumen global de la plataforma), exponiendo el resultado y el estado
 * de carga como signals para que los componentes reaccionen a ellos.
 */
@Injectable({
  providedIn: 'root'
})
export class DashboardService {
  private http = inject(HttpClient);
  private apiUrl = `${environment.apiUrl}`;

  // ── Propietario / Miembro ─────────────────────────────────────────────────
  /** Datos del dashboard de la casa del propietario/miembro actual. */
  dashboardData = signal<any>(null);
  /** Indica si se está cargando el dashboard de la casa. */
  isLoading = signal<boolean>(false);

  /**
   * Carga el dashboard de la casa indicada y actualiza `dashboardData`.
   * @param casaId Identificador de la casa (si no se indica, usa `0`).
   */
  loadDashboardCasa(casaId?: number) {
    this.isLoading.set(true);
    const id = casaId || 0;
    this.http.get<any>(`${this.apiUrl}/casa/${id}/dashboard`).subscribe({
      next: (data) => {
        this.dashboardData.set(data);
        this.isLoading.set(false);
      },
      error: () => {
        this.dashboardData.set(null);
        this.isLoading.set(false);
      }
    });
  }

  /**
   * Igual que {@link loadDashboardCasa}, pero sin tocar `isLoading` — para
   * refrescar en segundo plano (alertas, dispositivos en línea) sin que la
   * pantalla parpadee con el esqueleto de carga cada vez.
   */
  refreshDashboardCasaSilencioso(casaId?: number) {
    const id = casaId || 0;
    this.http.get<any>(`${this.apiUrl}/casa/${id}/dashboard`).subscribe({
      next: (data) => this.dashboardData.set(data),
      error: () => {}
    });
  }

  // ── Admin ─────────────────────────────────────────────────────────────────
  /** Datos del dashboard global de administración. */
  adminData = signal<any>(null);
  /** Indica si se está cargando el dashboard de administración. */
  isAdminLoading = signal<boolean>(false);

  /** Carga el dashboard global de administración y actualiza `adminData`. */
  loadAdminDashboard() {
    this.isAdminLoading.set(true);
    this.http.get<any>(`${this.apiUrl}/admin/dashboard`).subscribe({
      next: (data) => {
        this.adminData.set(data);
        this.isAdminLoading.set(false);
      },
      error: () => {
        this.adminData.set(null);
        this.isAdminLoading.set(false);
      }
    });
  }

  /**
   * Reset completo — llamar en logout para que el próximo
   * usuario no vea los datos cacheados del anterior.
   */
  reset() {
    this.dashboardData.set(null);
    this.adminData.set(null);
    this.isLoading.set(false);
    this.isAdminLoading.set(false);
  }
}
