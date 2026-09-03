import { Component, signal, inject, ViewChild, ElementRef, AfterViewChecked, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { LucideAngularModule, Send, Bot, User, Sparkles } from 'lucide-angular';
import { AuthService } from '../../core/services/auth.service';
import { environment } from '../../../environments/environment';
import { DomSanitizer, SafeHtml } from '@angular/platform-browser';

/** Mensaje del chat con el asistente de IA, propio o de la mascota. */
interface BotMsg { role: 'user' | 'bot'; texto: string; ts: Date; usaContexto?: boolean; }

@Component({
  selector: 'app-asistente',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
  templateUrl: './asistente.html',
})
/**
 * Chat con el asistente de IA de nutrición canina: responde preguntas
 * usando el contexto de la mascota activa y, ante consultas de negocios o
 * tiendas cercanas, geolocaliza al usuario para sugerir lugares reales.
 */
export class AsistenteComponent implements OnInit, AfterViewChecked {
  private http = inject(HttpClient);
  private sanitizer = inject(DomSanitizer);
  authService = inject(AuthService);
  user = this.authService.currentUser;

  Send = Send; Bot = Bot; User = User; Sparkles = Sparkles;

  mensajes = signal<BotMsg[]>([]);
  input = signal('');
  isTyping = signal(false);
  mascotaActiva = signal<any>(null);

  private scrollDone = false;
  @ViewChild('chatContainer') private container!: ElementRef;

  /** Carga la mascota activa y muestra el mensaje de bienvenida del asistente. */
  ngOnInit() {
    this.cargarMascota();
    this.agregarBotMsg(
      `¡Hola${this.user()?.nombre ? ', ' + this.user()!.nombre.split(' ')[0] : ''}! Soy tu asistente de nutrición canina. ¿En qué te puedo ayudar hoy?`,
      true
    );
  }

  /** Hace scroll automático al final del chat la primera vez que se renderiza tras un cambio. */
  ngAfterViewChecked() {
    if (!this.scrollDone && this.container) {
      this.container.nativeElement.scrollTop = this.container.nativeElement.scrollHeight;
      this.scrollDone = true;
    }
  }

  /** Obtiene la primera mascota de la casa del usuario, usada como contexto de las respuestas de la IA. */
  cargarMascota() {
    const casaId = this.user()?.casa_id;
    if (!casaId) return;
    this.http.get<any>(`${environment.apiUrl}/casa/dashboard?casaId=${casaId}`).subscribe({
      next: (data) => {
        const perros = data?.perros || data;
        if (Array.isArray(perros) && perros.length > 0) {
          this.mascotaActiva.set(perros[0]);
        }
      },
      error: () => {}
    });
  }

  /**
   * Busca tiendas y veterinarias cercanas a unas coordenadas y responde en
   * el chat con la lista formateada (nombre, dirección, horario y enlace a Maps).
   * @param lat Latitud de búsqueda.
   * @param lng Longitud de búsqueda.
   */
  buscarNegociosConCoords(lat: number, lng: number) {
    this.http.get<any>(`${environment.apiUrl}/ia/negocios-cercanos?lat=${lat}&lng=${lng}&tipo=pet_store`).subscribe({
      next: (res) => {
        let msg = 'Aquí tienes algunos negocios y veterinarias cercanas para tu mascota:\n\n';
        const placesList = Array.isArray(res) ? res : (res?.places || []);
        if (placesList.length > 0) {
          placesList.forEach((n: any) => {
            const nombre = n.displayName?.text || n.nombre || 'Tienda de mascotas';
            const addr = n.formattedAddress || n.direccion || '';
            const rating = n.rating ? ` (calificación ${n.rating})` : '';

            let estadoHorario = 'Horario no disponible';
            const openNow = n.currentOpeningHours?.openNow ?? n.regularOpeningHours?.openNow ?? n.opening_hours?.open_now;
            if (openNow === true) estadoHorario = 'Abierto ahora';
            else if (openNow === false) estadoHorario = 'Cerrado';

            const placeId = n.id || n.place_id;
            const mapsUrl = n.googleMapsUri || (placeId ? `https://www.google.com/maps/place/?q=place_id:${placeId}` : `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(nombre + ' ' + addr)}`);

            msg += `${nombre}${rating}\n   Dirección: ${addr}\n   Estado: ${estadoHorario}\n   Maps: ${mapsUrl}\n\n`;
          });
        } else {
          msg = 'No encontré negocios cercanos en esta ubicación.';
        }
        this.agregarBotMsg(msg, false);
        this.isTyping.set(false);
        this.scrollDone = false;
      },
      error: () => {
        this.agregarBotMsg('Lo siento, no pude buscar negocios en este momento.', false);
        this.isTyping.set(false);
        this.scrollDone = false;
      }
    });
  }

  sugerencias = [
    '¿Cuántas veces debe comer mi perro al día?',
    '¿Qué alimentos son tóxicos para los perros?',
    '¿Dónde hay tiendas de mascotas cercanas?',
    '¿Cuánta agua necesita mi mascota?'
  ];

  /**
   * Envía la pregunta del usuario al asistente. Si detecta intención de
   * buscar negocios/tiendas cercanas, geolocaliza al usuario (con
   * coordenadas de respaldo si lo rechaza) y muestra resultados reales; en
   * caso contrario, consulta la IA de nutrición con el contexto de la
   * mascota activa (o responde en modo demo si el backend no está conectado).
   * @param textoPrompt Texto a enviar; si se omite, usa el contenido del input.
   */
  enviar(textoPrompt?: string) {
    const txt = (textoPrompt || this.input()).trim();
    if (!txt || this.isTyping()) return;

    this.mensajes.update(m => [...m, { role: 'user', texto: txt, ts: new Date() }]);
    this.input.set('');
    this.scrollDone = false;
    this.isTyping.set(true);

    const txtLower = txt.toLowerCase();
    if (txtLower.includes('negocio') || txtLower.includes('tienda') || txtLower.includes('petshop') || txtLower.includes('comprar') || txtLower.includes('veterinaria') || txtLower.includes('donde') || txtLower.includes('dónde')) {
      const lat = this.user()?.casa_lat || 0;
      const lng = this.user()?.casa_lng || 0;
      
      if (lat === 0 && lng === 0) {
        if (typeof navigator !== 'undefined' && navigator.geolocation) {
          navigator.geolocation.getCurrentPosition(
            (pos) => this.buscarNegociosConCoords(pos.coords.latitude, pos.coords.longitude),
            () => this.buscarNegociosConCoords(-0.1807, -78.4678)
          );
        } else {
          this.buscarNegociosConCoords(-0.1807, -78.4678);
        }
        return;
      }

      this.buscarNegociosConCoords(lat, lng);
      return;
    }

    const mascota = this.mascotaActiva();

    if (environment.demoMode) {
      setTimeout(() => {
        this.agregarBotMsg('Conecta el backend de Spring Boot para recibir respuestas reales de la IA de Gemini. (Modo Demo)', false);
        this.isTyping.set(false);
        this.scrollDone = false;
      }, 900);
      return;
    }

    const payload = {
      pregunta: txt,
      raza:  mascota?.raza   || null,
      edad:  this.calcularEdad(mascota?.fecha_nacimiento),
      peso:  mascota?.peso   || null,
    };

    this.http.post<any>(`${environment.apiUrl}/ia/nutricion`, payload).subscribe({
      next: (res) => {
        this.agregarBotMsg(res.respuesta || res, res.usaContexto);
        this.isTyping.set(false);
        this.scrollDone = false;
      },
      error: () => {
        this.agregarBotMsg('No pude conectar con el servidor de IA. Intenta de nuevo.', false);
        this.isTyping.set(false);
        this.scrollDone = false;
      }
    });
  }

  /**
   * Convierte enlaces Markdown y URLs sueltas del texto de respuesta en
   * enlaces HTML clicables, marcados como seguros para el binding `[innerHTML]`.
   * @param texto Texto de la respuesta del asistente.
   */
  formatTexto(texto: string): SafeHtml {
    if (!texto) return '';
    let formatted = texto
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
    formatted = formatted.replace(/\[([^\]]+)\]\((https?:\/\/[^\s\)]+)\)/g, (match, text, url) => {
      return `<a href="${url}" target="_blank" rel="noopener noreferrer" class="text-[var(--primary)] font-bold underline hover:text-[var(--primary)] break-all bg-[var(--primary-surface)] px-2 py-1 rounded-lg my-1 inline-flex items-center gap-1">${text}</a>`;
    });
    formatted = formatted.replace(/(^|[^"])((https?:\/\/[^\s<]+))/g, (match, prefix, url) => {
      if (prefix.includes('href=')) return match;
      return `${prefix}<a href="${url}" target="_blank" rel="noopener noreferrer" class="text-[var(--primary)] font-bold underline hover:text-[var(--primary)] break-all bg-[var(--primary-surface)] px-2 py-1 rounded-lg my-1 inline-flex items-center gap-1">Ver en Google Maps</a>`;
    });
    return this.sanitizer.bypassSecurityTrustHtml(formatted);
  }

  /** Agrega un mensaje del asistente al historial del chat. */
  private agregarBotMsg(texto: string, usaContexto?: boolean) {
    this.mensajes.update(m => [...m, { role: 'bot', texto, ts: new Date(), usaContexto }]);
  }

  /** Calcula la edad de la mascota en meses o años, para enviarla como contexto a la IA. */
  private calcularEdad(fechaNac?: string): string {
    if (!fechaNac) return 'desconocida';
    const d = new Date(fechaNac);
    const meses = Math.floor((Date.now() - d.getTime()) / (1000 * 60 * 60 * 24 * 30));
    return meses < 24 ? `${meses} meses` : `${Math.floor(meses / 12)} años`;
  }
}
