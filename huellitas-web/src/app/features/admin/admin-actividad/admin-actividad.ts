import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { LucideAngularModule, Activity, Users, UserX, Clock, RefreshCw, BarChart } from 'lucide-angular';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../../environments/environment';

@Component({
  selector: 'app-admin-actividad',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  templateUrl: './admin-actividad.html'
})
/**
 * Panel de administración que resume la actividad de los usuarios de la
 * plataforma (conectados recientes, inactivos y cuentas desactivadas).
 */
export class AdminActividadComponent implements OnInit {
  private http = inject(HttpClient);

  Activity = Activity;
  Users = Users;
  UserX = UserX;
  Clock = Clock;
  RefreshCw = RefreshCw;
  BarChart = BarChart;

  actividad = signal<any>({
    conectados_24h: 0,
    conectados_7d: 0,
    inactivos_30d: 0,
    desactivados: 0
  });
  cargando = signal(true);

  ngOnInit() {
    this.cargarActividad();
  }

  /** Obtiene las métricas de actividad de usuarios para las gráficas del panel. */
  cargarActividad() {
    this.cargando.set(true);
    this.http.get<any>(`${environment.apiUrl}/admin/graficas-actividad`).subscribe({
      next: (res) => {
        if (res) this.actividad.set(res);
        this.cargando.set(false);
      },
      error: () => this.cargando.set(false)
    });
  }

  /** Suma usuarios conectados en la última semana, inactivos y desactivados. */
  getTotalUsuarios(): number {
    const a = this.actividad();
    return (a.conectados_7d || 0) + (a.inactivos_30d || 0) + (a.desactivados || 0);
  }
}
