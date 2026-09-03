import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { FormsModule } from '@angular/forms';
import { LucideAngularModule, Video, RefreshCw, AlertCircle, Camera, Shield, EyeOff, Maximize2, X, Plus, Smartphone, Check, Link, Dog, Wifi, Loader, Cpu } from 'lucide-angular';
import { IotControlService, DispositivoDescubierto } from '../dispositivos/services/iot-control.service';
import { AuthService } from '../../core/services/auth.service';
import { DashboardService } from '../../core/services/dashboard.service';
import { environment } from '../../../environments/environment';
import { WebRtcVideoComponent } from './web-rtc-video.component';
import { MediaUrlPipe } from '../../shared/pipes/media-url.pipe';

/** Cámara IP/WebRTC vinculada a la casa, opcionalmente asignada a una mascota. */
interface Camara {
  id: number;
  casaId: number;
  nombre: string;
  urlStream: string;
  activo: boolean;
  conectada: boolean;
  perroId: number | null;
  perroNombre: string | null;
  perroFotoUrl: string | null;
}

@Component({
  selector: 'app-camaras',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule, WebRtcVideoComponent, MediaUrlPipe],
  templateUrl: './camaras.html',
  styleUrls: ['./camaras.css']
})
/**
 * Muestra las cámaras vinculadas a la casa (vía WebRTC o URL de stream),
 * permite vincular cámaras nuevas por QR y asignar cada una a la mascota
 * que vigila.
 */
export class CamarasComponent implements OnInit {
  private http = inject(HttpClient);
  public auth = inject(AuthService);
  private sanitizer = inject(DomSanitizer);
  private dashboardService = inject(DashboardService);

  camaras = signal<Camara[]>([]);
  /** Mascotas de la casa, para elegir cuál vigila cada cámara. */
  perros = computed<any[]>(() => this.dashboardService.dashboardData()?.perros ?? []);
  asignandoMascota = signal<number | null>(null);
  cargando = signal<boolean>(true);
  error = signal<string | null>(null);
  camaraMaximizada = signal<Camara | null>(null);

  // Modal Agregar Camara
  mostrarModalAgregar = signal<boolean>(false);
  nuevaCamaraNombre = signal<string>('');
  guardandoCamara = signal<boolean>(false);
  qrGenerado = signal<string | null>(null);

  /** Pestaña activa del modal: vincular por QR o buscar en la red del hogar. */
  pestanaAlta = signal<'qr' | 'red'>('qr');
  buscandoDispositivos = signal<boolean>(false);
  dispositivosEncontrados = signal<DispositivoDescubierto[]>([]);
  /** Se pone en true cuando ya se buscó al menos una vez, para distinguir «vacío» de «todavía no buscaste». */
  yaBusco = signal<boolean>(false);
  ventanaPresencia = signal<number>(30);
  errorBusqueda = signal<string | null>(null);

  private iot = inject(IotControlService);

  // Icons
  VideoIcon = Video; RefreshCw = RefreshCw; AlertCircle = AlertCircle; CameraIcon = Camera;
  Shield = Shield; EyeOff = EyeOff; Maximize2 = Maximize2; XIcon = X; Plus = Plus;
  Smartphone = Smartphone; Check = Check; Link = Link; Dog = Dog;
  Wifi = Wifi; Loader = Loader; Cpu = Cpu;

  /** Carga las cámaras de la casa y, si aún no está en memoria, el dashboard (para la lista de mascotas). */
  ngOnInit() {
    this.cargarCamaras();
    // Las mascotas llegan en el mismo dashboard de la casa; solo se pide si
    // el usuario entró directo a esta pantalla y todavía no está cargado.
    if (!this.dashboardService.dashboardData()) {
      this.dashboardService.loadDashboardCasa(this.auth.currentUser()?.casa_id);
    }
  }

  /** Obtiene del backend las cámaras vinculadas a la casa del usuario en sesión. */
  cargarCamaras() {
    this.cargando.set(true);
    this.error.set(null);
    const user = this.auth.currentUser();
    if (!user || !user.casa_id) {
      this.error.set('No se pudo identificar tu casa para cargar las cámaras.');
      this.cargando.set(false);
      return;
    }

    this.http.get<Camara[]>(`${environment.apiUrl}/camaras/casa/${user.casa_id}`).subscribe({
      next: (data) => {
        this.camaras.set(data);
        this.cargando.set(false);
      },
      error: (err) => {
        console.error('Error al cargar cámaras', err);
        this.error.set('No se pudieron conectar las cámaras en este momento.');
        this.cargando.set(false);
      }
    });
  }

  codigoVinculacion = signal<string>('');
  cargandoCodigo = signal<boolean>(false);

  /** Abre el modal para vincular una cámara nueva, con el formulario en blanco. */
  abrirModalAgregar() {
    this.nuevaCamaraNombre.set('');
    this.qrGenerado.set(null);
    this.errorBusqueda.set(null);
    this.dispositivosEncontrados.set([]);
    this.yaBusco.set(false);
    this.mostrarModalAgregar.set(true);
    
    // Cargar el codigo de la vivienda al abrir el modal
    const dash = this.dashboardService.dashboardData();
    const casaId = dash && dash.casa ? dash.casa.id : null;
    if (casaId) {
      this.http.get<any>(`${environment.apiUrl}/casa/${casaId}/codigo-vinculacion`)
        .subscribe({
          next: (res) => this.codigoVinculacion.set(res.codigoVinculacion),
          error: (err) => console.error('Error cargando código de vinculación', err)
        });
    }
  }

  regenerarCodigo() {
    const dash = this.dashboardService.dashboardData();
    const casaId = dash && dash.casa ? dash.casa.id : null;
    if (!casaId) return;
    
    if (!confirm('Si regeneras el código, todas las placas que usan el código actual dejarán de funcionar hasta que se las actualice. ¿Estás seguro?')) {
      return;
    }

    this.cargandoCodigo.set(true);
    this.http.post<any>(`${environment.apiUrl}/casa/${casaId}/codigo-vinculacion/regenerar`, {})
      .subscribe({
        next: (res) => {
          this.codigoVinculacion.set(res.codigoVinculacion);
          this.cargandoCodigo.set(false);
        },
        error: (err) => {
          console.error('Error regenerando código', err);
          alert('No se pudo regenerar el código. Comprueba la conexión.');
          this.cargandoCodigo.set(false);
        }
      });
  }

  /** Cierra el modal de vinculación de cámara. */
  cerrarModalAgregar() {
    this.mostrarModalAgregar.set(false);
    this.qrGenerado.set(null);
    this.dispositivosEncontrados.set([]);
    this.yaBusco.set(false);
  }

  /** Cambia entre vincular por QR y buscar en la red del hogar. */
  cambiarPestana(p: 'qr' | 'red') {
    this.pestanaAlta.set(p);
    this.errorBusqueda.set(null);
    if (p === 'red' && !this.yaBusco()) this.buscarEnRed();
  }

  /**
   * Pide al backend qué dispositivos del hogar reportaron su latido hace poco.
   * El navegador no puede rastrear la red por su cuenta, así que la lista sale
   * de los aparatos que se anunciaron solos.
   */
  buscarEnRed() {
    this.buscandoDispositivos.set(true);
    this.errorBusqueda.set(null);

    this.iot.descubrirDispositivos(true).subscribe({
      next: (res) => {
        this.buscandoDispositivos.set(false);
        this.yaBusco.set(true);
        this.ventanaPresencia.set(res.ventanaSegundos ?? 30);
        this.dispositivosEncontrados.set(res.dispositivos ?? []);
      },
      error: () => {
        this.buscandoDispositivos.set(false);
        this.yaBusco.set(true);
        this.errorBusqueda.set('No se pudo consultar los dispositivos del hogar.');
      }
    });
  }

  /**
   * Da de alta como cámara un dispositivo encontrado en la red.
   *
   * Un aparato que nunca fue adoptado todavía no existe en la tabla de
   * dispositivos, así que primero hay que reclamarlo para esta vivienda y
   * recién entonces vincularlo como cámara. Los que ya son de la casa se
   * saltan ese primer paso.
   *
   * @param disp Dispositivo elegido de la lista.
   */
  vincularDispositivo(disp: DispositivoDescubierto) {
    if (!disp.reclamable && disp.id == null) {
      this.errorBusqueda.set('Ese dispositivo pertenece a otra cuenta.');
      return;
    }

    const nombre = this.nuevaCamaraNombre().trim() || disp.modelo || disp.mac_address;
    this.guardandoCamara.set(true);
    this.errorBusqueda.set(null);

    const conDispositivo = (dispositivoId: number) => {
      this.http.post<{ ok: boolean }>(`${environment.apiUrl}/camaras/vincular-dispositivo`,
        { dispositivoId, nombre }).subscribe({
        next: () => {
          this.guardandoCamara.set(false);
          this.cargarCamaras();
          this.nuevaCamaraNombre.set('');
          // No se cierra el modal: si el hogar tiene más de un dispositivo
          // encontrado, quitamos solo el que ya se vinculó para que el
          // usuario pueda seguir agregando el resto sin repetir la búsqueda.
          this.dispositivosEncontrados.update(lista => lista.filter(x => x.mac_address !== disp.mac_address));
        },
        error: (err) => {
          this.guardandoCamara.set(false);
          this.errorBusqueda.set(err?.error?.error ?? 'No se pudo vincular el dispositivo.');
        }
      });
    };

    if (disp.id != null) {
      conDispositivo(disp.id);
      return;
    }

    this.iot.reclamarDispositivo(disp.mac_address, nombre, 'CAMARA').subscribe({
      next: (res: any) => {
        const nuevoId = res?.dispositivo?.id;
        if (nuevoId == null) {
          this.guardandoCamara.set(false);
          this.errorBusqueda.set('El dispositivo se registró pero no se pudo leer su identificador.');
          return;
        }
        conDispositivo(nuevoId);
      },
      error: (err) => {
        this.guardandoCamara.set(false);
        this.errorBusqueda.set(err?.error?.error ?? 'No se pudo vincular el dispositivo.');
      }
    });
  }

  /**
   * Registra una nueva cámara para la casa y genera el código QR que el
   * dispositivo físico debe escanear para vincularse.
   */
  guardarCamara() {
    if (!this.nuevaCamaraNombre().trim()) return;
    
    const user = this.auth.currentUser();
    if (!user || !user.casa_id) return;

    this.guardandoCamara.set(true);
    const payload = {
      casaId: user.casa_id,
      nombre: this.nuevaCamaraNombre()
    };

    this.http.post<{ok: boolean, qrBase64: string}>(`${environment.apiUrl}/camaras/qr-vinculacion`, payload).subscribe({
      next: (response) => {
        this.guardandoCamara.set(false);
        this.qrGenerado.set(response.qrBase64);
        this.cargarCamaras();
      },
      error: (err) => {
        console.error(err);
        alert('Error al generar QR de cámara');
        this.guardandoCamara.set(false);
      }
    });
  }

  /**
   * Marca (o quita) la mascota que vigila una cámara. El servidor devuelve la
   * cámara ya con el nombre y la foto de la mascota, así que se reemplaza
   * directamente en la lista sin recargar todo.
   */
  asignarMascota(camara: Camara, valor: string) {
    const perroId = valor ? Number(valor) : null;
    if (perroId === (camara.perroId ?? null)) return;

    this.asignandoMascota.set(camara.id);
    this.http.put<Camara>(`${environment.apiUrl}/camaras/${camara.id}/mascota`, { perroId }).subscribe({
      next: (actualizada) => {
        this.camaras.update(lista => lista.map(c => c.id === camara.id ? { ...c, ...actualizada } : c));
        this.asignandoMascota.set(null);
      },
      error: (err) => {
        console.error('Error al asignar la mascota a la cámara', err);
        this.asignandoMascota.set(null);
      }
    });
  }

  /** Marca una URL de stream como segura para incrustarla, evitando el bloqueo de Angular contra XSS. */
  getSafeUrl(url: string): SafeResourceUrl {
    return this.sanitizer.bypassSecurityTrustResourceUrl(url);
  }

  /** Indica si la URL de una cámara corresponde a un stream WebRTC (prefijo `webrtc:`). */
  isWebRtc(url: string): boolean {
    return !!(url && url.startsWith('webrtc:'));
  }

  /** Muestra una cámara en vista maximizada/pantalla completa. */
  maximizar(camara: Camara) {
    this.camaraMaximizada.set(camara);
  }

  /** Cierra la vista maximizada de cámara. */
  cerrarMaximizada() {
    this.camaraMaximizada.set(null);
  }
}
