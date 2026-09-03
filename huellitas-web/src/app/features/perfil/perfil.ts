import { Component, inject, OnInit, OnDestroy, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, ReactiveFormsModule, FormsModule, Validators } from '@angular/forms';
import { LucideAngularModule, UserCircle, Save, CheckCircle2, AlertCircle, Users, UserPlus, Trash2, QrCode, RefreshCw, Clock } from 'lucide-angular';
import { AuthService } from '../../core/services/auth.service';
import { CustomValidators } from '../../core/utils/custom-validators';
import { environment } from '../../../environments/environment';
import { mapBackendError } from '../../core/utils/error-mapper';
import { MediaUrlPipe } from '../../shared/pipes/media-url.pipe';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';

@Component({
  selector: 'app-perfil',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, FormsModule, LucideAngularModule, MediaUrlPipe],
  templateUrl: './perfil.html',
})
/**
 * Pantalla de perfil del usuario: edición de nombre/foto y, para el
 * propietario de la casa, administración de miembros (invitar, revocar
 * acceso y generar códigos QR de acceso rápido o bienvenida).
 */
export class PerfilComponent implements OnInit, OnDestroy {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private confirmService = inject(ConfirmService);
  private toastService = inject(ToastService);

  UserCircle = UserCircle;
  Save = Save;
  CheckCircle2 = CheckCircle2;
  AlertCircle = AlertCircle;
  Users = Users;
  UserPlus = UserPlus;
  Trash2 = Trash2;
  QrCode = QrCode;
  RefreshCw = RefreshCw;
  Clock = Clock;

  isLoading = signal(false);
  successMessage = signal('');
  errorMessage = signal('');
  demoMode = signal(environment.demoMode);

  user = this.authService.currentUser;
  selectedFile: File | null = null;

  perfilForm = this.fb.group({
    nombre: ['', [Validators.required, CustomValidators.nombrePersona()]],
    email: [{ value: '', disabled: true }],
    fotoUrl: ['']
  });

  previewUrl = signal<string>('');

  // ── GESTIÓN DE MIEMBROS ──
  miembros = signal<any[]>([]);
  cargandoMiembros = signal(false);

  miembroForm = this.fb.group({
    nombre: ['', [Validators.required, CustomValidators.nombrePersona()]],
    email: ['', [Validators.required, Validators.email]]
  });

  /** Indica si un campo del formulario de nuevo miembro es inválido y ya fue tocado/modificado. */
  isCampoMiembroInvalido(campo: string): boolean {
    const ctrl = this.miembroForm.get(campo);
    return !!(ctrl && ctrl.invalid && (ctrl.dirty || ctrl.touched));
  }

  // Modal QR Acceso
  qrModalVisible = signal(false);
  qrMiembroSeleccionado = signal<any>(null);
  qrRawToken = signal('');
  qrTiempoRestante = signal(90);
  private qrTimer: any = null;

  /**
   * Precarga el formulario con los datos guardados localmente y luego los
   * refresca desde el servidor (útil si se editó el perfil desde la app
   * móvil). Si el usuario es propietario, además carga la lista de miembros.
   */
  ngOnInit() {
    const userStr = sessionStorage.getItem('user') || localStorage.getItem('user');
    if (userStr) {
      const user = JSON.parse(userStr);
      this.perfilForm.patchValue({
        nombre: user.nombre,
        email: user.email,
        fotoUrl: user.foto_url || ''
      });
      this.previewUrl.set(user.foto_url || '');
    }

    // Traer los datos frescos del servidor para reflejar cambios hechos
    // desde la app móvil (foto o nombre) sin tener que cerrar sesión.
    this.authService.refreshCurrentUser();
    setTimeout(() => {
      const u = this.user();
      if (!u) return;
      this.perfilForm.patchValue({ nombre: u.nombre, email: u.email, fotoUrl: u.foto_url || '' });
      this.previewUrl.set(u.foto_url || '');
    }, 600);

    if (this.esPropietario) {
      this.cargarMiembros();
    }
  }

  /** `true` si el usuario en sesión tiene el rol PROPIETARIO. */
  get esPropietario(): boolean {
    return this.user()?.rol === 'PROPIETARIO';
  }

  /** Carga la lista de miembros de la casa del propietario. */
  cargarMiembros() {
    this.cargandoMiembros.set(true);
    this.authService.listarMiembros().subscribe({
      next: (res) => {
        this.miembros.set(res || []);
        this.cargandoMiembros.set(false);
      },
      error: () => this.cargandoMiembros.set(false)
    });
  }

  /** Valida y envía la invitación de un nuevo miembro, y recarga la lista al terminar. */
  crearMiembro() {
    if (this.miembroForm.invalid) {
      this.miembroForm.markAllAsTouched();
      return;
    }

    this.cargandoMiembros.set(true);
    const { nombre, email } = this.miembroForm.getRawValue();

    this.authService.invitarMiembro(email!, nombre!).subscribe({
      next: (res: any) => {
        this.toastService.success(`Revisa el correo de ${email} para el código QR de bienvenida. Si no aparece, revisa la carpeta de spam.`, 'Miembro registrado');
        this.miembroForm.reset();
        this.cargarMiembros();
      },
      error: (err) => {
        this.toastService.error(mapBackendError(err, 'Error al registrar miembro.'));
        this.cargandoMiembros.set(false);
      }
    });
  }

  /**
   * Pide confirmación al usuario y, si la otorga, revoca el acceso del
   * miembro indicado.
   * @param id Identificador del miembro a eliminar.
   */
  async eliminarMiembro(id: number) {
    const confirmado = await this.confirmService.ask({
      titulo: 'Revocar acceso',
      mensaje: '¿Estás seguro de revocar el acceso a este miembro?',
      textoConfirmar: 'Sí, revocar',
      esPeligroso: true
    });
    if (!confirmado) return;

    this.cargandoMiembros.set(true);
    this.authService.eliminarMiembro(id).subscribe({
      next: () => {
        this.toastService.success('Acceso de miembro revocado.');
        this.cargarMiembros();
      },
      error: () => this.cargandoMiembros.set(false)
    });
  }

  /**
   * Abre el modal de QR y solicita al backend un token de acceso para el
   * miembro indicado, iniciando la cuenta regresiva de expiración.
   * @param m Miembro para el que se genera el QR.
   * @param tipo Tipo de QR: acceso rápido (90s) o bienvenida (24h).
   */
  generarQrMiembro(m: any, tipo: 'ACCESO_RAPIDO' | 'BIENVENIDA' = 'ACCESO_RAPIDO') {
    this.qrMiembroSeleccionado.set(m);
    this.qrRawToken.set('');
    this.qrTiempoRestante.set(tipo === 'BIENVENIDA' ? 86400 : 90);
    this.qrModalVisible.set(true);

    this.authService.generarQrToken(m.id, tipo).subscribe({
      next: (res) => {
        this.qrRawToken.set(res.raw_token);
        this.iniciarCountdownQr();
        if (tipo === 'BIENVENIDA') {
          this.toastService.success(`QR de Bienvenida (24h) reenviado al correo ${m.email}`);
        }
      },
      error: (err) => {
        this.qrModalVisible.set(false);
        this.toastService.error(err?.error?.error || 'Error al generar código QR');
      }
    });
  }

  /** Inicia el temporizador que decrementa `qrTiempoRestante` cada segundo hasta llegar a cero. */
  iniciarCountdownQr() {
    if (this.qrTimer) clearInterval(this.qrTimer);
    this.qrTimer = setInterval(() => {
      if (this.qrTiempoRestante() > 0) {
        this.qrTiempoRestante.update(v => v - 1);
      } else {
        clearInterval(this.qrTimer);
      }
    }, 1000);
  }

  /** Cierra el modal de QR y detiene la cuenta regresiva. */
  cerrarQrModal() {
    this.qrModalVisible.set(false);
    if (this.qrTimer) clearInterval(this.qrTimer);
  }

  /** Limpia el temporizador del QR al destruir el componente, para evitar fugas de memoria. */
  ngOnDestroy() {
    if (this.qrTimer) clearInterval(this.qrTimer);
  }

  /** Envía los cambios del formulario de perfil (nombre y/o foto) al backend. */
  onSubmit() {
    if (this.perfilForm.invalid) return;

    this.isLoading.set(true);
    this.successMessage.set('');
    this.errorMessage.set('');

    const formValues = this.perfilForm.value;
    const nombre = formValues.nombre!;

    this.authService.actualizarPerfil(nombre, this.selectedFile).subscribe({
      next: () => {
        this.successMessage.set('Perfil actualizado con éxito');
        this.isLoading.set(false);
      },
      error: (err) => {
        this.errorMessage.set(err.error?.error || 'Error al actualizar el perfil');
        this.isLoading.set(false);
      }
    });
  }

  /**
   * Genera una previsualización en Base64 de la foto de perfil elegida.
   * @param event Evento `change` del input de tipo archivo.
   */
  onFileSelected(event: any) {
    const file = event.target.files[0];
    if (file) {
      this.selectedFile = file;
      const reader = new FileReader();
      reader.onload = () => {
        const base64String = reader.result as string;
        // Sólo usamos Base64 para la previsualización en UI
        this.previewUrl.set(base64String);
      };
      reader.readAsDataURL(file);
    }
  }
}
