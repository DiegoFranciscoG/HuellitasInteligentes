import { Component, signal, computed, inject, OnInit, ViewChild, ElementRef, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { LucideAngularModule, Users, Plus, Hash, Shield, LogOut, ArrowLeft, Send, Smile, Image as ImageIcon, MessageSquare, AlertCircle, Sticker, Pencil, Trash2, Crown, Check, X, Video, VideoOff, Mic, MicOff, PhoneOff, Circle, Heart } from 'lucide-angular';
import { AuthService } from '../../core/services/auth.service';
import { SocialService } from '../../core/services/social.service';
import { CustomValidators } from '../../core/utils/custom-validators';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { environment } from '../../../environments/environment';
import { MediaUrlPipe } from '../../shared/pipes/media-url.pipe';

@Component({
  selector: 'app-grupos',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule, MediaUrlPipe],
  templateUrl: './grupos.html',
})
/**
 * Pantalla de grupos temáticos de la comunidad: listado y creación de
 * grupos, chat grupal (texto, imágenes, stickers, video corto y
 * videollamada 1 a 1 vía WebRTC) y edición/reacción de mensajes.
 */
export class Grupos implements OnInit, OnDestroy {
  authService = inject(AuthService);
  socialService = inject(SocialService);
  confirmService = inject(ConfirmService);
  toastService = inject(ToastService);
  http = inject(HttpClient);
  route = inject(ActivatedRoute);
  user = this.authService.currentUser;
  
  Users = Users; Plus = Plus; Hash = Hash; Shield = Shield; LogOut = LogOut; ArrowLeft = ArrowLeft; Send = Send; Smile = Smile; ImageIcon = ImageIcon; MessageSquare = MessageSquare; AlertCircle = AlertCircle; Sticker = Sticker; Pencil = Pencil; Trash2 = Trash2; Crown = Crown; Check = Check; X = X; Video = Video; VideoOff = VideoOff; Mic = Mic; MicOff = MicOff; PhoneOff = PhoneOff; Circle = Circle; Heart = Heart;

  grupos = signal<any[]>([]);
  isLoading = signal(true);
  
  nuevoGrupoNombre = signal('');
  nuevoGrupoDescripcion = signal('');
  mostrarModalCrear = signal(false);

  errorNuevoGrupoNombre = computed(() => {
    const v = this.nuevoGrupoNombre().trim();
    if (!v) return 'El nombre es obligatorio.';
    if (v.length < 2) return 'Debe tener al menos 2 caracteres.';
    const alfanumericos = v.replace(/[^a-zA-Z0-9áéíóúÁÉÍÓÚñÑ]/g, '').length;
    if (alfanumericos < 2) return 'El nombre debe contener letras o números válidos.';
    return '';
  });

  grupoActivo = signal<any>(null);
  mensajesGrupo = signal<any[]>([]);
  mostrarModalMiembros = signal(false);
  miembrosGrupoActivo = signal<any[]>([]);
  nuevoMensajeGrupo = signal('');
  mostrarEmojis = signal(false);
  mostrarStickers = signal(false);
  catStickers = signal<string[]>([]);

  // Video recording state (max 30s)
  isRecordingVideo = signal(false);
  videoSecondsLeft = signal(30);
  private mediaRecorder: MediaRecorder | null = null;
  private recordedChunks: Blob[] = [];
  private recordingTimer: any = null;

  // WebRTC 1-to-1 Video Call State
  enVideollamada = signal(false);
  micActivo = signal(true);
  camaraActiva = signal(true);
  localStream: MediaStream | null = null;
  peerConnection: RTCPeerConnection | null = null;

  @ViewChild('localVideo') localVideoRef!: ElementRef<HTMLVideoElement>;
  @ViewChild('remoteVideo') remoteVideoRef!: ElementRef<HTMLVideoElement>;

  emojis = ['😊', '😂', '🐶', '🐱', '🐾', '❤️', '👍', '🎉', '🔥', '✨', '🦴', '⚽', '🎾', '🥑', '🏆', '⭐'];
  stickers = ['🐶', '🐱', '🐾', '🦴', '🎾'];

  /** Carga los grupos disponibles y a los que pertenece el usuario. */
  ngOnInit() {
    this.cargarGrupos();
  }

  /** Detiene cualquier grabación de video o videollamada activa al salir de la pantalla. */
  ngOnDestroy() {
    this.detenerGrabacionVideo();
    this.colgarVideollamada();
  }

  /**
   * Obtiene del backend los grupos visibles para el usuario en sesión. El
   * backend ya calcula `es_miembro` y `rol_en_grupo` por usuario — antes no
   * se mapeaban a `esMiembro`/`rol` (los nombres que usa la plantilla), así
   * que un grupo al que ya te habías unido en una sesión anterior volvía a
   * mostrar el botón "Unirse" como si nunca te hubieras unido.
   */
  cargarGrupos() {
    const usuarioId = this.user()?.id || 0;
    this.http.get<any[]>(`${environment.apiUrl}/social/grupos?usuarioId=${usuarioId}`).subscribe({
      next: (data) => {
        this.grupos.set((data || []).map(g => ({
          ...g,
          esMiembro: g.es_miembro ?? g.esMiembro ?? false,
          rol: g.rol_en_grupo ?? g.rol ?? null,
          miembros: g.total_miembros ?? g.miembros ?? 0,
        })));
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }

  /**
   * Une al usuario a un grupo y abre su chat. Si el backend responde que ya
   * era miembro, igual actualiza el estado local y abre el chat en lugar de
   * mostrar un error.
   * @param grupo Grupo al que se desea unir.
   */
  unirseGrupo(grupo: any) {
    const usuarioId = this.user()?.id;
    if (!usuarioId) {
      this.toastService.error('Debes estar autenticado para unirte a un grupo.');
      return;
    }
    this.http.post<any>(`${environment.apiUrl}/social/grupos/${grupo.id}/unirse?usuarioId=${usuarioId}`, { usuarioId }).subscribe({
      next: () => {
        grupo.esMiembro = true;
        this.cargarGrupos();
        this.abrirChat(grupo);
      },
      error: (err) => {
        const errorStr = JSON.stringify(err.error || err.message || err || '');
        if (errorStr.includes('YA_ES_MIEMBRO')) {
          grupo.esMiembro = true;
          this.cargarGrupos();
          this.abrirChat(grupo);
          return;
        }
        this.toastService.error('Error al unirse al grupo.');
      }
    });
  }

  /** Valida y envía la creación de un nuevo grupo, y recarga la lista al terminar. */
  crearGrupo() {
    if (this.errorNuevoGrupoNombre()) {
      this.toastService.error(this.errorNuevoGrupoNombre());
      return;
    }
    const usuarioId = this.user()?.id || 0;

    const nombre = CustomValidators.capitalizeText(this.nuevoGrupoNombre().trim());

    this.http.post<any>(`${environment.apiUrl}/social/grupos?nombre=${encodeURIComponent(nombre)}&descripcion=${encodeURIComponent(this.nuevoGrupoDescripcion().trim())}&creadoPor=${usuarioId}`, {
      usuarioId,
      creadoPor: usuarioId,
      nombre: nombre,
      descripcion: this.nuevoGrupoDescripcion().trim()
    }).subscribe({
      next: () => {
        this.toastService.success('Grupo creado exitosamente.', 'Grupo Creado');
        this.nuevoGrupoNombre.set('');
        this.nuevoGrupoDescripcion.set('');
        this.mostrarModalCrear.set(false);
        this.cargarGrupos();
      },
      error: (err) => this.toastService.error(err.message || 'Error al crear grupo.')
    });
  }

  /**
   * Abre el chat de un grupo (solo si el usuario ya es miembro) y carga sus mensajes.
   * @param grupo Grupo cuyo chat se quiere abrir.
   */
  abrirChat(grupo: any) {
    if (!grupo.esMiembro) return;
    this.grupoActivo.set(grupo);
    this.cargarMensajesGrupo(grupo.id);
  }

  /** Cierra el chat grupal actualmente abierto. */
  cerrarChat() {
    this.grupoActivo.set(null);
    this.mensajesGrupo.set([]);
    this.mostrarModalMiembros.set(false);
  }

  /** Abre el panel de gestión de miembros (solo visible para el ADMIN del grupo). */
  abrirGestionMiembros() {
    const grupo = this.grupoActivo();
    if (!grupo) return;
    this.socialService.miembrosGrupo(grupo.id).subscribe({
      next: (data) => this.miembrosGrupoActivo.set(data || []),
      error: () => this.toastService.error('No se pudo cargar la lista de miembros.'),
    });
    this.mostrarModalMiembros.set(true);
  }

  /** Expulsa a un miembro del grupo activo (requiere confirmación). */
  async expulsarMiembro(miembro: any) {
    const grupo = this.grupoActivo();
    const adminId = this.user()?.id;
    if (!grupo || !adminId) return;
    const ok = await this.confirmService.ask({
      titulo: 'Expulsar miembro',
      mensaje: `¿Expulsar a ${miembro.nombre} del grupo "${grupo.nombre}"?`,
      textoConfirmar: 'Expulsar',
    });
    if (!ok) return;
    this.socialService.expulsarMiembroGrupo(grupo.id, adminId, miembro.id).subscribe({
      next: () => {
        this.toastService.success(`${miembro.nombre} fue expulsado del grupo.`);
        this.abrirGestionMiembros();
        this.cargarGrupos();
      },
      error: (err) => this.toastService.error(err.message || 'No se pudo expulsar al miembro.'),
    });
  }

  /** Transfiere la administración del grupo activo a otro miembro (requiere confirmación). */
  async transferirAdmin(miembro: any) {
    const grupo = this.grupoActivo();
    const adminId = this.user()?.id;
    if (!grupo || !adminId) return;
    const ok = await this.confirmService.ask({
      titulo: 'Transferir administración',
      mensaje: `¿Hacer a ${miembro.nombre} el nuevo administrador de "${grupo.nombre}"? Perderás los permisos de administrador.`,
      textoConfirmar: 'Transferir',
    });
    if (!ok) return;
    this.socialService.transferirAdminGrupo(grupo.id, adminId, miembro.id).subscribe({
      next: () => {
        this.toastService.success(`${miembro.nombre} ahora es el administrador del grupo.`);
        this.mostrarModalMiembros.set(false);
        this.cerrarChat();
        this.cargarGrupos();
      },
      error: () => this.toastService.error('No se pudo transferir la administración.'),
    });
  }

  /** Elimina por completo el grupo activo (requiere confirmación). */
  async eliminarGrupoActivo() {
    const grupo = this.grupoActivo();
    const adminId = this.user()?.id;
    if (!grupo || !adminId) return;
    const ok = await this.confirmService.ask({
      titulo: 'Eliminar grupo',
      mensaje: `¿Eliminar el grupo "${grupo.nombre}" por completo? Esta acción no se puede deshacer — se perderán todos sus mensajes.`,
      textoConfirmar: 'Eliminar grupo',
    });
    if (!ok) return;
    this.socialService.eliminarGrupo(grupo.id, adminId).subscribe({
      next: () => {
        this.toastService.success('Grupo eliminado.');
        this.cerrarChat();
        this.cargarGrupos();
      },
      error: () => this.toastService.error('No se pudo eliminar el grupo.'),
    });
  }

  /**
   * Obtiene los mensajes de un grupo.
   * @param grupoId Identificador del grupo.
   */
  cargarMensajesGrupo(grupoId: number) {
    const usuarioId = this.user()?.id || 0;
    this.http.get<any[]>(`${environment.apiUrl}/social/grupos/${grupoId}/mensajes?usuarioId=${usuarioId}`).subscribe({
      next: (data) => this.mensajesGrupo.set(data || []),
      error: (err) => console.error('Error al cargar mensajes del grupo', err)
    });
  }

  /**
   * Agrega o quita la reacción del usuario a un mensaje, actualizando el
   * contador localmente según la acción confirmada por el servidor.
   * @param msg Mensaje reaccionado.
   */
  reaccionarMensaje(msg: any) {
    const usuarioId = this.user()?.id;
    if (!usuarioId) return;

    this.http.post<any>(`${environment.apiUrl}/social/grupos/mensaje/${msg.id}/reaccionar?usuarioId=${usuarioId}`, {}).subscribe({
      next: (res) => {
        if (res.action === 'added') {
          msg.liked_by_me = true;
          msg.likes_count = (msg.likes_count || 0) + 1;
        } else {
          msg.liked_by_me = false;
          msg.likes_count = Math.max(0, (msg.likes_count || 0) - 1);
        }
      },
      error: (err) => console.error('Error al reaccionar:', err)
    });
  }

  /**
   * Indica si el mensaje todavía se puede editar: tiene que ser propio y
   * haber pasado menos de 5 minutos desde que se envió — pasado ese tiempo
   * el backend ya no lo permite, solo queda eliminarlo.
   */
  puedeEditarMensaje(msg: any): boolean {
    if (msg.usuario_id !== this.user()?.id) return false;
    const creado = new Date(msg.created_at || msg.fecha_creacion).getTime();
    return Date.now() - creado < 5 * 60 * 1000;
  }

  /** Indica si el usuario en sesión puede eliminar el mensaje para todos (autor, ADMIN del grupo o admin de la plataforma). */
  puedeEliminarMensaje(msg: any): boolean {
    return msg.usuario_id === this.user()?.id || this.grupoActivo()?.rol === 'ADMIN';
  }

  /** Activa el modo edición local para un mensaje propio, precargando su contenido actual. */
  iniciarEdicionMensaje(msg: any) {
    msg.isEditing = true;
    msg.editContent = msg.contenido;
  }

  /**
   * Envía al backend el contenido editado de un mensaje y actualiza la
   * vista local si la edición fue aceptada.
   * @param msg Mensaje en edición, con el nuevo texto en `editContent`.
   */
  guardarEdicionMensaje(msg: any) {
    const usuarioId = this.user()?.id;
    if (!usuarioId || !msg.editContent?.trim()) return;

    this.http.put<any>(`${environment.apiUrl}/social/grupos/mensaje/${msg.id}?usuarioId=${usuarioId}&contenido=${encodeURIComponent(msg.editContent.trim())}`, {}).subscribe({
      next: () => {
        msg.contenido = msg.editContent.trim();
        msg.isEditing = false;
        this.toastService.success('Mensaje actualizado');
      },
      error: (err) => this.toastService.error(err.message || 'No se pudo editar el mensaje')
    });
  }

  /** Elimina un mensaje de grupo para todos (autor, ADMIN del grupo o admin de la plataforma). */
  eliminarMensajeGrupo(msg: any) {
    const usuarioId = this.user()?.id;
    if (!usuarioId) return;
    this.http.delete<any>(`${environment.apiUrl}/social/grupos/mensaje/${msg.id}?usuarioId=${usuarioId}`).subscribe({
      next: () => {
        this.mensajesGrupo.update(m => m.filter(item => item.id !== msg.id));
        this.toastService.success('Mensaje eliminado para todos');
      },
      error: (err) => this.toastService.error(err.message || 'No se pudo eliminar el mensaje')
    });
  }

  /** Oculta un mensaje de grupo solo para el usuario en sesión ("eliminar para mí"), sin borrarlo para los demás. */
  ocultarMensajeParaMi(msg: any) {
    const usuarioId = this.user()?.id;
    if (!usuarioId) return;
    this.socialService.ocultarContenido(usuarioId, 'PUBLICACION_GRUPO', msg.id).subscribe({
      next: () => {
        this.mensajesGrupo.update(m => m.filter(item => item.id !== msg.id));
        this.toastService.success('Mensaje eliminado solo para ti');
      },
      error: (err) => this.toastService.error(err.message || 'No se pudo ocultar el mensaje')
    });
  }

  /** Abre un cuadro para redactar el motivo y denuncia un mensaje de grupo ajeno ante moderación. */
  async denunciarMensajeGrupo(msg: any) {
    const usuarioId = this.user()?.id;
    if (!usuarioId) return;
    const ok = await this.confirmService.ask({
      titulo: 'Denunciar mensaje',
      mensaje: '¿Quieres denunciar este mensaje de ' + (msg.autor_nombre || 'este usuario') + ' ante moderación?',
      textoConfirmar: 'Denunciar',
    });
    if (!ok) return;
    this.socialService.reportarPublicacionGrupo(msg.id, usuarioId, 'Contenido ofensivo reportado desde el chat del grupo').subscribe({
      next: () => this.toastService.success('Denuncia enviada a moderación.'),
      error: (err) => this.toastService.error(err.message || 'No se pudo enviar la denuncia.')
    });
  }

  /**
   * Envía el mensaje de texto redactado en el chat del grupo activo. Igual
   * que en el feed principal: si el backend responde con una advertencia de
   * moderación, se le pregunta al usuario si quiere enviarlo de todas
   * formas antes de reenviar con `confirmado=true`.
   */
  enviarMensajeGrupo(confirmado = false) {
    const txt = this.nuevoMensajeGrupo().trim();
    if (!txt || !this.grupoActivo()) return;

    const grupoId = this.grupoActivo().id;
    const usuarioId = this.user()?.id;

    this.http.post<any>(`${environment.apiUrl}/social/grupos/${grupoId}/mensajes`, {
      usuarioId,
      contenido: txt,
      confirmado
    }).subscribe({
      next: async (res: any) => {
        if (res?.advertencia) {
          const seguir = await this.confirmService.ask({
            titulo: 'Revisa tu mensaje',
            mensaje: res.mensaje || 'Este contenido podría romper nuestras reglas y afectar a otros usuarios. Te recomendamos no enviarlo.',
            textoConfirmar: 'Enviar de todas formas',
            textoCancelar: 'No enviar',
            esPeligroso: true,
          });
          if (seguir) this.enviarMensajeGrupo(true);
          return;
        }
        this.nuevoMensajeGrupo.set('');
        this.mostrarEmojis.set(false);
        this.cargarMensajesGrupo(grupoId);
      },
      error: (err) => this.toastService.error(err.message || 'Error al enviar mensaje.')
    });
  }

  /**
   * Valida el tamaño de la imagen elegida en el chat (máx. 5MB) y la envía.
   * @param event Evento `change` del input de tipo archivo.
   */
  onImageSelected(event: any) {
    const file = event.target.files[0];
    if (file) {
      if (file.size > 5 * 1024 * 1024) {
        this.toastService.error('La imagen debe ser menor a 5MB.');
        return;
      }
      this.enviarImagenGrupo(file);
    }
  }

  /**
   * Sube una imagen o video como mensaje del grupo activo.
   * @param file Archivo multimedia a enviar.
   */
  enviarImagenGrupo(file: File, confirmado = false) {
    const grupoId = this.grupoActivo()?.id;
    const usuarioId = this.user()?.id;
    if (!grupoId || !usuarioId) return;

    const formData = new FormData();
    formData.append('usuarioId', usuarioId.toString());
    formData.append('contenido', '');
    formData.append('file', file);
    formData.append('confirmado', confirmado.toString());

    this.http.post<any>(`${environment.apiUrl}/social/grupos/${grupoId}/mensajes`, formData).subscribe({
      next: async (res: any) => {
        if (res?.advertencia) {
          const seguir = await this.confirmService.ask({
            titulo: 'Revisa esta imagen',
            mensaje: res.mensaje || 'Este contenido podría romper nuestras reglas y afectar a otros usuarios. Te recomendamos no enviarlo.',
            textoConfirmar: 'Enviar de todas formas',
            textoCancelar: 'No enviar',
            esPeligroso: true,
          });
          if (seguir) this.enviarImagenGrupo(file, true);
          return;
        }
        this.cargarMensajesGrupo(grupoId);
      },
      error: (err) => this.toastService.error(err.message || 'Error al enviar imagen.')
    });
  }

  // ── GRABAR VIDEO CORTO (MÁX 30 SEGUNDOS) ──
  /**
   * Solicita permiso de cámara/micrófono e inicia la grabación de un video
   * corto para el chat, con un límite de 30 segundos controlado por un
   * temporizador que detiene la grabación automáticamente al llegar a cero.
   */
  async iniciarGrabacionVideo() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
      this.recordedChunks = [];
      this.mediaRecorder = new MediaRecorder(stream);

      this.mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) this.recordedChunks.push(event.data);
      };

      this.mediaRecorder.onstop = () => {
        const blob = new Blob(this.recordedChunks, { type: 'video/webm' });
        stream.getTracks().forEach(track => track.stop());
        this.finalizarEnvioVideo(blob);
      };

      this.mediaRecorder.start();
      this.isRecordingVideo.set(true);
      this.videoSecondsLeft.set(30);

      this.recordingTimer = setInterval(() => {
        const current = this.videoSecondsLeft() - 1;
        this.videoSecondsLeft.set(current);
        if (current <= 0) {
          this.detenerGrabacionVideo();
        }
      }, 1000);

      this.toastService.info('Grabando video (máx 30s)...', 'Grabando Video');
    } catch (e) {
      this.toastService.error('No se pudo acceder a la cámara o micrófono.', 'Error de Cámara');
    }
  }

  /** Detiene la grabación de video en curso (manual o por límite de tiempo) y dispara su envío. */
  detenerGrabacionVideo() {
    if (this.recordingTimer) {
      clearInterval(this.recordingTimer);
      this.recordingTimer = null;
    }
    if (this.mediaRecorder && this.mediaRecorder.state !== 'inactive') {
      this.mediaRecorder.stop();
    }
    this.isRecordingVideo.set(false);
  }

  /**
   * Empaqueta el video grabado como archivo y lo envía al chat del grupo.
   * @param blob Datos binarios del video grabado.
   */
  finalizarEnvioVideo(blob: Blob) {
    const file = new File([blob], 'video.webm', { type: 'video/webm' });
    this.enviarImagenGrupo(file);
    this.toastService.success('Video enviado al grupo.', 'Video Enviado');
  }

  // ── VIDEOLLAMADA WEBRTC 1 A 1 ──
  /**
   * Solicita permiso de cámara/micrófono e inicia una videollamada 1 a 1,
   * mostrando el stream local en el elemento de video correspondiente.
   */
  async iniciarVideollamada() {
    try {
      this.localStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
      this.enVideollamada.set(true);
      
      setTimeout(() => {
        if (this.localVideoRef && this.localStream) {
          this.localVideoRef.nativeElement.srcObject = this.localStream;
        }
      }, 100);

      this.toastService.success('Conectando videollamada...', 'Videollamada Iniciada');
    } catch (e) {
      this.toastService.error('No se pudo acceder a los dispositivos para la videollamada.', 'Error de Medios');
    }
  }

  /** Activa/desactiva el micrófono local durante la videollamada. */
  toggleMic() {
    if (this.localStream) {
      const audioTrack = this.localStream.getAudioTracks()[0];
      if (audioTrack) {
        audioTrack.enabled = !audioTrack.enabled;
        this.micActivo.set(audioTrack.enabled);
      }
    }
  }

  /** Activa/desactiva la cámara local durante la videollamada. */
  toggleCamara() {
    if (this.localStream) {
      const videoTrack = this.localStream.getVideoTracks()[0];
      if (videoTrack) {
        videoTrack.enabled = !videoTrack.enabled;
        this.camaraActiva.set(videoTrack.enabled);
      }
    }
  }

  /** Detiene el stream local y cierra la conexión peer de la videollamada. */
  colgarVideollamada() {
    if (this.localStream) {
      this.localStream.getTracks().forEach(track => track.stop());
      this.localStream = null;
    }
    if (this.peerConnection) {
      this.peerConnection.close();
      this.peerConnection = null;
    }
    this.enVideollamada.set(false);
    this.toastService.info('Videollamada finalizada.', 'Llamada Colgada');
  }

  /** Muestra/oculta el panel de stickers de gatos, cargándolos la primera vez que se abre. */
  toggleStickersPanel() {
    this.mostrarStickers.set(!this.mostrarStickers());
    this.mostrarEmojis.set(false);
    if (this.mostrarStickers() && this.catStickers().length === 0) {
      this.cargarCatStickers();
    }
  }

  /** Obtiene imágenes aleatorias de gatos desde The Cat API para usar como stickers, con imágenes fijas de respaldo si falla. */
  cargarCatStickers() {
    // La clave vive en environment.ts junto al resto de claves de navegador.
    const headers = new HttpHeaders({
      'x-api-key': environment.catApiKey
    });
    this.http.get<any[]>('https://api.thecatapi.com/v1/images/search?limit=9', { headers }).subscribe({
      next: (res) => {
        const urls = res.map((item) => item.url);
        this.catStickers.set(urls);
      },
      error: () => {
        this.catStickers.set([
          'https://cdn2.thecatapi.com/images/0XYvR3-47.jpg',
          'https://cdn2.thecatapi.com/images/ebv.jpg',
          'https://cdn2.thecatapi.com/images/MTY3ODIyMQ.jpg'
        ]);
      }
    });
  }

  /**
   * Envía un sticker de gato (imagen de The Cat API) como mensaje del grupo activo.
   * @param url URL de la imagen del sticker.
   */
  enviarCatSticker(url: string) {
    const grupoId = this.grupoActivo()?.id;
    const usuarioId = this.user()?.id;
    if (!grupoId || !usuarioId) {
      this.toastService.error('Debes estar autenticado para enviar stickers.');
      return;
    }

    this.http.post<any>(`${environment.apiUrl}/social/grupos/${grupoId}/mensajes`, {
      usuarioId,
      contenido: url
    }).subscribe({
      next: () => {
        this.cargarMensajesGrupo(grupoId);
        this.mostrarStickers.set(false);
      },
      error: () => this.toastService.error('Error al enviar sticker.')
    });
  }

  /**
   * Envía un sticker emoji predefinido como mensaje del grupo activo.
   * @param sticker Emoji del sticker a enviar.
   */
  enviarSticker(sticker: string) {
    const grupoId = this.grupoActivo()?.id;
    const usuarioId = this.user()?.id;
    if (!grupoId || !usuarioId) {
      this.toastService.error('Debes estar autenticado para enviar stickers.');
      return;
    }

    this.http.post<any>(`${environment.apiUrl}/social/grupos/${grupoId}/mensajes`, {
      usuarioId,
      contenido: sticker
    }).subscribe({
      next: () => {
        this.cargarMensajesGrupo(grupoId);
        this.mostrarStickers.set(false);
      },
      error: () => this.toastService.error('Error al enviar sticker.')
    });
  }

  /** Agrega un emoji al final del mensaje que se está redactando. */
  agregarEmoji(emoji: string) {
    this.nuevoMensajeGrupo.update(v => v + emoji);
  }
}
