import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { LucideAngularModule, PawPrint, Clock, Save, RefreshCw, ImageOff, Utensils, GlassWater, Moon, Gamepad2, HelpCircle } from 'lucide-angular';
import { environment } from '../../../environments/environment';

/** Un instante detectado por una cámara IoT, tal como lo devuelve el backend. */
interface MomentoMascota {
  id: number;
  actividad: 'COMIENDO' | 'BEBIENDO' | 'DURMIENDO' | 'JUGANDO' | 'NINGUNA_CLARA';
  confianza: number;
  capturado_at: string;
  expira_at: string;
  guardado: boolean;
  perro_id: number | null;
  perro_nombre: string | null;
  perro_foto_url: string | null;
  camara_nombre: string;
  segundos_restantes: number;
  urlsFragmento: string[];
}

@Component({
  selector: 'app-momentos',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  templateUrl: './momentos.html',
})
/**
 * "Momentos de tu mascota": lo que la cámara IoT detectó hace poco, con una
 * cuenta regresiva de 3 minutos para guardarlo antes de que el fragmento se
 * borre solo, y la galería de lo que ya se guardó.
 */
export class MomentosComponent implements OnInit, OnDestroy {
  private http = inject(HttpClient);

  activos = signal<MomentoMascota[]>([]);
  galeria = signal<MomentoMascota[]>([]);
  cargandoActivos = signal(true);
  cargandoGaleria = signal(true);
  guardando = signal<number | null>(null);
  errorGaleria = signal<string | null>(null);

  private pollActivos?: ReturnType<typeof setInterval>;
  private tick?: ReturnType<typeof setInterval>;

  // Íconos
  PawPrint = PawPrint; Clock = Clock; Save = Save; RefreshCw = RefreshCw;
  ImageOff = ImageOff; Utensils = Utensils; GlassWater = GlassWater;
  Moon = Moon; Gamepad2 = Gamepad2; HelpCircle = HelpCircle;

  ngOnInit() {
    this.cargarActivos();
    this.cargarGaleria();
    // Los activos se refrescan solos: una detección nueva puede llegar en
    // cualquier momento y la cuenta regresiva necesita seguir siendo real.
    this.pollActivos = setInterval(() => this.cargarActivos(), 15_000);
    // Cuenta regresiva por segundo del lado del cliente, para que no se vea
    // congelada entre un poll y el siguiente.
    this.tick = setInterval(() => {
      this.activos.update(lista => lista
        .map(m => ({ ...m, segundos_restantes: Math.max(0, m.segundos_restantes - 1) }))
        .filter(m => m.segundos_restantes > 0));
    }, 1000);
  }

  ngOnDestroy() {
    if (this.pollActivos) clearInterval(this.pollActivos);
    if (this.tick) clearInterval(this.tick);
  }

  cargarActivos() {
    this.http.get<{ ok: boolean; momentos: MomentoMascota[] }>(`${environment.apiUrl}/momentos/activo`).subscribe({
      next: (res) => {
        this.activos.set(res.momentos ?? []);
        this.cargandoActivos.set(false);
      },
      error: () => this.cargandoActivos.set(false),
    });
  }

  cargarGaleria() {
    this.cargandoGaleria.set(true);
    this.errorGaleria.set(null);
    this.http.get<{ ok: boolean; momentos: MomentoMascota[] }>(`${environment.apiUrl}/momentos`).subscribe({
      next: (res) => {
        this.galeria.set(res.momentos ?? []);
        this.cargandoGaleria.set(false);
      },
      error: () => {
        this.errorGaleria.set('No se pudo cargar la galería de momentos guardados.');
        this.cargandoGaleria.set(false);
      },
    });
  }

  guardar(momento: MomentoMascota) {
    this.guardando.set(momento.id);
    this.http.post<{ ok: boolean }>(`${environment.apiUrl}/momentos/${momento.id}/guardar`, {}).subscribe({
      next: () => {
        this.guardando.set(null);
        this.activos.update(lista => lista.filter(m => m.id !== momento.id));
        this.cargarGaleria();
      },
      error: () => {
        this.guardando.set(null);
        // El más probable es que expiró justo antes de tocar Guardar; se
        // refresca la lista para que desaparezca sola si ya no está vigente.
        this.cargarActivos();
      },
    });
  }

  /** Texto en español de la actividad, para no mostrar el nombre técnico del enum. */
  textoActividad(actividad: MomentoMascota['actividad']): string {
    switch (actividad) {
      case 'COMIENDO': return 'comiendo';
      case 'BEBIENDO': return 'bebiendo agua';
      case 'DURMIENDO': return 'durmiendo';
      case 'JUGANDO': return 'jugando';
      default: return 'frente a la cámara';
    }
  }

  iconoActividad(actividad: MomentoMascota['actividad']) {
    switch (actividad) {
      case 'COMIENDO': return this.Utensils;
      case 'BEBIENDO': return this.GlassWater;
      case 'DURMIENDO': return this.Moon;
      case 'JUGANDO': return this.Gamepad2;
      default: return this.HelpCircle;
    }
  }

  /** Formatea segundos restantes como m:ss para la cuenta regresiva. */
  formatoCuenta(segundos: number): string {
    const m = Math.floor(segundos / 60);
    const s = segundos % 60;
    return `${m}:${s.toString().padStart(2, '0')}`;
  }
}
