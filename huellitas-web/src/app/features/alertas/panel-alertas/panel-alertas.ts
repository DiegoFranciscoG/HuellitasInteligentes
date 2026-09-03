import { Component, signal, OnInit, inject, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { LucideAngularModule, Droplets, Thermometer, CookingPot, WifiOff, Wind, DownloadCloud, AlertTriangle, CheckCheck, RefreshCw, Activity } from 'lucide-angular';
import { AuthService } from '../../../core/services/auth.service';
import { AlertaService } from '../../../core/services/alerta.service';

/** Alerta generada por el sistema o un dispositivo IoT de la casa. */
interface Alerta {
  id: number;
  severidad: 'CRITICA' | 'ADVERTENCIA' | 'INFO';
  mensaje: string;
  ts: string;
  leida: boolean;
  /** Tipo real del backend (IOT_OFFLINE, IOT_CRITICO, TEMPERATURA...). */
  tipo?: string | null;
  /** Dispositivo al que se refiere la alerta, si viene de uno. */
  dispositivo_id?: number | null;
}

@Component({
  selector: 'app-panel-alertas',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  templateUrl: './panel-alertas.html',
})
/**
 * Muestra las alertas de la casa del usuario (dispositivos, conectividad,
 * etc.), con filtro de leídas/no leídas y un ícono contextual según el
 * contenido del mensaje.
 */
export class PanelAlertas implements OnInit {
  private alertaService = inject(AlertaService);
  private authService = inject(AuthService);
  private router = inject(Router);

  user = this.authService.currentUser;

  isLoading = signal(true);
  errorMsg = signal('');
  filtroActual = signal<'TODAS' | 'NO_LEIDAS'>('TODAS');
  alertas = signal<Alerta[]>([]);

  // Icons
  Droplets = Droplets;
  Thermometer = Thermometer;
  CookingPot = CookingPot;
  WifiOff = WifiOff;
  Wind = Wind;
  DownloadCloud = DownloadCloud;
  AlertTriangle = AlertTriangle;
  CheckCheck = CheckCheck;
  RefreshCw = RefreshCw;
  Activity = Activity;

  /** Carga las alertas de la casa del usuario. */
  ngOnInit() {
    this.cargarAlertas();
  }

  /** Obtiene las alertas de la casa del usuario en sesión. */
  cargarAlertas() {
    const casaId = this.user()?.casa_id;
    if (!casaId) {
      this.errorMsg.set('No hay casa asociada a este usuario.');
      this.isLoading.set(false);
      return;
    }

    this.isLoading.set(true);
    this.errorMsg.set('');

    this.alertaService.buscarAlertas(casaId).subscribe({
      next: (raw) => {
        // fn_buscar_alertas devuelve JSON — puede ser string o array
        const data: Alerta[] = typeof raw === 'string' ? JSON.parse(raw) : raw;
        this.alertas.set(Array.isArray(data) ? data : []);
        this.isLoading.set(false);
      },
      error: (err) => {
        this.errorMsg.set('No se pudieron cargar las alertas: ' + (err.error?.message || err.message));
        this.isLoading.set(false);
      }
    });
  }

  /**
   * Elige el ícono de una alerta. El campo `tipo` que manda el backend es un
   * dato exacto, así que manda sobre la búsqueda por palabras del mensaje,
   * que solo se usa como respaldo para las alertas que no traen tipo.
   * @param alerta La alerta completa.
   */
  getIcon(alerta: Alerta) {
    const tipo = (alerta.tipo || '').toUpperCase();
    if (tipo === 'IOT_OFFLINE' || tipo === 'IOT_NUNCA_CONECTO') return this.WifiOff;
    if (tipo === 'IOT_CRITICO') return this.AlertTriangle;
    if (tipo === 'TEMPERATURA') return this.Thermometer;
    if (tipo === 'MOVIMIENTO') return this.Activity;

    const m = (alerta.mensaje || '').toLowerCase();
    if (m.includes('agua')) return this.Droplets;
    if (m.includes('temperatura')) return this.Thermometer;
    if (m.includes('alimento')) return this.CookingPot;
    if (m.includes('conexi')) return this.WifiOff;
    if (m.includes('aire') || m.includes('viento')) return this.Wind;
    if (m.includes('firmware') || m.includes('actualizaci')) return this.DownloadCloud;
    return this.AlertTriangle;
  }

  /**
   * Si la alerta viene de un dispositivo, lleva al panel de dispositivos —el
   * destino real más cercano a "ver qué pasa con ese aparato", igual que en
   * la aplicación móvil. No hay pantalla de detalle por dispositivo todavía.
   */
  abrirDispositivoDeAlerta(alerta: Alerta) {
    if (!alerta.dispositivo_id) return;
    this.router.navigate(['/dispositivos']);
  }

  /** Alertas visibles según el filtro actual (todas o solo no leídas). */
  get filtradas(): Alerta[] {
    const data = this.alertas();
    if (this.filtroActual() === 'TODAS') return data;
    return data.filter(a => !a.leida);
  }

  /** Cantidad de alertas no leídas. */
  get nuevasCount(): number {
    return this.alertas().filter(a => !a.leida).length;
  }

  /**
   * Marca una alerta como leída, tanto en el servidor como en el estado local.
   * @param id Identificador de la alerta.
   */
  marcarLeida(id: number) {
    this.alertaService.marcarLeida(id).subscribe({
      next: () => {
        this.alertas.update(list => list.map(a => a.id === id ? { ...a, leida: true } : a));
      },
      error: (err) => console.error('Error al marcar leída:', err)
    });
  }

  /** Marca como leídas todas las alertas pendientes de la casa. */
  marcarTodasLeidas() {
    const noLeidas = this.alertas().filter(a => !a.leida);
    noLeidas.forEach(a => this.marcarLeida(a.id));
  }
}
