import { Component, signal, inject, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { LucideAngularModule, Check, Crown, Shield } from 'lucide-angular';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { AuthService } from '../../core/services/auth.service';

@Component({
  selector: 'app-planes',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  templateUrl: './planes.html',
})
/**
 * Muestra los planes de suscripción disponibles y gestiona el cambio de
 * plan de la casa del usuario: planes gratuitos se aplican directo y los
 * de pago se procesan a través de la pasarela Stripe.
 */
export class Planes implements OnInit {
  private http = inject(HttpClient);
  private authService = inject(AuthService);
  user = this.authService.currentUser;
  
  Check = Check;
  Crown = Crown;
  Shield = Shield;

  planes = signal<any[]>([]);
  planActualId = signal<number>(1);
  isLoading = signal(true);
  mensajePlan = signal('');

  /** Carga el catálogo de planes, el plan actual de la casa y resuelve un posible retorno desde Stripe. */
  ngOnInit() {
    this.cargarPlanesReales();
    this.cargarMiPlan();
    this.procesarRetornoDePago();
  }

  /** Obtiene el catálogo de planes activos disponibles para contratar. */
  cargarPlanesReales() {
    this.http.get<any[]>(`${environment.apiUrl}/planes/activos`).subscribe({
      next: (data) => {
        this.planes.set(data || []);
      },
      error: (err) => console.error('Error al cargar planes reales', err)
    });
  }

  /** Obtiene el plan actualmente contratado por la casa del usuario. */
  cargarMiPlan() {
    this.isLoading.set(true);
    const token = this.authService.getToken();
    const headers = new HttpHeaders({ 'Authorization': `Bearer ${token || ''}` });

    this.http.get<any>(`${environment.apiUrl}/planes/mi-plan`, { headers }).subscribe({
      next: (res) => {
        if (res && res.plan_id) {
          this.planActualId.set(Number(res.plan_id));
        }
        this.isLoading.set(false);
      },
      error: () => {
        this.isLoading.set(false);
      }
    });
  }

  /**
   * Los planes de pago pasan por Stripe: se pide una sesión de cobro y se
   * envía al usuario a pagar. Solo los planes gratuitos se cambian directo.
   * El precio lo decide el servidor leyéndolo de la base (el que fije el
   * administrador, incluida la oferta), nunca el navegador.
   */
  seleccionarPlan(id: number) {
    if (this.planActualId() === id) return;

    this.isLoading.set(true);
    this.mensajePlan.set('');
    const token = this.authService.getToken();
    const headers = new HttpHeaders({ 'Authorization': `Bearer ${token || ''}` });

    this.http.post<any>(`${environment.apiUrl}/pagos/checkout?planId=${id}`, {}, { headers }).subscribe({
      next: (res) => {
        if (res?.gratuito) {
          this.cambiarPlanGratuito(id, headers);
          return;
        }
        if (res?.url) {
          this.mensajePlan.set('Redirigiendo a la pasarela de pago segura...');
          window.location.href = res.url;
          return;
        }
        this.mensajePlan.set('No se pudo iniciar el pago. Inténtalo de nuevo.');
        this.isLoading.set(false);
      },
      error: (err) => {
        this.mensajePlan.set('Error al iniciar el pago: ' + (err.error?.error || 'Inténtalo de nuevo.'));
        this.isLoading.set(false);
      }
    });
  }

  /**
   * Aplica de inmediato un cambio a un plan gratuito (sin pasar por Stripe).
   * @param id Identificador del plan gratuito destino.
   * @param headers Cabeceras con el token de autorización.
   */
  private cambiarPlanGratuito(id: number, headers: HttpHeaders) {
    this.http.post<any>(`${environment.apiUrl}/planes/cambiar`, { planId: id }, { headers }).subscribe({
      next: () => {
        this.planActualId.set(id);
        this.mensajePlan.set('Tu suscripción se actualizó correctamente.');
        this.cargarMiPlan();
        setTimeout(() => this.mensajePlan.set(''), 4000);
      },
      error: (err) => {
        this.mensajePlan.set('Error al cambiar de plan: ' + (err.error?.error || 'Inténtalo de nuevo.'));
        this.isLoading.set(false);
      }
    });
  }

  /** Al volver de Stripe, se confirma el cobro contra el servidor. */
  private procesarRetornoDePago() {
    const params = new URLSearchParams(window.location.search);
    const estado = params.get('pago');
    const sessionId = params.get('session_id');

    if (estado === 'cancelado') {
      this.mensajePlan.set('Pago cancelado. Tu plan no cambió.');
      setTimeout(() => this.mensajePlan.set(''), 5000);
      history.replaceState({}, '', '/planes');
      return;
    }

    if (estado === 'ok' && sessionId) {
      this.isLoading.set(true);
      const token = this.authService.getToken();
      const headers = new HttpHeaders({ 'Authorization': `Bearer ${token || ''}` });

      this.http.post<any>(`${environment.apiUrl}/pagos/confirmar?sessionId=${sessionId}`, {}, { headers })
        .subscribe({
          next: () => {
            this.mensajePlan.set('¡Pago confirmado! Tu plan ya está activo.');
            this.cargarMiPlan();
            setTimeout(() => this.mensajePlan.set(''), 6000);
          },
          error: (err) => {
            this.mensajePlan.set('No se pudo confirmar el pago: ' + (err.error?.error || 'Contacta con soporte.'));
            this.isLoading.set(false);
          }
        });
      history.replaceState({}, '', '/planes');
    }
  }
}
