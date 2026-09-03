import { Component, inject, OnInit, OnDestroy, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { LucideAngularModule, Dog, CheckCircle2, ArrowRight, Star, X } from 'lucide-angular';
import { interval, Subscription } from 'rxjs';
import { DashboardService } from '../../../core/services/dashboard.service';
import { AuthService } from '../../../core/services/auth.service';
import { CountUpDirective } from '../../../shared/directives/count-up.directive';
import { MediaUrlPipe } from '../../../shared/pipes/media-url.pipe';

@Component({
  selector: 'app-propietario-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink, LucideAngularModule, CountUpDirective, MediaUrlPipe],
  templateUrl: './propietario-dashboard.html',
})
/**
 * Panel principal del propietario/miembro: muestra el resumen de su casa
 * (mascotas, dispositivos activos, alertas y plan contratado) y permite
 * establecer una contraseña cuando la cuenta aún no tiene una (por ejemplo,
 * cuentas creadas vía OAuth o QR).
 */
export class PropietarioDashboardComponent implements OnInit, OnDestroy {
  dashboardService = inject(DashboardService);
  authService = inject(AuthService);

  data = this.dashboardService.dashboardData;
  isLoading = this.dashboardService.isLoading;
  tienePassword = signal(true);
  isSettingPassword = signal(false);
  newPassword = signal('');
  passwordError = signal('');

  Dog = Dog;
  CheckCircle2 = CheckCircle2;
  ArrowRight = ArrowRight;
  Star = Star;
  X = X;

  private _refrescoSub?: Subscription;

  /**
   * Carga el dashboard de la casa del usuario (si no estaba ya cargado en
   * el servicio) y consulta si la cuenta ya tiene contraseña establecida.
   * El "Resumen del Ecosistema" (alertas pendientes, dispositivos activos)
   * necesita reflejar el estado real aunque el usuario se quede quieto en
   * esta pantalla, así que se refresca solo cada 20s, sin el parpadeo de
   * carga completa que tendría llamar a loadDashboardCasa de nuevo.
   */
  ngOnInit() {
    const casaId = this.authService.currentUser()?.casa_id;
    if (!this.data()) {
      this.dashboardService.loadDashboardCasa(casaId);
    }
    this.authService.tienePassword().subscribe({
      next: (res) => this.tienePassword.set(res.tiene_password),
      error: () => this.tienePassword.set(true)
    });
    this._refrescoSub = interval(20_000).subscribe(() => {
      this.dashboardService.refreshDashboardCasaSilencioso(casaId);
    });
  }

  ngOnDestroy() {
    this._refrescoSub?.unsubscribe();
  }

  /** Valida y envía la nueva contraseña ingresada por el usuario para establecerla en su cuenta. */
  establecerPassword() {
    if (this.newPassword().length < 6) {
      this.passwordError.set('Mínimo 6 caracteres');
      return;
    }
    this.isSettingPassword.set(true);
    this.authService.establecerPassword(this.newPassword()).subscribe({
      next: () => {
        this.tienePassword.set(true);
        this.isSettingPassword.set(false);
      },
      error: () => {
        this.passwordError.set('Error al establecer contraseña');
        this.isSettingPassword.set(false);
      }
    });
  }

  // helper to get a count from array length
  /** Cantidad de dispositivos en estado ACTIVO de la casa. */
  get dispositivosActivos() {
    if (!this.data()?.dispositivos) return 0;
    return this.data()?.dispositivos.filter((d: any) => d.estado === 'ACTIVO').length || 0;
  }

  /**
   * Altura de la barra de un dispositivo en la gráfica de "Actividad de
   * Dispositivos", como % relativo al mayor valor del grupo — no un % fijo
   * sobre 100, que no tiene sentido para sensores con escalas distintas
   * (22.5°C de temperatura vs. 82% de un sensor de nivel).
   */
  barHeight(disp: any): number {
    const valores = (this.data()?.dispositivos || [])
      .map((d: any) => Number(d.ultimo_valor))
      .filter((v: number) => Number.isFinite(v) && v > 0);
    const max = valores.length ? Math.max(...valores) : 0;
    const val = Number(disp.ultimo_valor);
    if (!max || !Number.isFinite(val) || val <= 0) return 8;
    return Math.max(8, Math.round((val / max) * 100));
  }

  /**
   * Precio del plan contratado, ya formateado. Se usa la oferta cuando el
   * administrador la tiene puesta, igual que en la pantalla de planes; si no
   * hay suscripción todavía, el plan es gratuito y el importe es 0.
   */
  precioPlan(): string {
    const plan = this.data()?.plan;
    const oferta = Number(plan?.precio_oferta ?? 0);
    const mensual = Number(plan?.precio_mensual ?? 0);
    const precio = oferta > 0 ? oferta : mensual;
    return Number.isFinite(precio) ? precio.toFixed(2) : '0.00';
  }

  /** Precio de lista, el que se tacha cuando hay oferta vigente. */
  precioBase(): string {
    const mensual = Number(this.data()?.plan?.precio_mensual ?? 0);
    return Number.isFinite(mensual) ? mensual.toFixed(2) : '0.00';
  }

  /** Indica si el plan contratado tiene una oferta vigente (precio de oferta menor al mensual). */
  tieneOferta(): boolean {
    const plan = this.data()?.plan;
    const oferta = Number(plan?.precio_oferta ?? 0);
    return oferta > 0 && Number(plan?.precio_mensual ?? 0) > oferta;
  }

  /**
   * Calcula la edad en años de una mascota a partir de su fecha de nacimiento.
   * @param fechaNacimiento Fecha de nacimiento en formato ISO.
   * @returns Edad formateada (ej. "1 año" o "3 años"), o cadena vacía si no hay fecha.
   */
  calcularEdad(fechaNacimiento: string): string {
    if (!fechaNacimiento) return '';
    const nac = new Date(fechaNacimiento);
    const hoy = new Date();
    let edad = hoy.getFullYear() - nac.getFullYear();
    const m = hoy.getMonth() - nac.getMonth();
    if (m < 0 || (m === 0 && hoy.getDate() < nac.getDate())) {
      edad--;
    }
    return edad === 1 ? '1 año' : `${edad} años`;
  }
}
