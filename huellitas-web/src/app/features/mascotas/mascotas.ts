import { Component, inject, OnInit, computed, signal, effect } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { LucideAngularModule, Dog, Bone, HeartPulse, Plus, X, Camera, Calendar, Scale, Save, Trash2 } from 'lucide-angular';
import { DashboardService } from '../../core/services/dashboard.service';
import { AuthService } from '../../core/services/auth.service';
import { environment } from '../../../environments/environment';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { CustomValidators } from '../../core/utils/custom-validators';
import { MediaUrlPipe } from '../../shared/pipes/media-url.pipe';

@Component({
  selector: 'app-mascotas',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule, MediaUrlPipe],
  templateUrl: './mascotas.html',
})
/**
 * Gestiona el registro, edición, consulta y eliminación de las mascotas
 * (perros) de la casa del usuario, incluyendo la validación del formulario
 * de alta y el control del límite de mascotas según el plan contratado.
 */
export class MascotasComponent implements OnInit {
  dashboardService = inject(DashboardService);
  authService = inject(AuthService);
  confirmService = inject(ConfirmService);
  toastService = inject(ToastService);
  http = inject(HttpClient);
  
  private _perrosCache = signal<any[]>([]);
  /** Lista de mascotas de la casa actual, en solo lectura. */
  perros = this._perrosCache.asReadonly();
  isLoading = this.dashboardService.isLoading;
  user = this.authService.currentUser;

  constructor() {
    // effect() es la forma correcta de reaccionar a cambios de señal en Angular
    // Mantiene _perrosCache sincronizada cada vez que cambian los datos del dashboard.
    effect(() => {
      const data = this.dashboardService.dashboardData()?.perros;
      if (Array.isArray(data)) {
        this._perrosCache.set(data);
      }
    });
  }

  mostrarForm = signal(false);
  nombre = signal('');
  raza = signal('');
  fechaNacimiento = signal('');
  peso = signal<number | null>(null);
  fotoUrl = signal<string>(''); // Para preview en UI
  selectedFile: File | null = null; // Para envío al backend

  mascotaDetalle = signal<any>(null);
  nuevaFotoDetalle = signal<string>(''); // Para preview en UI
  selectedFotoDetalle: File | null = null; // Para envío al backend
  isSaving = signal(false);
  confirmandoEliminacion = signal(false);

  // Plan info: límite de mascotas según plan activo
  /** Nombre del plan activo, límite de mascotas permitido y cantidad actual registrada. */
  planInfo = computed(() => {
    const d = this.dashboardService.dashboardData();
    return {
      nombre:  d?.plan?.nombre  || 'FREE',
      limite:  d?.plan?.limite_mascotas ?? 2,
      total:   this._perrosCache().length
    };
  });
  /** `true` cuando la casa ya alcanzó el límite de mascotas de su plan. */
  limitAlcanzado = computed(() => this.planInfo().total >= this.planInfo().limite);

  Dog = Dog;
  Bone = Bone;
  HeartPulse = HeartPulse;
  Plus = Plus;
  X = X;
  Camera = Camera;
  Trash2 = Trash2;
  Calendar = Calendar;
  Scale = Scale;
  Save = Save;

  // Validaciones en vivo del formulario de alta: cada campo expone su propio
  // mensaje de error (cadena vacía si es válido) para pintarlo junto al input.
  errorNombre = computed(() => {
    const v = this.nombre().trim();
    if (!v) return 'El nombre es obligatorio.';
    if (v.length < 2) return 'El nombre debe tener al menos 2 caracteres.';
    if (!/^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]+$/.test(v)) return 'El nombre solo debe contener letras y espacios (sin números).';
    return '';
  });

  errorRaza = computed(() => {
    const v = this.raza().trim();
    if (!v) return 'La raza es obligatoria.';
    if (v.length < 2) return 'La raza debe tener al menos 2 caracteres.';
    if (!/^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]+$/.test(v)) return 'La raza solo debe contener letras y espacios (sin números).';
    return '';
  });

  errorPeso = computed(() => {
    const p = this.peso();
    if (p === null || p === undefined || isNaN(p as any)) return 'El peso es obligatorio.';
    if (p <= 0) return 'El peso debe ser mayor a 0 kg.';
    if (p > 150) return 'El peso no puede exceder los 150 kg.';
    return '';
  });

  errorFecha = computed(() => {
    const f = this.fechaNacimiento();
    if (!f) return 'La fecha de nacimiento es obligatoria.';
    const date = new Date(f);
    const now = new Date();
    if (date > now) return 'La fecha de nacimiento no puede ser futura.';
    const maxAge = new Date();
    maxAge.setFullYear(now.getFullYear() - 25);
    if (date < maxAge) return 'La fecha de nacimiento no puede exceder los 25 años.';
    return '';
  });

  /** `true` si algún campo del formulario de alta tiene un error de validación. */
  formInvalido = computed(() => {
    return !!(this.errorNombre() || this.errorRaza() || this.errorPeso() || this.errorFecha());
  });

  ngOnInit() {
    const casaId = this.user()?.casa_id;
    if (casaId) {
      // Siempre recargar con el casaId correcto al navegar a esta página
      this.dashboardService.loadDashboardCasa(casaId);
    }
  }

  /**
   * Valida y previsualiza la foto elegida para una mascota nueva (máx. 5MB,
   * formatos JPG/PNG/WEBP), guardándola para el envío posterior del formulario.
   * @param event Evento `change` del input de tipo archivo.
   */
  onFotoSelected(event: any) {
    const file = event.target.files[0];
    if (file) {
      if (file.size > 5 * 1024 * 1024) {
        this.toastService.error('La foto debe ser menor a 5MB.', 'Archivo muy grande');
        return;
      }
      const validTypes = ['image/jpeg', 'image/png', 'image/webp'];
      if (!validTypes.includes(file.type)) {
        this.toastService.error('Formato no permitido. Solo imágenes JPG, PNG o WEBP.', 'Formato no soportado');
        return;
      }
      this.selectedFile = file;
      const reader = new FileReader();
      reader.onload = (e: any) => this.fotoUrl.set(e.target.result);
      reader.readAsDataURL(file);
    }
  }

  /**
   * Envía el formulario de alta de mascota al backend (con la foto, si se
   * seleccionó una) y, si tiene éxito, limpia el formulario y recarga el
   * dashboard de la casa para reflejar la nueva mascota.
   */
  registrarMascota() {
    if (this.formInvalido()) {
      this.toastService.error('Por favor corrige los errores del formulario antes de continuar.', 'Formulario inválido');
      return;
    }

    const casaId = this.user()?.casa_id || 16;
    const formData = new FormData();
    formData.append('casaId', casaId.toString());
    formData.append('nombre', CustomValidators.capitalizeText(this.nombre().trim()));
    formData.append('raza', CustomValidators.capitalizeText(this.raza().trim()));
    formData.append('fechaNacimiento', this.fechaNacimiento());
    if (this.peso() !== null) {
      formData.append('peso', this.peso()!.toString());
    }
    if (this.selectedFile) {
      formData.append('file', this.selectedFile);
    }
    
    this.http.post(`${environment.apiUrl}/perro`, formData).subscribe({
      next: () => {
        this.toastService.success(`Mascota "${this.nombre()}" registrada exitosamente.`, 'Mascota Agregada');
        this.nombre.set('');
        this.raza.set('');
        this.fechaNacimiento.set('');
        this.peso.set(null);
        this.fotoUrl.set('');
        this.selectedFile = null;
        this.mostrarForm.set(false);
        this.dashboardService.loadDashboardCasa(this.user()?.casa_id || undefined);
      },
      error: (err) => this.toastService.error('Error al registrar mascota: ' + (err.error?.message || err.message))
    });
  }

  /** Abre el panel de detalle de una mascota. */
  verDetalle(perro: any) {
    this.mascotaDetalle.set(perro);
    this.nuevaFotoDetalle.set(perro.foto_url || '');
  }

  /** Cierra el panel de detalle y descarta cualquier cambio de foto sin guardar. */
  cerrarDetalle() {
    this.mascotaDetalle.set(null);
    this.nuevaFotoDetalle.set('');
    this.selectedFotoDetalle = null;
    this.confirmandoEliminacion.set(false);
  }

  /**
   * Valida y previsualiza la nueva foto elegida para la mascota en detalle.
   * @param event Evento `change` del input de tipo archivo.
   */
  onFotoDetalleSelected(event: any) {
    const file = event.target.files[0];
    if (file) {
      if (file.size > 5 * 1024 * 1024) {
        this.toastService.error('La foto debe ser menor a 5MB.');
        return;
      }
      const validTypes = ['image/jpeg', 'image/png', 'image/webp'];
      if (!validTypes.includes(file.type)) {
        this.toastService.error('Formato no permitido. Solo JPG, PNG o WEBP.');
        return;
      }
      this.selectedFotoDetalle = file;
      const reader = new FileReader();
      reader.onload = (e: any) => this.nuevaFotoDetalle.set(e.target.result);
      reader.readAsDataURL(file);
    }
  }

  /** Sube la nueva foto seleccionada para la mascota en detalle y refresca el dashboard. */
  guardarNuevaFoto() {
    const perro = this.mascotaDetalle();
    if (!perro) return;
    if (!this.selectedFotoDetalle) {
      this.toastService.error('Primero selecciona una foto nueva tocando la imagen.', 'Sin foto seleccionada');
      return;
    }
    if (this.isSaving()) return;

    this.isSaving.set(true);
    const formData = new FormData();
    formData.append('nombre', CustomValidators.capitalizeText(perro.nombre));
    formData.append('raza', CustomValidators.capitalizeText(perro.raza));
    formData.append('peso', perro.peso);
    formData.append('file', this.selectedFotoDetalle);

    this.http.put(`${environment.apiUrl}/perro/${perro.id}`, formData).subscribe({
      next: () => {
        this.toastService.success(`Foto de ${perro.nombre} actualizada.`, 'Foto Actualizada');
        this.cerrarDetalle();
        this.dashboardService.loadDashboardCasa(this.user()?.casa_id || undefined);
      },
      error: (err) => {
        this.isSaving.set(false);
        // errorInterceptor ya extrajo el mensaje real del backend y lo puso en
        // err.message (reemplaza el HttpErrorResponse por un Error plano, así
        // que err.error ya no existe aquí) — antes esto solo miraba err.error,
        // por lo que un rechazo real (p. ej. "esa foto no es de un perro") se
        // veía como el genérico "Error al subir la foto".
        this.toastService.error(err.message || 'Error al subir la foto. Inténtalo de nuevo.');
      },
      complete: () => this.isSaving.set(false)
    });
  }

  /**
   * Calcula la edad aproximada de una mascota, en meses si es menor a 2
   * años o en años completos en caso contrario.
   * @param fechaNac Fecha de nacimiento en formato ISO.
   */
  calcularEdad(fechaNac?: string): string {
    if (!fechaNac) return 'Desconocida';
    const d = new Date(fechaNac);
    const meses = Math.floor((Date.now() - d.getTime()) / (1000 * 60 * 60 * 24 * 30));
    return meses < 24 ? `${meses} meses` : `${Math.floor(meses / 12)} años`;
  }

  /** Elimina definitivamente la mascota en detalle y refresca el dashboard. */
  confirmarEliminacion(perro: any) {
    this.confirmandoEliminacion.set(false);
    this.http.delete(`${environment.apiUrl}/perro/${perro.id}`).subscribe({
      next: () => {
        this.toastService.success(`"${perro.nombre}" eliminado correctamente.`, 'Mascota Eliminada');
        this.cerrarDetalle();
        this.dashboardService.loadDashboardCasa(this.user()?.casa_id || undefined);
      },
      error: (err) => this.toastService.error('Error al eliminar: ' + (err.error?.message || err.message))
    });
  }
}
