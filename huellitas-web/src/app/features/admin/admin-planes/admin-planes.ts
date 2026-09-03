import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LucideAngularModule, Crown, Check, Shield, Layers, Plus, Edit, Trash2, Power, Tag } from 'lucide-angular';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../../environments/environment';
import { AuthService } from '../../../core/services/auth.service';
import { ConfirmService } from '../../../core/services/confirm.service';

@Component({
  selector: 'app-admin-planes',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
  templateUrl: './admin-planes.html',
})
/**
 * Administración del catálogo de planes de suscripción: creación, edición,
 * activación/desactivación y descontinuación de planes, con notificación
 * automática a los usuarios afectados.
 */
export class AdminPlanesComponent implements OnInit {
  private http = inject(HttpClient);
  private authService = inject(AuthService);
  private confirmService = inject(ConfirmService);

  user = this.authService.currentUser;

  Crown = Crown;
  Check = Check;
  Shield = Shield;
  Layers = Layers;
  Plus = Plus;
  Edit = Edit;
  Trash2 = Trash2;
  Power = Power;
  Tag = Tag;

  planes = signal<any[]>([]);
  isLoading = signal(true);
  mensaje = signal('');

  // State Modals
  modalCrearOpen = signal(false);
  modalEditarOpen = signal(false);

  // Form State Plan
  planEditar = signal<any>(null);
  tipoPlan = signal('FREE');
  nuevoNombre = signal('FREE');
  nuevoPrecio = signal<number>(0);
  precioOferta = signal<number | null>(null);
  descuentoPct = signal<number>(0);
  /**
   * Cuántas mascotas puede registrar una casa con este plan — el único
   * límite que el sistema realmente aplica (lo comprueba el servidor al dar
   * de alta una mascota). El límite de dispositivos existe en la base por
   * compatibilidad, pero nunca se valida: la casa registra los dispositivos
   * y cámaras que quiera, así que no se expone aquí.
   */
  limiteMascotas = signal<number>(2);
  limiteDispositivos = signal<number>(5);
  limiteAlmacenamientoMb = signal<number>(1000);
  descripcionPlan = signal('');

  ngOnInit() {
    this.cargarPlanes();
  }

  /** Obtiene el catálogo completo de planes (activos e inactivos). */
  cargarPlanes() {
    this.isLoading.set(true);
    this.http.get<any[]>(`${environment.apiUrl}/admin/planes`).subscribe({
      next: (data) => {
        this.planes.set(data || []);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  /**
   * Sincroniza el nombre del plan con el tipo elegido en el selector; si se
   * elige "OTRO", deja el nombre en blanco para que el administrador lo escriba.
   * @param val Tipo de plan seleccionado (`FREE`, `PREMIUM`, `VIP` u `OTRO`).
   */
  onTipoPlanChange(val: string) {
    this.tipoPlan.set(val);
    if (val !== 'OTRO') {
      this.nuevoNombre.set(val);
    } else {
      this.nuevoNombre.set('');
    }
  }

  /**
   * Precio base, precio de oferta y porcentaje de descuento son tres formas
   * de decir lo mismo, así que se mantienen coordinados entre sí: cambiar
   * cualquiera de los tres recalcula los otros dos. Antes eran campos
   * independientes y se podía guardar, por ejemplo, precio base $5, oferta
   * $1.99 y descuento 30% — que no cuadran entre sí (30% de $5 son $3.50).
   */
  onPrecioBaseChange(valor: number) {
    this.nuevoPrecio.set(valor);
    if (this.descuentoPct() > 0) {
      this.recalcularOfertaDesdeDescuento();
    } else if (this.precioOferta() !== null) {
      this.recalcularDescuentoDesdeOferta();
    }
  }

  /** El admin fija el precio final de oferta; el % de descuento se deduce de él. */
  onOfertaChange(valor: number | null) {
    this.precioOferta.set(valor);
    if (valor === null || valor === undefined || (valor as any) === '') {
      this.descuentoPct.set(0);
      return;
    }
    this.recalcularDescuentoDesdeOferta();
  }

  /** El admin fija el % de descuento; el precio final de oferta se deduce de él. */
  onDescuentoChange(valor: number) {
    this.descuentoPct.set(valor);
    if (!valor || valor <= 0) {
      this.precioOferta.set(null);
      this.descuentoPct.set(0);
      return;
    }
    this.recalcularOfertaDesdeDescuento();
  }

  private recalcularOfertaDesdeDescuento() {
    const base = this.nuevoPrecio();
    const pct = this.descuentoPct();
    if (base <= 0 || pct <= 0) return;
    const pctClamp = Math.min(pct, 100);
    if (pctClamp !== pct) this.descuentoPct.set(pctClamp);
    this.precioOferta.set(Math.round(base * (1 - pctClamp / 100) * 100) / 100);
  }

  private recalcularDescuentoDesdeOferta() {
    const base = this.nuevoPrecio();
    const oferta = this.precioOferta();
    if (base <= 0 || oferta === null || oferta === undefined) return;
    if (oferta >= base) {
      // Un precio de "oferta" que no baja el precio no es una oferta.
      this.precioOferta.set(null);
      this.descuentoPct.set(0);
      return;
    }
    this.descuentoPct.set(Math.round((1 - oferta / base) * 100));
  }

  /** Abre el modal de creación de plan con valores por defecto. */
  abrirCrear() {
    this.tipoPlan.set('FREE');
    this.nuevoNombre.set('FREE');
    this.nuevoPrecio.set(9.99);
    this.precioOferta.set(null);
    this.descuentoPct.set(0);
    this.limiteMascotas.set(2);
    this.limiteDispositivos.set(5);
    this.limiteAlmacenamientoMb.set(1000);
    this.descripcionPlan.set('');
    this.modalCrearOpen.set(true);
  }

  /**
   * Abre el modal de edición de un plan, precargando el formulario con sus
   * valores actuales.
   * @param plan Plan a editar.
   */
  abrirEditar(plan: any) {
    this.planEditar.set(plan);
    const nombreUpper = plan.nombre.toUpperCase();
    if (['FREE', 'PREMIUM', 'VIP'].includes(nombreUpper)) {
      this.tipoPlan.set(nombreUpper);
    } else {
      this.tipoPlan.set('OTRO');
    }
    this.nuevoNombre.set(plan.nombre);
    this.nuevoPrecio.set(parseFloat(plan.precio_mensual || 0));
    this.precioOferta.set(plan.precio_oferta ? parseFloat(plan.precio_oferta) : null);
    this.descuentoPct.set(plan.descuento_porcentaje ? parseFloat(plan.descuento_porcentaje) : 0);
    this.limiteMascotas.set(plan.limite_mascotas ?? 2);
    this.descripcionPlan.set(plan.descripcion || '');
    this.modalEditarOpen.set(true);
  }

  /** Cierra los modales de creación y edición de plan. */
  cerrarModales() {
    this.modalCrearOpen.set(false);
    this.modalEditarOpen.set(false);
    this.planEditar.set(null);
  }

  /** Crea un nuevo plan con los datos del formulario. */
  guardarNuevoPlan() {
    if (!this.nuevoNombre().trim()) return;

    const payload = {
      adminId: this.user()?.id ?? null,
      nombre: this.nuevoNombre().trim(),
      precioMensual: this.nuevoPrecio(),
      precioOferta: this.precioOferta(),
      descuentoPorcentaje: this.descuentoPct(),
      limiteMascotas: this.limiteMascotas(),
      limiteDispositivos: this.limiteDispositivos(),
      limiteAlmacenamientoMb: this.limiteAlmacenamientoMb(),
      descripcion: this.descripcionPlan().trim()
    };

    this.http.post<any>(`${environment.apiUrl}/admin/planes`, payload).subscribe({
      next: () => {
        this.mensaje.set('Plan creado exitosamente.');
        this.cerrarModales();
        this.cargarPlanes();
        setTimeout(() => this.mensaje.set(''), 3000);
      },
      error: (err) => {
        this.mensaje.set('Error: ' + (err.error?.message || err.message));
        setTimeout(() => this.mensaje.set(''), 3000);
      }
    });
  }

  /** Envía los cambios del plan en edición y notifica a los usuarios suscritos a él. */
  guardarEdicionPlan() {
    if (!this.planEditar()) return;

    const payload = {
      nombre: this.nuevoNombre().trim(),
      precioMensual: this.nuevoPrecio(),
      precioOferta: this.precioOferta(),
      descuentoPorcentaje: this.descuentoPct(),
      limiteMascotas: this.limiteMascotas(),
      descripcion: this.descripcionPlan().trim()
    };

    const id = this.planEditar().id;
    this.http.put<any>(`${environment.apiUrl}/admin/planes/${id}`, payload).subscribe({
      next: () => {
        this.mensaje.set('Plan actualizado y usuarios del plan notificados.');
        this.cerrarModales();
        this.cargarPlanes();
        setTimeout(() => this.mensaje.set(''), 4000);
      },
      error: (err) => {
        this.mensaje.set('Error: ' + (err.error?.message || err.message));
        setTimeout(() => this.mensaje.set(''), 4000);
      }
    });
  }

  /**
   * Pide confirmación y activa o desactiva la disponibilidad de un plan
   * para nuevas contrataciones.
   * @param plan Plan a activar/desactivar.
   */
  async alternarEstadoPlan(plan: any) {
    const accion = plan.activo ? 'desactivar' : 'activar';
    const ok = await this.confirmService.ask({
      titulo: `${plan.activo ? 'Desactivar' : 'Activar'} Plan`,
      mensaje: `¿Estás seguro de ${accion} el plan "${plan.nombre}"?`,
      textoConfirmar: 'Sí, continuar',
      textoCancelar: 'Cancelar'
    });

    if (!ok) return;

    this.http.put<any>(`${environment.apiUrl}/admin/planes/${plan.id}/toggle`, {}).subscribe({
      next: () => {
        this.mensaje.set(`Plan "${plan.nombre}" ${plan.activo ? 'desactivado' : 'activado'} correctamente.`);
        this.cargarPlanes();
        setTimeout(() => this.mensaje.set(''), 3000);
      },
      error: (err) => {
        this.mensaje.set('Error: ' + (err.error?.message || err.message));
        setTimeout(() => this.mensaje.set(''), 3000);
      }
    });
  }

  /**
   * Pide confirmación y descontinúa un plan, notificando a los propietarios
   * suscritos a él.
   * @param plan Plan a descontinuar.
   */
  async eliminarPlan(plan: any) {
    const ok = await this.confirmService.ask({
      titulo: 'Descontinuar Plan',
      mensaje: `¿Deseas descontinuar el plan "${plan.nombre}"? Se enviará un aviso automático a todos los propietarios suscritos.`,
      textoConfirmar: 'Descontinuar Plan',
      textoCancelar: 'Cancelar'
    });

    if (!ok) return;

    this.http.delete<any>(`${environment.apiUrl}/admin/planes/${plan.id}`).subscribe({
      next: () => {
        this.mensaje.set(`Plan "${plan.nombre}" descontinuado y usuarios notificados.`);
        this.cargarPlanes();
        setTimeout(() => this.mensaje.set(''), 4000);
      },
      error: (err) => {
        this.mensaje.set('Error: ' + (err.error?.message || err.message));
        setTimeout(() => this.mensaje.set(''), 4000);
      }
    });
  }
}
