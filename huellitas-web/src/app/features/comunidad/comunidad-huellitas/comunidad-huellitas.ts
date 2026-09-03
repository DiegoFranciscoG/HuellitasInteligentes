import { Component, signal, OnInit, inject, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../../environments/environment';
import { Client } from '@stomp/stompjs';
import { LucideAngularModule, Heart, MessageSquare, Share2, MoreHorizontal, Image as ImageIcon, Trash2, ShieldAlert, Save, Pencil, Flag, Send, X, EyeOff } from 'lucide-angular';
import { AuthService } from '../../../core/services/auth.service';
import { SocialService } from '../../../core/services/social.service';
import { ToastService } from '../../../core/services/toast.service';
import { ConfirmService } from '../../../core/services/confirm.service';

@Component({
  selector: 'app-comunidad-huellitas',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
  templateUrl: './comunidad-huellitas.html',
})
/**
 * Feed social de la comunidad: publicar texto/imagen/video, comentar,
 * reaccionar, buscar por texto o hashtag, moderar (editar/eliminar/aplicar
 * strikes) y recibir actualizaciones del feed en tiempo real por STOMP.
 */
export class ComunidadHuellitas implements OnInit {
  authService = inject(AuthService);
  socialService = inject(SocialService);
  http = inject(HttpClient);
  toastService = inject(ToastService);
  confirmService = inject(ConfirmService);

  isLoading = signal(true);
  private stompClient!: Client;
  user = this.authService.currentUser;
  
  isAdmin = computed(() => {
    return this.user()?.rol === 'ADMINISTRADOR' || this.user()?.rol === 'ADMIN';
  });
  
  Heart = Heart;
  MessageSquare = MessageSquare;
  Share2 = Share2;
  MoreHorizontal = MoreHorizontal;
  ImageIcon = ImageIcon;
  Trash2 = Trash2;
  ShieldAlert = ShieldAlert;
  Save = Save;
  Pencil = Pencil;
  Flag = Flag;
  Send = Send;
  X = X;
  EyeOff = EyeOff;

  posts = signal<any[]>([]);
  nuevoPost = signal<string>('');
  imagenSeleccionada = signal<string>('');
  archivoSeleccionado = signal<File | null>(null);
  esVideoPreview = signal<boolean>(false);
  errorModeracion = signal<string>('');
  sugerenciaInclusiva = signal<string>('');
  
  // Denuncia Modal
  modalDenunciaOpen = signal(false);
  postParaDenunciar = signal<any>(null);
  motivoDenuncia = signal('');

  EMOJIS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  diccionarioInclusivo = signal<any[]>([]);
  palabrasProhibidas = ['spam', 'insulto', 'basura', 'odio'];

  /**
   * Resuelve la URL de un recurso multimedia de una publicación a una URL
   * absoluta, dejando intactas las que ya son http(s), data URI o blob.
   * @param url URL relativa o absoluta devuelta por el backend.
   */
  getMediaUrl(url: string | null | undefined): string {
    if (!url) return '';
    if (url.startsWith('http') || url.startsWith('data:image') || url.startsWith('blob:')) return url;
    
    // Convert relative backend URLs to absolute URLs using the environment apiUrl
    const baseUrl = environment.apiUrl.replace('/api/huellitas', '');
    return baseUrl + (url.startsWith('/') ? url : '/' + url);
  }

  /** Carga el diccionario de lenguaje inclusivo, el feed, los hashtags destacados y abre el canal en tiempo real. */
  ngOnInit() {
    this.cargarInclusivo();
    this.cargarPosts();
    this.cargarHashtags();
    this.conectarStomp();
  }

  /** Se suscribe por STOMP al feed global para recargar las publicaciones en tiempo real cuando hay cambios. */
  conectarStomp() {
    const wsUrl = `${environment.apiUrl.replace('/api/huellitas', '')}/ws/websocket`;
    this.stompClient = new Client({
      brokerURL: wsUrl.replace('http://', 'ws://').replace('https://', 'wss://'),
      // Identifica al usuario real ante el backend (ver StompAuthChannelInterceptor).
      connectHeaders: { Authorization: `Bearer ${this.authService.getToken() || ''}` },
      reconnectDelay: 5000,
    });

    this.stompClient.onConnect = () => {
      this.stompClient.subscribe('/topic/social/feed', () => {
        this.cargarPosts(true); // Recargar feed en tiempo real de forma silenciosa
      });
    };
    
    this.stompClient.activate();
  }

  /** Cierra la conexión STOMP al destruir el componente. */
  ngOnDestroy() {
    if (this.stompClient) {
      this.stompClient.deactivate();
    }
  }

  /** Carga las sugerencias de lenguaje inclusivo usadas al redactar una publicación. */
  cargarInclusivo() {
    this.socialService.listarSugerenciasInclusivas().subscribe({
      next: (res) => this.diccionarioInclusivo.set(res),
      error: (err) => console.error(err)
    });
  }

  // ── Buscador y hashtags ────────────────────────────────────────────────
  busqueda = signal('');
  busquedaActiva = signal('');
  hashtags = signal<any[]>([]);

  /** Obtiene los hashtags más usados para mostrarlos como accesos rápidos de búsqueda. */
  cargarHashtags() {
    this.http.get<any[]>(`${environment.apiUrl}/social/hashtags?limite=12`).subscribe({
      next: (res) => this.hashtags.set(res || []),
      error: () => this.hashtags.set([])
    });
  }

  /** Aplica el texto de búsqueda actual y recarga el feed filtrado. */
  buscar() {
    this.busquedaActiva.set(this.busqueda().trim());
    this.cargarPosts();
  }

  /**
   * Busca las publicaciones asociadas a un hashtag.
   * @param tag Hashtag a buscar, sin el símbolo `#`.
   */
  buscarHashtag(tag: string) {
    this.busqueda.set('#' + tag);
    this.buscar();
  }

  /** Limpia la búsqueda activa y vuelve a mostrar el feed completo. */
  limpiarBusqueda() {
    this.busqueda.set('');
    this.busquedaActiva.set('');
    this.cargarPosts();
  }

  /**
   * Carga el feed (o los resultados de búsqueda, si hay un término activo).
   * @param silent Si es `true`, recarga sin mostrar el spinner y preserva el
   * estado local de cada post (comentarios abiertos, texto en edición, etc.),
   * usado para las actualizaciones en tiempo real vía STOMP.
   */
  cargarPosts(silent = false) {
    if (!silent) this.isLoading.set(true);
    if (!this.user()) return;

    // Con búsqueda activa se consulta el endpoint filtrado; sin ella, el feed
    // normal. Ambos devuelven la misma estructura, así que el pintado es igual.
    const termino = this.busquedaActiva();
    const origen$ = termino
      ? this.http.get<any[]>(
          `${environment.apiUrl}/social/buscar?usuarioId=${this.user().id}&q=${encodeURIComponent(termino)}`)
      : this.socialService.getFeed(this.user().id);

    origen$.subscribe({
      next: (data) => {
        const mapped = data.map(d => ({
          id: d.id,
          autorId: d.usuario_id,
          autor: d.autor_nombre,
          fotoUrl: d.autor_foto_url || null,
          initials: (d.autor_nombre || 'U')[0].toUpperCase(),
          color: '#061b0e',
          tiempo: new Date(d.created_at).toLocaleString(),
          createdAt: new Date(d.created_at).getTime(),
          contenido: d.contenido,
          imagen: d.imagen_url || null,
          mediaType: d.media_type || 'IMAGE',
          likes: parseInt(d.likes_count || '0', 10),
          comentarios: parseInt(d.total_comentarios || '0', 10),
          liked: d.liked_by_me === true || d.liked_by_me === 'true',
          reacciones: d.reacciones || [],
          editando: false,
          mostrarComentarios: false,
          listaComentarios: [],
          nuevoComentario: '',
          mostrarPicker: false
        }));
        
        if (silent) {
          // Preservar estado local (como modales de comentarios y campos de texto)
          const current = this.posts();
          const updated = mapped.map(newPost => {
            const oldPost = current.find(p => p.id === newPost.id);
            if (oldPost) {
              newPost.mostrarComentarios = oldPost.mostrarComentarios;
              newPost.listaComentarios = oldPost.listaComentarios;
              newPost.nuevoComentario = oldPost.nuevoComentario;
              newPost.editando = oldPost.editando;
              newPost.mostrarPicker = oldPost.mostrarPicker;
            }
            return newPost;
          });
          this.posts.set(updated);
        } else {
          this.posts.set(mapped);
          this.isLoading.set(false);
        }
      },
      error: () => {
        if (!silent) this.isLoading.set(false);
      }
    });
  }

  /**
   * Previsualiza el archivo (imagen o video) elegido para la nueva publicación.
   * @param event Evento `change` del input de tipo archivo.
   */
  onFileSelected(event: any) {
    const file = event.target.files[0];
    if (file) {
      this.archivoSeleccionado.set(file);
      this.esVideoPreview.set(file.type.startsWith('video/'));
      const reader = new FileReader();
      reader.onload = (e: any) => {
        this.imagenSeleccionada.set(e.target.result);
      };
      reader.readAsDataURL(file);
    }
  }

  /**
   * Publica el texto/imagen redactados, ya sea subiendo un archivo o
   * enviando una URL de imagen ya existente, y limpia el formulario al terminar.
   *
   * El backend puede responder tres cosas distintas: éxito normal, una
   * "advertencia" (200, no guardó nada — el contenido podría romper las
   * reglas pero no es grave; se le pregunta al usuario si quiere publicar
   * igual y, si acepta, se reenvía la misma petición con `confirmado=true`),
   * o un bloqueo duro (422 — contenido grave, se elimina y se aplica un
   * strike automático, sin importar la confirmación).
   *
   * @param confirmado Si ya se le mostró la advertencia y el usuario decidió publicar de todas formas.
   */
  publicar(confirmado = false) {
    let texto = this.nuevoPost();
    let img = this.imagenSeleccionada();
    if (!texto.trim() && !img) return;

    if (!this.user()) return;

    const file = this.archivoSeleccionado();
    const request$ = file
      ? this.socialService.crearPublicacionConArchivo(this.user().id, texto, file, confirmado)
      : this.socialService.crearPublicacion(this.user().id, texto, img, confirmado);

    request$.subscribe({
      next: async (res: any) => {
        if (res?.advertencia) {
          const seguir = await this.confirmService.ask({
            titulo: 'Revisa tu publicación',
            mensaje: res.mensaje || 'Este contenido podría romper nuestras reglas y afectar a otros usuarios. Te recomendamos no subirlo.',
            textoConfirmar: 'Publicar de todas formas',
            textoCancelar: 'No publicar',
            esPeligroso: true,
          });
          if (seguir) this.publicar(true);
          return;
        }
        this.cargarPosts();
        this.nuevoPost.set('');
        this.imagenSeleccionada.set('');
        this.archivoSeleccionado.set(null);
        this.esVideoPreview.set(false);
      },
      error: (err) => {
        // El interceptor global de HTTP ya extrajo el mensaje real del
        // backend (campo "message" del JSON) y lo reempaquetó como
        // `err.message` — `err.error` ya no existe en este punto.
        this.errorModeracion.set(err.message || 'No se pudo publicar.');
      }
    });
  }

  /** Muestra/oculta los comentarios de una publicación, cargándolos del servidor al abrir. */
  toggleComentarios(post: any) {
    post.mostrarComentarios = !post.mostrarComentarios;
    if (post.mostrarComentarios) {
      this.socialService.listarComentarios(post.id, this.user()?.id).subscribe({
        next: (res) => {
          post.listaComentarios = res;
          post.comentarios = res.length;
        },
        error: (err) => console.error(err)
      });
    }
  }

  /**
   * Envía el comentario redactado para una publicación y refresca su lista
   * de comentarios. Igual que {@link publicar}: si el backend responde con
   * una advertencia, se le pregunta al usuario si quiere comentar de todas
   * formas antes de reenviar con `confirmado=true`.
   */
  comentar(post: any, confirmado = false) {
    if (!post.nuevoComentario?.trim() || !this.user()) return;
    this.socialService.comentar(post.id, this.user().id, post.nuevoComentario, confirmado).subscribe({
      next: async (res: any) => {
        if (res?.advertencia) {
          const seguir = await this.confirmService.ask({
            titulo: 'Revisa tu comentario',
            mensaje: res.mensaje || 'Este contenido podría romper nuestras reglas y afectar a otros usuarios. Te recomendamos no subirlo.',
            textoConfirmar: 'Comentar de todas formas',
            textoCancelar: 'No comentar',
            esPeligroso: true,
          });
          if (seguir) this.comentar(post, true);
          return;
        }
        post.nuevoComentario = '';
        this.toggleComentarios(post);
      },
      error: (err) => this.toastService.error(err.message || 'No se pudo comentar.', 'Error al comentar')
    });
  }

  /** Indica si el usuario en sesión puede eliminar una publicación (autor o administrador) — sin límite de tiempo. */
  puedeEditarEliminar(post: any): boolean {
    if (this.isAdmin()) return true;
    return post.autorId === this.user()?.id;
  }

  /**
   * Indica si todavía se puede editar una publicación: además de ser el
   * autor (o admin), tienen que haber pasado menos de 5 minutos desde que
   * se creó — pasado ese tiempo, el backend ya no lo permite y solo queda
   * eliminarla (para uno mismo o para todos).
   */
  puedeEditar(post: any): boolean {
    if (!this.puedeEditarEliminar(post)) return false;
    if (this.isAdmin() && post.autorId !== this.user()?.id) return true; // un admin puede editar sin límite de tiempo
    const creado = new Date(post.created_at || post.createdAt).getTime();
    return Date.now() - creado < 5 * 60 * 1000;
  }

  /** Activa/desactiva el modo edición de una publicación, si el usuario tiene permiso y todavía está dentro de la ventana de 5 minutos. */
  toggleEdit(post: any) {
    if (this.puedeEditar(post)) {
      post.editando = !post.editando;
    }
  }

  /** Guarda el contenido editado de una publicación, si el usuario tiene permiso. */
  guardarEdicion(post: any) {
    if (this.puedeEditar(post)) {
      this.socialService.editarPublicacion(post.id, this.user().id, post.contenido).subscribe({
        next: () => {
          post.editando = false;
          this.toastService.success('Publicación editada');
        },
        error: (err) => {
          this.toastService.error(err.message || 'Tiempo expirado o no autorizado', 'Error al editar');
        }
      });
    }
  }

  /**
   * Elimina una publicación para todos, si el usuario tiene permiso.
   * @param id Identificador de la publicación a eliminar.
   */
  eliminarPost(id: number) {
    const post = this.posts().find(p => p.id === id);
    if (post && this.puedeEditarEliminar(post)) {
      this.socialService.eliminarPublicacion(id, this.user().id).subscribe({
        next: () => {
          this.posts.update(p => p.filter(item => item.id !== id));
          this.toastService.success('Publicación eliminada para todos');
        },
        error: (err) => {
          this.toastService.error(err.message || 'No autorizado', 'Error al eliminar');
        }
      });
    }
  }

  /**
   * Oculta una publicación solo para el usuario en sesión ("eliminar para
   * mí") — sigue visible para todos los demás. A diferencia de
   * {@link eliminarPost}, cualquiera puede ocultar cualquier publicación de
   * su propia vista, no solo el autor.
   */
  ocultarPostParaMi(id: number) {
    if (!this.user()) return;
    this.socialService.ocultarContenido(this.user().id, 'PUBLICACION', id).subscribe({
      next: () => {
        this.posts.update(p => p.filter(item => item.id !== id));
        this.toastService.success('Publicación eliminada solo para ti');
      },
      error: (err) => this.toastService.error(err.message || 'No se pudo ocultar la publicación.')
    });
  }

  /** Aplica un strike de moderación al autor de una publicación (solo administradores). */
  darStrike(post: any) {
    if (this.isAdmin() && this.user()) {
       this.socialService.darStrike(this.user().id, post.autorId).subscribe({
         next: (res) => this.toastService.success(res.message || 'Strike aplicado correctamente'),
         error: (err) => this.toastService.error(err.message, 'Error al aplicar strike')
       });
    }
  }

  /**
   * Agrupa las reacciones crudas de una publicación por tipo de emoji, con su conteo.
   * @param reacciones Lista de reacciones tal como la devuelve el backend.
   */
  agruparReacciones(reacciones: any[]): { emoji: string, count: number }[] {
    if (!reacciones || !reacciones.length || reacciones[0] === null) return [];
    const grouped = reacciones.reduce((acc: any, curr: any) => {
      if (!curr || !curr.tipo) return acc;
      acc[curr.tipo] = (acc[curr.tipo] || 0) + 1;
      return acc;
    }, {});
    return Object.keys(grouped).map(k => ({ emoji: k, count: grouped[k] }));
  }

  /** Indica si el usuario en sesión ya reaccionó con un emoji dado a un ítem (publicación o comentario). */
  haReaccionado(item: any, emoji: string): boolean {
    if (!item.reacciones || !item.reacciones.length || item.reacciones[0] === null || !this.user()) return false;
    return item.reacciones.some((r: any) => r && r.tipo === emoji && r.usuario_id === this.user()?.id);
  }

  /**
   * Agrega, cambia o quita (toggle, estilo WhatsApp) la reacción del usuario
   * sobre un ítem, actualizando el estado local de inmediato y revirtiéndolo
   * si la petición al servidor falla.
   * @param item Publicación o comentario reaccionado.
   * @param emoji Emoji de la reacción.
   * @param tipoItem Tipo de ítem reaccionado (`publicacion` por defecto).
   */
  toggleReaccion(item: any, emoji: string, tipoItem: string = 'publicacion') {
    if (!this.user()) return;
    
    // Inicializar reacciones si no existe o es null
    if (!item.reacciones || (item.reacciones.length > 0 && item.reacciones[0] === null)) {
      item.reacciones = [];
    }

    const userId = this.user().id;
    const yaReacciono = this.haReaccionado(item, emoji);

    if (yaReacciono) {
      // Si hace clic en la misma reacción que ya tiene, se quita (toggle off)
      item.reacciones = item.reacciones.filter((r: any) => !(r.tipo === emoji && r.usuario_id === userId));
    } else {
      // Si elige una nueva, primero limpiamos CUALQUIER otra reacción de este usuario (comportamiento estilo WhatsApp)
      item.reacciones = item.reacciones.filter((r: any) => r.usuario_id !== userId);
      // Y luego agregamos la nueva
      item.reacciones.push({ tipo: emoji, usuario_id: userId });
    }
    
    // Ocultar picker temporal
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
        this.toastService.error('Error al reaccionar');
      }
    });
  }

  /** Abre el modal para redactar el motivo de una denuncia sobre una publicación. */
  abrirModalDenuncia(post: any) {
    this.postParaDenunciar.set(post);
    this.motivoDenuncia.set('');
    this.modalDenunciaOpen.set(true);
  }

  /** Cierra el modal de denuncia sin enviarla. */
  cerrarModalDenuncia() {
    this.modalDenunciaOpen.set(false);
    this.postParaDenunciar.set(null);
    this.motivoDenuncia.set('');
  }

  /** Envía a moderación la denuncia redactada sobre la publicación seleccionada. */
  denunciarPostConfirmado() {
    const post = this.postParaDenunciar();
    const motivo = this.motivoDenuncia().trim();
    if (!post || !motivo || !this.user()) return;
    
    this.socialService.reportarPublicacion(post.id, this.user().id, motivo).subscribe({
      next: () => {
        this.toastService.success('Denuncia enviada correctamente a moderación.');
        this.cerrarModalDenuncia();
      },
      error: () => {
        this.toastService.error('Error al enviar denuncia.');
        this.cerrarModalDenuncia();
      }
    });
  }
}
