import { Component, computed, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LucideAngularModule, Cpu, Server, Wifi, WifiOff, RefreshCw, CheckCircle2, AlertTriangle, MessageCircleWarning, X, Send } from 'lucide-angular';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../../environments/environment';

/** Un dispositivo IoT tal como lo devuelve `/admin/iot/dispositivos`. */
interface DispositivoAdmin {
  id: number;
  mac_address: string;
  tipo: string;
  categoria: string;
  modelo: string | null;
  estado: string;
  ultima_conexion: string | null;
  zona_nombre: string;
  casa_id: number;
  casa_nombre: string;
  propietario_nombre: string | null;
  propietario_email: string | null;
  en_linea: boolean;
  /** Motivo real por el que este dispositivo necesita revisión, o `null` si está conforme. */
  problema: string | null;
}

/** Los dispositivos de una vivienda, agrupados para no repetir la casa en cada fila. */
interface CasaAgrupada {
  casaId: number;
  casaNombre: string;
  propietario: string;
  dispositivos: DispositivoAdmin[];
  conforme: boolean;
}

@Component({
  selector: 'app-admin-iot',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
  templateUrl: './admin-iot.html'
})
/**
 * Panel de administración que lista los dispositivos IoT de todas las
 * viviendas, agrupados por usuario: si todos los suyos están conformes se
 * colapsa en una línea, y solo se expande sola la vivienda que tiene algo
 * real que revisar (nunca dio señal, lleva más de 24h sin dar señal, o quedó
 * en estado de error). No es una vista de "en línea ahora mismo" —para eso
 * está el panel del propio usuario— es una auditoría de qué necesita atención.
 */
export class AdminIotComponent implements OnInit {
  private http = inject(HttpClient);

  Cpu = Cpu;
  Server = Server;
  Wifi = Wifi;
  WifiOff = WifiOff;
  RefreshCw = RefreshCw;
  CheckCircle2 = CheckCircle2;
  AlertTriangle = AlertTriangle;
  MessageCircleWarning = MessageCircleWarning;
  X = X;
  Send = Send;

  // Modal "Avisar a este usuario"
  dispositivoAAvisar = signal<DispositivoAdmin | null>(null);
  mensajeAviso = signal('');
  enviandoAviso = signal(false);
  avisoResultado = signal<'ok' | 'error' | null>(null);

  dispositivos = signal<DispositivoAdmin[]>([]);
  cargando = signal(true);

  casas = computed<CasaAgrupada[]>(() => {
    const porCasa = new Map<number, CasaAgrupada>();
    for (const d of this.dispositivos()) {
      let grupo = porCasa.get(d.casa_id);
      if (!grupo) {
        grupo = {
          casaId: d.casa_id,
          casaNombre: d.casa_nombre,
          propietario: d.propietario_nombre || d.propietario_email || 'Sin propietario',
          dispositivos: [],
          conforme: true,
        };
        porCasa.set(d.casa_id, grupo);
      }
      grupo.dispositivos.push(d);
      if (d.problema) grupo.conforme = false;
    }
    // Primero las que tienen algo que revisar, para que un admin con muchas
    // viviendas no tenga que desplazarse buscando cuál falló.
    return [...porCasa.values()].sort((a, b) => Number(a.conforme) - Number(b.conforme));
  });

  /** Cuántas viviendas tienen al menos un dispositivo que necesita revisión. */
  totalConProblema = computed(() => this.casas().filter(c => !c.conforme).length);

  ngOnInit() {
    this.cargarDispositivos();
  }

  /** Obtiene todos los dispositivos IoT registrados en la plataforma. */
  cargarDispositivos() {
    this.cargando.set(true);
    this.http.get<DispositivoAdmin[]>(`${environment.apiUrl}/admin/iot/dispositivos`).subscribe({
      next: (res) => {
        this.dispositivos.set(res || []);
        this.cargando.set(false);
      },
      error: () => this.cargando.set(false)
    });
  }

  /**
   * Abre el cuadro para escribirle al dueño de un dispositivo con problema.
   * Precarga un mensaje razonable según el motivo detectado, que el admin
   * puede editar antes de mandarlo — para el caso que un trabajo automático
   * no puede redactar solo (por ejemplo, un cambio de IP que el admin
   * detectó mirando el detalle del aparato).
   */
  abrirAvisoParaDispositivo(d: DispositivoAdmin) {
    this.dispositivoAAvisar.set(d);
    this.avisoResultado.set(null);
    this.mensajeAviso.set(
      d.problema
        ? `Notamos que tu dispositivo "${d.modelo || d.categoria}" tiene un problema: ${d.problema.toLowerCase()}. Revisa que esté encendido y conectado a tu red WiFi.`
        : `Sobre tu dispositivo "${d.modelo || d.categoria}": `
    );
  }

  cerrarModalAviso() {
    this.dispositivoAAvisar.set(null);
    this.mensajeAviso.set('');
  }

  /** Manda el mensaje escrito al propietario del dispositivo que se está avisando. */
  enviarAviso() {
    const dispositivo = this.dispositivoAAvisar();
    if (!dispositivo || !this.mensajeAviso().trim()) return;

    this.enviandoAviso.set(true);
    this.avisoResultado.set(null);
    this.http.post<{ ok: boolean }>(
      `${environment.apiUrl}/admin/iot/dispositivos/${dispositivo.id}/avisar`,
      { mensaje: this.mensajeAviso().trim() }
    ).subscribe({
      next: () => {
        this.enviandoAviso.set(false);
        this.avisoResultado.set('ok');
        setTimeout(() => this.cerrarModalAviso(), 1200);
      },
      error: () => {
        this.enviandoAviso.set(false);
        this.avisoResultado.set('error');
      }
    });
  }
}
