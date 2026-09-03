import { Component, inject, OnInit, OnDestroy, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { LucideAngularModule, Users, Home, Cpu, CreditCard, RefreshCw, BarChart2, Wifi, WifiOff, AlertTriangle } from 'lucide-angular';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../../environments/environment';

@Component({
  selector: 'app-admin-dashboard',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  templateUrl: './admin-dashboard.html'
})
/**
 * Panel principal de administración: muestra las métricas globales de la
 * plataforma (casas, usuarios, dispositivos, suscripciones) y las gráficas
 * de registros por mes y dispositivos por casa.
 */
export class AdminDashboardComponent implements OnInit, OnDestroy {
  private http = inject(HttpClient);

  Users = Users;
  Home = Home;
  Cpu = Cpu;
  CreditCard = CreditCard;
  RefreshCw = RefreshCw;
  BarChart2 = BarChart2;
  Wifi = Wifi;
  WifiOff = WifiOff;
  AlertTriangle = AlertTriangle;

  stats = signal<any>({
    resumen: { total_casas: 0, total_usuarios_activos: 0, suscripciones_activas: 0, total_dispositivos: 0 },
    por_plan: []
  });
  isLoading = signal(true);

  // Chart 1: Registros por mes reales desde PostgreSQL
  registrosMes = signal<any[]>([]);

  // Chart 3: Dispositivos por casa, una tarjeta a la vez
  dispositivosCasa = signal<any[]>([]);
  casaActiva = signal(0);
  casaMostrada = computed(() => this.dispositivosCasa()[this.casaActiva()] ?? null);
  private _rotacionSub?: ReturnType<typeof setInterval>;

  /** Carga las métricas resumidas, los registros por mes y los dispositivos por casa. */
  ngOnInit() {
    this.cargarDashboard();
    this.cargarUsuariosPorMes();
    this.cargarDispositivos();
    // En escritorio no hay "deslizar" — la tarjeta rota sola. El clic en un
    // punto de abajo también funciona, para saltar directo a una vivienda.
    this._rotacionSub = setInterval(() => {
      const total = this.dispositivosCasa().length;
      if (total > 1) this.casaActiva.set((this.casaActiva() + 1) % total);
    }, 4000);
  }

  ngOnDestroy() {
    if (this._rotacionSub) clearInterval(this._rotacionSub);
  }

  /** Salta directamente a una vivienda del carrusel (clic en su punto indicador). */
  irACasa(indice: number) {
    this.casaActiva.set(indice);
  }

  /** Obtiene las métricas globales resumidas de la plataforma. */
  cargarDashboard() {
    this.isLoading.set(true);
    this.http.get<any>(`${environment.apiUrl}/admin/dashboard`).subscribe({
      next: (res) => {
        if (res) this.stats.set(res);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  /** Obtiene la cantidad de usuarios registrados por mes, para la gráfica de registros. */
  cargarUsuariosPorMes() {
    this.http.get<any[]>(`${environment.apiUrl}/admin/usuarios-por-mes`).subscribe({
      next: (res) => {
        this.registrosMes.set(res || []);
      },
      error: () => {}
    });
  }

  /**
   * Obtiene los dispositivos IoT de todas las viviendas y los agrupa por
   * casa para la gráfica correspondiente. El endpoint devuelve una fila por
   * dispositivo (con la casa y el propietario de cada uno) — antes cada fila
   * se dibujaba como su propia barra de "1 IoT", así que una vivienda con 9
   * aparatos aparecía como 9 barras repetidas en vez de una sola con el total real.
   */
  cargarDispositivos() {
    this.http.get<any[]>(`${environment.apiUrl}/admin/iot/dispositivos`).subscribe({
      next: (res) => {
        interface GrupoCasa {
          casaId: number; casa: string; propietario: string;
          total: number; enLinea: number; conProblema: number;
        }
        const porCasa = new Map<number, GrupoCasa>();
        for (const d of res || []) {
          const casaId = d.casa_id ?? 0;
          let grupo = porCasa.get(casaId);
          if (!grupo) {
            grupo = {
              casaId,
              casa: d.casa_nombre || 'Sin nombre',
              propietario: d.propietario_nombre || 'Sin propietario',
              total: 0, enLinea: 0, conProblema: 0,
            };
            porCasa.set(casaId, grupo);
          }
          grupo.total++;
          if (d.en_linea) grupo.enLinea++;
          if (d.problema) grupo.conProblema++;
        }
        this.dispositivosCasa.set(Array.from(porCasa.values()).sort((a, b) => b.total - a.total));
        this.casaActiva.set(0);
      },
      error: () => {}
    });
  }

  // Los siguientes getMax* devuelven el valor más alto de cada serie (mínimo 1)
  // para escalar las barras de las gráficas de barras simples del dashboard.
  getMaxPlanCount(): number {
    const plans = this.stats().por_plan || [];
    if (!plans.length) return 1;
    return Math.max(...plans.map((p: any) => p.total || 0), 1);
  }

  getMaxMonthCount(): number {
    if (!this.registrosMes().length) return 1;
    return Math.max(...this.registrosMes().map(m => m.total || 0), 1);
  }
}
