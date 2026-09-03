import {
  Component, OnInit, OnDestroy, AfterViewChecked,
  signal, inject, ViewChild, ElementRef, computed
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Client } from '@stomp/stompjs';
import { AuthService } from '../../core/services/auth.service';
import { SocialService } from '../../core/services/social.service';
import { LucideAngularModule, Send, Users, Plus, Hash, ArrowLeft, MessageSquare, X } from 'lucide-angular';
import { environment } from '../../../environments/environment';

/** Sala de chat temática a la que un usuario puede unirse. */
interface Sala { id: number; tema: string; descripcion: string; total_miembros: number; es_miembro: boolean; creador_nombre: string; }
/** Mensaje enviado dentro de una sala de chat. */
interface MsgSala { id?: number; salaId: number; emisorId: number; emisorNombre: string; emisorFoto?: string; contenido: string; fecha: string; reacciones?: any[]; mostrarPicker?: boolean; }

@Component({
  selector: 'app-chat',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
  templateUrl: './chat.html',
})
/**
 * Chat por salas temáticas (distinto del chat global de `ChatService`):
 * listar y crear salas, unirse, conversar en tiempo real vía STOMP y
 * reaccionar a los mensajes.
 */
export class Chat implements OnInit, OnDestroy, AfterViewChecked {
  private http = inject(HttpClient);
  authService  = inject(AuthService);
  socialService = inject(SocialService);
  user = this.authService.currentUser;

  EMOJIS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  Send = Send; Users = Users; Plus = Plus; Hash = Hash;
  ArrowLeft = ArrowLeft; MessageSquare = MessageSquare; X = X;

  salas        = signal<Sala[]>([]);
  salaActiva   = signal<Sala | null>(null);
  mensajes     = signal<MsgSala[]>([]);
  nuevoMensaje = signal('');
  nuevoTema    = signal('');
  nuevaDesc    = signal('');
  mostrarForm  = signal(false);
  isLoading    = signal(true);
  isConnected  = signal(false);
  private scrollDone = false;

  private stompClient!: Client;
  private subActual: any = null;

  @ViewChild('msgContainer') private container!: ElementRef;

  /** Carga las salas de chat disponibles. */
  ngOnInit() { this.cargarSalas(); }

  /** Cierra la conexión STOMP al salir de la pantalla. */
  ngOnDestroy() { this.stompClient?.deactivate(); }

  /** Hace scroll automático al final de los mensajes la primera vez que se renderizan tras un cambio. */
  ngAfterViewChecked() {
    if (!this.scrollDone && this.container) {
      this.container.nativeElement.scrollTop = this.container.nativeElement.scrollHeight;
      this.scrollDone = true;
    }
  }

  /** Obtiene las salas de chat visibles para el usuario en sesión. */
  cargarSalas() {
    if (!this.user()) return;
    this.isLoading.set(true);
    const params = new HttpParams().set('usuarioId', this.user().id);
    this.http.get<any>(`${environment.apiUrl}/chat/salas`, { params }).subscribe({
      next: (raw) => {
        const data = typeof raw === 'string' ? JSON.parse(raw) : raw;
        this.salas.set(Array.isArray(data) ? data : []);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  /** Crea una nueva sala de chat con el tema y descripción redactados. */
  crearSala() {
    if (!this.nuevoTema().trim() || !this.user()) return;
    const params = new HttpParams()
      .set('usuarioId', this.user().id)
      .set('tema', this.nuevoTema())
      .set('descripcion', this.nuevaDesc());
    this.http.post<any>(`${environment.apiUrl}/chat/salas`, null, { params }).subscribe({
      next: () => { this.nuevoTema.set(''); this.nuevaDesc.set(''); this.mostrarForm.set(false); this.cargarSalas(); },
      error: (e) => alert('Error al crear sala: ' + e.message)
    });
  }

  /**
   * Une al usuario a una sala de chat.
   * @param sala Sala a la que se desea unir.
   */
  unirse(sala: Sala) {
    const params = new HttpParams().set('usuarioId', this.user().id);
    this.http.post<any>(`${environment.apiUrl}/chat/salas/${sala.id}/unirse`, null, { params }).subscribe({
      next: () => { sala.es_miembro = true; sala.total_miembros++; }
    });
  }

  /**
   * Abre una sala (uniéndose primero si aún no es miembro), carga su
   * historial y conecta el canal de mensajes en tiempo real.
   * @param sala Sala a la que se desea entrar.
   */
  entrarSala(sala: Sala) {
    if (!sala.es_miembro) { this.unirse(sala); return; }
    this.salaActiva.set(sala);
    this.mensajes.set([]);
    this.scrollDone = false;
    this.cargarHistorial(sala.id);
    this.conectarSala(sala.id);
  }

  /**
   * Agrupa las reacciones crudas de un mensaje por tipo de emoji, con su conteo.
   * @param reacciones Lista de reacciones tal como la devuelve el backend.
   */
  agruparReacciones(reacciones: any[] | undefined): { emoji: string, count: number }[] {
    if (!reacciones || !reacciones.length || reacciones[0] === null) return [];
    const grouped = reacciones.reduce((acc: any, curr: any) => {
      if (!curr || !curr.tipo) return acc;
      acc[curr.tipo] = (acc[curr.tipo] || 0) + 1;
      return acc;
    }, {});
    return Object.keys(grouped).map(k => ({ emoji: k, count: grouped[k] }));
  }

  /** Indica si el usuario en sesión ya reaccionó con un emoji dado a un mensaje. */
  haReaccionado(item: any, emoji: string): boolean {
    if (!item.reacciones || !item.reacciones.length || item.reacciones[0] === null || !this.user()) return false;
    return item.reacciones.some((r: any) => r && r.tipo === emoji && r.usuario_id === this.user()?.id);
  }

  /**
   * Agrega o quita la reacción del usuario sobre un mensaje, actualizando
   * el estado local de inmediato y revirtiéndolo si la petición falla.
   * @param item Mensaje reaccionado.
   * @param emoji Emoji de la reacción.
   * @param tipoItem Tipo de ítem reaccionado (`chat-sala` por defecto).
   */
  toggleReaccion(item: any, emoji: string, tipoItem: string = 'chat-sala') {
    if (!this.user() || !item.id) return;
    
    if (!item.reacciones || (item.reacciones.length > 0 && item.reacciones[0] === null)) {
      item.reacciones = [];
    }

    const userId = this.user().id;
    const yaReacciono = this.haReaccionado(item, emoji);

    if (yaReacciono) {
      item.reacciones = item.reacciones.filter((r: any) => !(r.tipo === emoji && r.usuario_id === userId));
    } else {
      item.reacciones.push({ tipo: emoji, usuario_id: userId });
    }
    
    item.mostrarPicker = false;

    this.socialService.reaccionarItem(item.id, userId, emoji, tipoItem, yaReacciono).subscribe({
      next: () => {},
      error: () => {
        // Rollback
        if (yaReacciono) {
          item.reacciones.push({ tipo: emoji, usuario_id: userId });
        } else {
          item.reacciones = item.reacciones.filter((r: any) => !(r.tipo === emoji && r.usuario_id === userId));
        }
      }
    });
  }

  /** Sale de la sala activa y cancela la suscripción de mensajes en tiempo real. */
  salirVista() {
    this.salaActiva.set(null);
    this.subActual?.unsubscribe();
    this.subActual = null;
  }

  /**
   * Obtiene los últimos 50 mensajes de una sala.
   * @param salaId Identificador de la sala.
   */
  cargarHistorial(salaId: number) {
    const params = new HttpParams().set('limite', '50');
    this.http.get<any>(`${environment.apiUrl}/chat/salas/${salaId}/mensajes`, { params }).subscribe({
      next: (raw) => {
        const data = typeof raw === 'string' ? JSON.parse(raw) : raw;
        const msgs: MsgSala[] = (Array.isArray(data) ? data : []).reverse();
        this.mensajes.set(msgs.map(m => ({ ...m, salaId })));
        this.scrollDone = false;
      }
    });
  }

  /**
   * Conecta (o reutiliza la conexión STOMP existente) y se suscribe al
   * canal de mensajes en tiempo real de una sala. En modo demo, simula la
   * conexión sin abrir un socket real.
   * @param salaId Identificador de la sala.
   */
  conectarSala(salaId: number) {
    if (environment.demoMode) { this.isConnected.set(true); return; }
    const wsUrl = environment.apiUrl.replace('/api/huellitas', '') + '/ws/websocket';
    if (!this.stompClient || !this.stompClient.active) {
      this.stompClient = new Client({
        brokerURL: wsUrl.replace('http://', 'ws://').replace('https://', 'wss://'),
        // Identifica al usuario real ante el backend (ver StompAuthChannelInterceptor).
        connectHeaders: { Authorization: `Bearer ${this.authService.getToken() || ''}` },
        reconnectDelay: 5000,
      });
    }
    this.stompClient.onConnect = () => {
      this.isConnected.set(true);
      this.subActual = this.stompClient.subscribe(`/topic/sala/${salaId}`, (msg) => {
        if (msg.body) {
          const newMsg: MsgSala = JSON.parse(msg.body);
          // Evitar duplicado optimista
          this.mensajes.update(m => {
            const dup = m.some(x => x.fecha === newMsg.fecha && x.emisorId === newMsg.emisorId);
            return dup ? m : [...m, newMsg];
          });
          this.scrollDone = false;
        }
      });
    };
    this.stompClient.onWebSocketClose = () => this.isConnected.set(false);
    if (!this.stompClient.active) this.stompClient.activate();
  }

  /** Envía el mensaje redactado a la sala activa (local primero, luego por STOMP si hay conexión real). */
  enviar() {
    const texto = this.nuevoMensaje().trim();
    const sala  = this.salaActiva();
    if (!texto || !sala || !this.user()) return;

    const msg: MsgSala = {
      salaId: sala.id, emisorId: this.user().id,
      emisorNombre: this.user().nombre, contenido: texto,
      fecha: new Date().toISOString()
    };
    this.mensajes.update(m => [...m, msg]);
    this.nuevoMensaje.set('');
    this.scrollDone = false;

    if (!environment.demoMode && this.stompClient?.active) {
      this.stompClient.publish({ destination: `/app/sala/${sala.id}`, body: JSON.stringify(msg) });
    }
  }
}
