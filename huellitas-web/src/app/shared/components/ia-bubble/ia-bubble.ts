import {
  Component, signal, inject, ViewChild,
  ElementRef, AfterViewChecked, OnInit
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { LucideAngularModule, Bot, X, Send, ChevronDown, Sparkles, MapPin, ExternalLink, Dog } from 'lucide-angular';
import { AuthService } from '../../../core/services/auth.service';
import { environment } from '../../../../environments/environment';
import { DomSanitizer, SafeHtml } from '@angular/platform-browser';

/** Mensaje del chat de la burbuja flotante del asistente de IA. */
interface BotMsg { role: 'user' | 'bot'; texto: string; ts: Date; usaContexto?: boolean; }

@Component({
  selector: 'app-ia-bubble',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
  templateUrl: './ia-bubble.html',
})
/**
 * Burbuja flotante del asistente de IA de nutrición canina, disponible en
 * toda la app: permite elegir entre las mascotas de la casa y conversar
 * con el asistente sin salir de la pantalla actual.
 */
export class IaBubbleComponent implements OnInit, AfterViewChecked {
  private http = inject(HttpClient);
  private sanitizer = inject(DomSanitizer);
  authService = inject(AuthService);
  user = this.authService.currentUser;

  Bot = Bot; X = X; Send = Send; ChevronDown = ChevronDown; Sparkles = Sparkles; MapPin = MapPin; ExternalLink = ExternalLink; Dog = Dog;

  isOpen       = signal(false);
  isTyping     = signal(false);
  input        = signal('');
  mensajes     = signal<BotMsg[]>([]);
  listaMascotas = signal<any[]>([]);
  mascotaActiva = signal<any>(null);
  private scrollDone = false;

  @ViewChild('chatContainer') private container!: ElementRef;

  /** Carga las mascotas de la casa al iniciar. */
  ngOnInit() {
    this.cargarMascotas();
  }

  /** Hace scroll automático al final del chat la primera vez que se renderiza tras un cambio. */
  ngAfterViewChecked() {
    if (!this.scrollDone && this.container) {
      this.container.nativeElement.scrollTop = this.container.nativeElement.scrollHeight;
      this.scrollDone = true;
    }
  }

  /** Abre la burbuja de chat, mostrando el mensaje de bienvenida la primera vez que se abre. */
  open() {
    this.isOpen.set(true);
    if (this.mensajes().length === 0) {
      const pet = this.mascotaActiva();
      this.agregarBotMsg(
        `¡Hola${this.user()?.nombre ? ', ' + this.user()!.nombre.split(' ')[0] : ''}! Soy tu Nutricionista e IA Canina. ${pet ? 'Estoy analizando a ' + pet.nombre + ' (' + pet.raza + ').' : ''} ¿Qué consulta tienes sobre nutrición o salud?`,
        true
      );
    }
  }

  /** Cierra la burbuja de chat. */
  close() {
    this.isOpen.set(false);
  }

  /** Abre o cierra la burbuja de chat según su estado actual. */
  toggle() {
    if (this.isOpen()) {
      this.close();
    } else {
      this.open();
    }
  }

  /** Obtiene las mascotas de la casa del usuario y selecciona la primera como activa. */
  cargarMascotas() {
    const casaId = this.user()?.casa_id;
    if (!casaId) return;
    this.http.get<any>(`${environment.apiUrl}/casa/dashboard?casaId=${casaId}`).subscribe({
      next: (data) => {
        const perros = data?.perros || data;
        if (Array.isArray(perros) && perros.length > 0) {
          this.listaMascotas.set(perros);
          this.mascotaActiva.set(perros[0]);
        }
      },
      error: () => {}
    });
  }

  /**
   * Cambia la mascota activa del asistente y lo confirma con un mensaje en el chat.
   * @param perro Mascota seleccionada.
   */
  seleccionarMascota(perro: any) {
    this.mascotaActiva.set(perro);
    this.agregarBotMsg(`Has seleccionado a **${perro.nombre}** (${perro.raza}, ${perro.peso || '?'} kg). ¿En qué te ayudo sobre su dieta?`, true);
  }

  /** Envía la pregunta del usuario a la IA de nutrición, con el contexto de la mascota activa. */
  enviar() {
    const txt = this.input().trim();
    if (!txt || this.isTyping()) return;

    this.mensajes.update(m => [...m, { role: 'user', texto: txt, ts: new Date() }]);
    this.input.set('');
    this.isTyping.set(true);
    this.scrollDone = false;

    const mascota = this.mascotaActiva();

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
        this.agregarBotMsg('Lo siento, hubo un problema al conectar con el servidor de IA. Intenta de nuevo.', false);
        this.isTyping.set(false);
        this.scrollDone = false;
      }
    });
  }

  /**
   * Convierte el Markdown ligero de la respuesta de la IA (enlaces,
   * encabezados, negrita, cursiva, listas y saltos de línea) a HTML,
   * marcado como seguro para el binding `[innerHTML]`.
   * @param texto Texto de la respuesta del asistente.
   */
  formatTexto(texto: string): SafeHtml {
    if (!texto) return '';
    let formatted = texto
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');

    // Convert markdown links [Text](URL)
    formatted = formatted.replace(/\[([^\]]+)\]\((.*?)\)/g, (match, text, url) => {
      // Remove spaces from url just in case AI adds spaces
      const cleanUrl = url.trim();
      return `<a href="${cleanUrl}" target="_blank" rel="noopener noreferrer" class="inline-flex items-center gap-1 px-2.5 py-1 my-1 bg-[#061b0e] text-[#fdc003] hover:bg-[#0d2d18] rounded-xl text-xs font-bold shadow-sm transition-all break-all">${text}</a>`;
    });

    // Headers
    formatted = formatted.replace(/^### (.*$)/gim, '<h4 class="font-serif font-bold text-[#061b0e] mt-2 mb-1 text-sm">$1</h4>');
    formatted = formatted.replace(/^## (.*$)/gim, '<h3 class="font-serif font-bold text-[#061b0e] mt-3 mb-1 text-base">$1</h3>');

    // Bold
    formatted = formatted.replace(/\*\*([^*]+)\*\*/g, '<strong class="font-bold text-[#061b0e]">$1</strong>');

    // Italic
    formatted = formatted.replace(/\*([^*]+)\*/g, '<em class="italic">$1</em>');

    // Bullet points
    formatted = formatted.replace(/^\s*[\*\-] (.*$)/gim, '<li class="ml-4 list-disc text-xs leading-relaxed my-0.5">$1</li>');

    // Newlines
    formatted = formatted.replace(/\n/g, '<br>');

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
