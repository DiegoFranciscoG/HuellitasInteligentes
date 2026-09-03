import { Component, signal, inject, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { LucideAngularModule, Cpu, Clock, Activity, Zap, Server } from 'lucide-angular';
import { AuthService } from '../../../core/services/auth.service';
import { environment } from '../../../../environments/environment';
import { Subscription, interval } from 'rxjs';

@Component({
  selector: 'app-historial-dispositivos',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  templateUrl: './historial-dispositivos.html'
})
/**
 * Muestra el historial de lecturas de sensores y comandos de actuadores
 * de los dispositivos IoT de la casa, seleccionables uno a la vez.
 */
export class HistorialDispositivos implements OnInit, OnDestroy {
  authService = inject(AuthService);
  http = inject(HttpClient);
  user = this.authService.currentUser;

  Cpu = Cpu;
  Clock = Clock;
  Activity = Activity;
  Zap = Zap;
  Server = Server;

  dispositivos = signal<any[]>([]);
  dispositivoSeleccionado = signal<number | null>(null);
  lecturas = signal<any[]>([]);
  actuadores = signal<any[]>([]);
  isLoading = signal(true);

  private pollSub?: Subscription;

  /**
   * Carga los dispositivos de la casa y arranca un sondeo cada 10 segundos
   * para refrescar el historial del dispositivo elegido — antes solo se
   * volvía a pedir al hacer clic en una pestaña, así que una acción hecha
   * en otra pantalla (o desde otro miembro de la casa) no se veía reflejada
   * aquí hasta recargar la página entera.
   */
  ngOnInit() {
    this.cargarDispositivos();
    this.pollSub = interval(10000).subscribe(() => {
      const id = this.dispositivoSeleccionado();
      if (id != null) this.cargarHistorial(id);
    });
  }

  ngOnDestroy() {
    this.pollSub?.unsubscribe();
  }

  /** Obtiene los dispositivos de la casa y selecciona automáticamente el primero. */
  cargarDispositivos() {
    if (!this.user()) return;
    this.isLoading.set(true);
    this.http.get<any[]>(`${environment.apiUrl}/dispositivo/casa`).subscribe({
      next: (data) => {
        this.dispositivos.set(this.etiquetar(data));
        if (data.length > 0) {
          this.seleccionarDispositivo(data[0].id);
        }
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  /**
   * Reduce el `modelo` real de cada dispositivo ("Ventana Cocina", "Luz
   * Comedor") a su primera palabra ("Ventana", "Luz"), y numera los que
   * comparten esa palabra clave (dos luces → "Luz 1"/"Luz 2"). El nombre de
   * la habitación no aporta nada para elegir un dispositivo en una lista tan
   * corta, y alarga las pestañas sin necesidad.
   */
  private etiquetar(dispositivos: any[]): any[] {
    const total = new Map<string, number>();
    for (const d of dispositivos) {
      const palabra = (d.modelo || '').trim().split(/\s+/)[0] || `Dispositivo #${d.id}`;
      total.set(palabra, (total.get(palabra) || 0) + 1);
    }
    const vistos = new Map<string, number>();
    return dispositivos.map(d => {
      const palabra = (d.modelo || '').trim().split(/\s+/)[0] || `Dispositivo #${d.id}`;
      if ((total.get(palabra) || 1) <= 1) return { ...d, etiqueta: palabra };
      const n = (vistos.get(palabra) || 0) + 1;
      vistos.set(palabra, n);
      return { ...d, etiqueta: `${palabra} ${n}` };
    });
  }

  /**
   * Selecciona un dispositivo y carga su historial de lecturas y de comandos de actuadores.
   * @param id Identificador del dispositivo.
   */
  seleccionarDispositivo(id: number) {
    this.dispositivoSeleccionado.set(id);
    this.cargarHistorial(id);
  }

  /** Pide de nuevo las lecturas y los comandos del dispositivo indicado. */
  private cargarHistorial(id: number) {
    this.http.get<any[]>(`${environment.apiUrl}/dispositivo/${id}/historial`).subscribe({
      next: (data) => this.lecturas.set(data),
      error: () => this.lecturas.set([])
    });
    this.http.get<any[]>(`${environment.apiUrl}/dispositivo/${id}/actuadores`).subscribe({
      next: (data) => this.actuadores.set(data),
      error: () => this.actuadores.set([])
    });
  }
}
