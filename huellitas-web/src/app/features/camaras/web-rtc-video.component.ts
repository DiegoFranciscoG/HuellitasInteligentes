import { Component, Input, OnInit, OnDestroy, ViewChild, ElementRef, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Client } from '@stomp/stompjs';
import { AuthService } from '../../core/services/auth.service';
import { environment } from '../../../environments/environment';
import { LucideAngularModule, Video, Shield, Loader, RefreshCw, RotateCcw, RotateCw } from 'lucide-angular';
import { IotControlService } from '../dispositivos/services/iot-control.service';

@Component({
  selector: 'app-web-rtc-video',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  template: `
    <!-- El video y sus mandos van apilados, no superpuestos: los botones de
         giro estaban flotando sobre la imagen y tapaban justo la parte que
         hay que mirar mientras se mueve la cámara. -->
    <div class="w-full h-full flex flex-col">
    <div class="relative flex-1 min-h-0 w-full bg-black flex items-center justify-center">
      <!-- object-contain y no object-cover: así se ve todo el campo de visión
           de la cámara, aunque queden bandas a los costados. -->
      <video #videoElement autoplay playsinline class="w-full h-full object-contain"></video>
      
      <!-- Overlay Loading -->
      <div *ngIf="status() !== 'connected'" class="absolute inset-0 flex flex-col items-center justify-center bg-black/60 backdrop-blur-sm z-10 space-y-3">
        <lucide-icon [name]="Loader" [size]="32" class="text-[var(--primary)] animate-spin"></lucide-icon>
        <span class="text-white font-medium text-sm">{{ status() === 'connecting' ? 'Conectando a Cámara...' : 'Negociando P2P...' }}</span>
      </div>
      
      <!-- Overlay Badges -->
      <div class="absolute top-4 right-4 z-20 flex gap-2">
        <button *ngIf="status() === 'connected'" (click)="flipCamera()" class="p-1.5 rounded-md bg-black/60 backdrop-blur-sm border border-white/20 text-white hover:bg-white/20 transition shadow-lg">
          <lucide-icon [name]="RefreshCw" [size]="14"></lucide-icon>
        </button>
        <span class="px-2 py-1 rounded-md bg-black/60 backdrop-blur-sm border border-[rgba(27,48,34,0.3)] text-xs font-medium text-[var(--primary)] flex items-center gap-1.5 shadow-lg">
          <lucide-icon [name]="Shield" [size]="12"></lucide-icon> P2P
        </span>
        <span *ngIf="status() === 'connected'" class="px-2 py-1 rounded-md bg-[rgba(186,26,26,0.2)] backdrop-blur-sm border border-[rgba(186,26,26,0.3)] text-xs font-medium text-[var(--error)] flex items-center gap-1.5 shadow-lg animate-pulse">
          LIVE
        </span>
      </div>
    </div>

    <!-- Mandos de giro, debajo de la imagen -->
    <div *ngIf="status() === 'connected'"
      class="shrink-0 flex items-center justify-center gap-3 py-2.5 px-3 bg-[var(--surface)] border-t border-[var(--outline)]/15">
      <button (click)="girarCamara(-30)" [disabled]="anguloCamara() <= 0"
        class="btn btn-outline px-3 py-1.5 flex items-center gap-1.5 text-xs disabled:opacity-40"
        title="Girar 30° a la izquierda">
        <lucide-icon [name]="RotateCcw" [size]="15"></lucide-icon> Izquierda
      </button>
      <span class="text-xs font-semibold text-[var(--primary)] tabular-nums w-12 text-center">
        {{ anguloCamara() }}°
      </span>
      <button (click)="girarCamara(30)" [disabled]="anguloCamara() >= 180"
        class="btn btn-outline px-3 py-1.5 flex items-center gap-1.5 text-xs disabled:opacity-40"
        title="Girar 30° a la derecha">
        Derecha <lucide-icon [name]="RotateCw" [size]="15"></lucide-icon>
      </button>
    </div>
    </div>
  `
})
/**
 * Reproduce en un `<video>` el stream WebRTC en vivo de una cámara física,
 * negociando la conexión peer-to-peer (oferta/respuesta/candidatos ICE) a
 * través de un canal de señalización STOMP sobre WebSocket.
 */
export class WebRtcVideoComponent implements OnInit, OnDestroy {
  /** Identificador del stream/cámara origen al que se solicita la conexión. */
  @Input() targetStream!: string;
  @ViewChild('videoElement', { static: true }) videoElement!: ElementRef<HTMLVideoElement>;

  private auth = inject(AuthService);
  private iot = inject(IotControlService);
  private stompClient!: Client;
  private peerConnection!: RTCPeerConnection;
  private pendingCandidates: RTCIceCandidateInit[] = [];
  private isRemoteSet = false;

  status = signal<'connecting' | 'negotiating' | 'connected'>('connecting');
  /** Ángulo actual del servo que orienta la cámara, para mostrarlo sobre el video. */
  anguloCamara = signal<number>(0);

  Loader = Loader; Shield = Shield; VideoIcon = Video; RefreshCw = RefreshCw;
  RotateCcw = RotateCcw; RotateCw = RotateCw;

  /** Prepara la conexión WebRTC y luego abre el canal de señalización STOMP. */
  async ngOnInit() {
    await this.initWebRTC();
    this.connectStomp();
    this.cargarAnguloCamara();
  }

  /** Lee la orientación actual de la cámara para que el indicador arranque en el valor real. */
  private cargarAnguloCamara() {
    this.iot.getDevices().subscribe({
      next: (state) => this.anguloCamara.set(state?.servo3?.angle ?? 0),
      error: () => {
        // Sin el estado del ESP32 el indicador queda en 0; los botones siguen sirviendo.
      }
    });
  }

  /** Cierra la conexión STOMP y la conexión peer-to-peer al destruir el componente. */
  ngOnDestroy() {
    this.stompClient?.deactivate();
    this.peerConnection?.close();
  }

  /**
   * Credenciales TURN de Metered pedidas en tiempo real (si están
   * configuradas en `environment.ts`) para no depender solo de STUN, que
   * falla detrás de NATs estrictos. Sin configurar, cae a solo STUN.
   */
  private async getIceServers(): Promise<RTCIceServer[]> {
    const { turnMeteredDomain, turnMeteredApiKey } = environment as { turnMeteredDomain?: string; turnMeteredApiKey?: string };

    if (turnMeteredDomain && turnMeteredApiKey) {
      try {
        const response = await fetch(
          `https://${turnMeteredDomain}/api/v1/turn/credentials?apiKey=${turnMeteredApiKey}`
        );
        if (response.ok) {
          return await response.json();
        }
      } catch (e) {
        console.warn('No se pudo obtener credenciales TURN de Metered, usando solo STUN:', e);
      }
    }

    return [{ urls: 'stun:stun.l.google.com:19302' }];
  }

  /** Crea la `RTCPeerConnection` y registra los manejadores de candidatos ICE y de llegada de video remoto. */
  private async initWebRTC() {
    const iceServers = await this.getIceServers();
    this.peerConnection = new RTCPeerConnection({ iceServers });

    this.peerConnection.onicecandidate = (event) => {
      if (event.candidate) {
        this.sendSignal({
          type: 'candidate',
          candidate: event.candidate
        });
      }
    };

    this.peerConnection.ontrack = (event) => {
      if (this.videoElement.nativeElement.srcObject !== event.streams[0]) {
        this.videoElement.nativeElement.srcObject = event.streams[0];
        this.status.set('connected');
      }
    };
  }

  /**
   * Abre la conexión STOMP de señalización, se suscribe al canal propio del
   * espectador y, una vez conectado, inicia la oferta WebRTC hacia la cámara.
   */
  private connectStomp() {
    // OJO: apiUrl es ".../api/huellitas". Hay que quitar el segmento COMPLETO;
    // quitar solo "/api" dejaba "ws://host/huellitas/ws/websocket" y la
    // conexión de señalización nunca se establecía (video eternamente "Conectando...").
    const wsUrl = environment.apiUrl.replace('/api/huellitas', '').replace('http', 'ws') + '/ws/websocket';
    const myUserId = this.auth.currentUser()?.id;

    if (!myUserId) return;

    this.stompClient = new Client({
      brokerURL: wsUrl,
      // Identifica al usuario real ante el backend (ver StompAuthChannelInterceptor).
      connectHeaders: { Authorization: `Bearer ${this.auth.getToken() || ''}` },
      reconnectDelay: 5000,
      onConnect: () => {
        this.stompClient.subscribe(`/topic/webrtc/viewer-${myUserId}`, (msg) => {
          const body = JSON.parse(msg.body);
          if (body.from === this.targetStream) {
            this.handleIncomingSignal(body.payload);
          }
        });
        
        // Initiate the call
        this.createOffer();
      }
    });

    this.stompClient.activate();
  }

  /** Crea y envía la oferta SDP (solo recepción de video) para iniciar la negociación WebRTC. */
  private async createOffer() {
    this.status.set('negotiating');
    // We expect video only
    this.peerConnection.addTransceiver('video', { direction: 'recvonly' });
    
    const offer = await this.peerConnection.createOffer();
    await this.peerConnection.setLocalDescription(offer);
    
    this.sendSignal({
      type: 'offer',
      sdp: offer.sdp
    });
  }

  /**
   * Procesa un mensaje de señalización entrante: aplica la respuesta SDP de
   * la cámara o encola/agrega un candidato ICE, según corresponda. Los
   * candidatos que llegan antes que la respuesta se guardan en
   * `pendingCandidates` hasta que la descripción remota queda establecida.
   * @param payload Mensaje de señalización (`answer` o `candidate`).
   */
  private async handleIncomingSignal(payload: any) {
    if (payload.type === 'answer') {
      await this.peerConnection.setRemoteDescription(new RTCSessionDescription(payload));
      this.isRemoteSet = true;
      for (const c of this.pendingCandidates) {
        await this.peerConnection.addIceCandidate(new RTCIceCandidate(c));
      }
      this.pendingCandidates = [];
    } else if (payload.type === 'candidate') {
      if (this.isRemoteSet) {
        await this.peerConnection.addIceCandidate(new RTCIceCandidate(payload.candidate));
      } else {
        this.pendingCandidates.push(payload.candidate);
      }
    }
  }

  /**
   * Publica un mensaje de señalización WebRTC dirigido a la cámara de origen.
   * @param payload Contenido de la señal (oferta, candidato o comando).
   */
  private sendSignal(payload: any) {
    if (this.stompClient && this.stompClient.active) {
      const myUserId = this.auth.currentUser()?.id;
      this.stompClient.publish({
        destination: '/app/webrtc/signal',
        body: JSON.stringify({
          target: this.targetStream,
          from: 'viewer-' + myUserId,
          payload: payload
        })
      });
    }
  }

  /**
   * Gira físicamente la cámara moviendo el servo 3, en pasos de 30° y sin
   * pasarse de los topes. El ángulo mostrado se actualiza con lo que responde
   * el backend, que es quien recorta el valor final.
   * @param delta Grados a sumar (positivo) o restar (negativo).
   */
  girarCamara(delta: number) {
    const destino = Math.min(180, Math.max(0, this.anguloCamara() + delta));
    if (destino === this.anguloCamara()) return;

    this.iot.updateServo3({ angle: destino }).subscribe({
      next: (res: any) => this.anguloCamara.set(res?.angle ?? destino),
      error: () => {
        // Si el backend no respondió, no movemos el indicador: así no muestra
        // una posición en la que la cámara no está.
      }
    });
  }

  /** Envía a la cámara física el comando para voltear/cambiar de lente. */
  flipCamera() {
    this.sendSignal({
      type: 'command',
      command: 'flip_camera'
    });
  }
}
