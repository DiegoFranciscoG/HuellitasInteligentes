import { Injectable, signal, inject } from '@angular/core';
import { Client, Message } from '@stomp/stompjs';
import { environment } from '../../../environments/environment';
import { AuthService } from './auth.service';

export interface ChatMessage {
  id?: number;
  emisorId: number;
  receptorId?: number;
  contenido: string;
  fecha?: string;
  emisorNombre?: string;
}

/**
 * Gestiona la conexión WebSocket (STOMP) al chat global de la comunidad,
 * manteniendo el historial de mensajes recibidos y el estado de conexión
 * como signals reactivas para los componentes de chat.
 */
@Injectable({
  providedIn: 'root'
})
export class ChatService {
  private authService = inject(AuthService);
  private client!: Client;
  /** Historial de mensajes del canal global de chat. */
  public messages = signal<ChatMessage[]>([]);
  /** Indica si el cliente STOMP está actualmente conectado. */
  public isConnected = signal(false);

  /**
   * Conecta al WebSocket STOMP suscribiéndose al canal global de comunidad.
   * No llamar si demoMode está activo (evita errores de consola).
   */
  connect(userId: number, userName: string) {
    // FIX: import SockJS como módulo. SockJS se importa via script tag o require.
    // Usamos dynamic import para evitar el problema con esbuild.
    const wsUrl = environment.apiUrl.replace('/api/huellitas', '') + '/ws';

    // FIX: No usar `import * as SockJS` — usar dynamic require con (window as any).SockJS
    // o pasar la URL directamente usando STOMP nativo si SockJS está disponible globalmente.
    // La solución más segura para Angular + esbuild es usar webSocketFactory con URL directa.
    this.client = new Client({
      // FIX: En lugar de SockJS (problemas con esbuild), usamos brokerURL directo.
      // Spring Boot con SockJS también expone el endpoint WebSocket nativo en /ws/websocket
      brokerURL: wsUrl.replace('http://', 'ws://').replace('https://', 'wss://') + '/websocket',
      // Identifica al usuario real ante el backend (ver StompAuthChannelInterceptor) —
      // así el servidor no depende del emisorId que mande el propio mensaje.
      connectHeaders: { Authorization: `Bearer ${this.authService.getToken() || ''}` },
      reconnectDelay: 5000,
      heartbeatIncoming: 4000,
      heartbeatOutgoing: 4000,
    });

    // FIX: Suscripción movida DENTRO de onConnect, después de setear userId
    this.client.onConnect = () => {
      this.isConnected.set(true);

      // Canal público global — todos los usuarios conectados ven los mensajes
      this.client.subscribe('/topic/chat-global', (msg: Message) => {
        if (msg.body) {
          const newMsg: ChatMessage = JSON.parse(msg.body);
          // Evitar duplicados: el emisor ya lo tiene localmente
          this.messages.update(m => {
            const yaExiste = m.some(x => x.fecha === newMsg.fecha && x.emisorId === newMsg.emisorId && x.contenido === newMsg.contenido);
            return yaExiste ? m : [...m, newMsg];
          });
        }
      });
    };

    this.client.onStompError = (frame) => {
      console.error('[Chat] STOMP error:', frame.headers['message']);
    };

    this.client.onWebSocketClose = () => {
      this.isConnected.set(false);
    };

    this.client.activate();
  }

  /** Desconecta el cliente STOMP del canal de chat. */
  disconnect() {
    if (this.client) {
      this.client.deactivate();
    }
    this.isConnected.set(false);
  }

  /**
   * Envía un mensaje al canal global.
   * Agrega el mensaje localmente primero para UI responsiva.
   */
  sendMessage(emisorId: number, emisorNombre: string, contenido: string) {
    const fecha = new Date().toISOString();
    const msg: ChatMessage = { emisorId, emisorNombre, contenido, fecha };

    // Agregar localmente inmediatamente
    this.messages.update(m => [...m, msg]);

    if (this.client && this.isConnected()) {
      this.client.publish({
        destination: '/app/chat-global',
        body: JSON.stringify(msg)
      });
    }
  }

  /** Limpia el historial local de mensajes. */
  clearMessages() {
    this.messages.set([]);
  }
}
