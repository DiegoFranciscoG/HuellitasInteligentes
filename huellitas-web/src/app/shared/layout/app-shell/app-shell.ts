import { Component, computed, inject, OnInit, OnDestroy, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { HttpClient } from '@angular/common/http';
import { AuthService } from '../../../core/services/auth.service';
import { DashboardService } from '../.././../core/services/dashboard.service';
import { ChatService } from '../../../core/services/chat.service';
import { environment } from '../../../../environments/environment';
import {
  LucideAngularModule,
  LayoutDashboard, Cpu, Dog, Bell, Users, UserCircle,
  LogOut, Menu, X, MessageSquare, BookOpen, BotMessageSquare,
  CreditCard, ShieldAlert, Globe, BarChart3, Bot, Server, KeyRound, Video, Download, PawPrint
} from 'lucide-angular';
import { interval, Subscription } from 'rxjs';

import { WelcomeToastComponent } from '../../components/welcome-toast/welcome-toast';
import { WelcomeToastService } from '../../../core/services/welcome-toast.service';
import { IaBubbleComponent } from '../../components/ia-bubble/ia-bubble';
import { MediaUrlPipe } from '../../pipes/media-url.pipe';

@Component({
  selector: 'app-shell',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterLinkActive, RouterOutlet, LucideAngularModule, WelcomeToastComponent, IaBubbleComponent, MediaUrlPipe],
  templateUrl: './app-shell.html',
})
/**
 * Layout raíz de la app autenticada: barra lateral de navegación (distinta
 * según el rol del usuario), notificaciones, saludo dinámico, la burbuja
 * de IA, el toast de bienvenida y el flujo de cambio de contraseña
 * obligatorio antes de dejar continuar al usuario.
 */
export class AppShellComponent implements OnInit, OnDestroy {
  private authService     = inject(AuthService);
  private dashboardService = inject(DashboardService);
  private chatService     = inject(ChatService);
  private router          = inject(Router);
  private http            = inject(HttpClient);

  sidebarOpen = signal(false);
  sidebarCollapsed = signal(false);
  isAdminRoute = computed(() => this.router.url.startsWith('/admin'));
  user = this.authService.currentUser;

  notificaciones = signal<any[]>([]);
  mostrarNotificaciones = signal(false);
  unreadCount = computed(() => this.notificaciones().filter(n => n.estado === 'PENDIENTE').length);

  /** Reactive greeting — refreshes every 60 s so it updates when the hour changes */
  private _computeGreeting(): string {
    const h = new Date().getHours();
    if (h < 12) return 'Buenos días,';
    if (h < 18) return 'Buenas tardes,';
    return 'Buenas noches,';
  }
  greetingSignal = signal<string>(this._computeGreeting());
  private _greetingSub!: Subscription;

  // Icons
  LayoutDashboard = LayoutDashboard;
  Cpu = Cpu;
  Dog = Dog;
  Bell = Bell;
  Users = Users;
  UserCircle = UserCircle;
  KeyRound = KeyRound;
  LogOut = LogOut;
  Menu = Menu;
  X = X;
  MessageSquare = MessageSquare;
  BookOpen = BookOpen;
  BotMessageSquare = BotMessageSquare;
  CreditCard = CreditCard;
  ShieldAlert = ShieldAlert;
  Globe = Globe;
  Bot = Bot;
  BarChart3 = BarChart3;
  Server = Server;
  PawPrint = PawPrint;

  // ── PROPIETARIO / MIEMBRO ── acceso a su propia casa
  propietarioNav = [
    { icon: LayoutDashboard,    label: 'Dashboard',    route: '/dashboard'    },
    { icon: Dog,                label: 'Mascotas',     route: '/mascotas'     },
    { icon: Cpu,                label: 'Dispositivos', route: '/dispositivos' },
    { icon: Video,              label: 'Cámaras',      route: '/camaras'      },
    { icon: PawPrint,           label: 'Momentos',     route: '/momentos'     },
    { icon: Bell,               label: 'Alertas',      route: '/alertas'      },
    { icon: Globe,              label: 'Comunidad',    route: '/comunidad'    },
    { icon: BookOpen,           label: 'Grupos',       route: '/grupos'       },
    { icon: BarChart3,          label: 'Historial',    route: '/historial'    },
    { icon: Server,             label: 'Historial IoT',route: '/historial-dispositivos' },
    { icon: CreditCard,         label: 'Mi Plan',      route: '/planes'       },
    { icon: UserCircle,         label: 'Perfil',       route: '/perfil'       },
  ];

  // MIEMBRO → acceso exclusivo a Cámaras y Dispositivos
  miembroNav = [
    { icon: Cpu,      label: 'Dispositivos', route: '/dispositivos' },
    { icon: Video,    label: 'Cámaras',      route: '/camaras'      },
    { icon: PawPrint, label: 'Momentos',     route: '/momentos'     },
    { icon: Bell,     label: 'Alertas',      route: '/alertas'      }
  ];

  // ── ADMINISTRADOR ── gestión de la plataforma, moderación
  adminNav = [
    { icon: LayoutDashboard,  label: 'Dashboard Admin', route: '/admin/dashboard'       },
    { icon: Users,            label: 'Usuarios',        route: '/admin/usuarios'        },
    { icon: CreditCard,       label: 'Planes',          route: '/admin/planes'          },
    { icon: BarChart3,        label: 'Suscripciones',   route: '/admin/suscripciones'   },
    { icon: ShieldAlert,      label: 'Moderación',      route: '/admin/moderacion'      },
    { icon: Bell,             label: 'Avisos Masivos',  route: '/admin/avisos'          },
    { icon: BookOpen,         label: 'Grupos (Admin)',  route: '/admin/grupos'          },
    { icon: BarChart3,        label: 'Actividad Plataforma', route: '/admin/actividad'  },
    { icon: Cpu,              label: 'Monitoreo IoT',   route: '/admin/iot'             },
    { icon: Bot,              label: 'Entrenamiento IA',route: '/admin/entrenamiento-ia'},
    { icon: Download,         label: 'Exportar Datos',  route: '/admin/exportar-datos'  },
    { icon: UserCircle,       label: 'Perfil',          route: '/perfil'                },
  ];

  private welcomeToast = inject(WelcomeToastService);

  /**
   * Si no hay sesión, redirige al login; si la hay, refresca el usuario
   * desde el servidor, muestra el toast de bienvenida, carga las
   * notificaciones según el rol y arranca el refresco periódico del saludo.
   */
  ngOnInit() {
    if (!this.user() && !this.authService.getToken()) {
      this.router.navigate(['/auth/login']);
    } else {
      // Traer los datos frescos del usuario (foto, nombre) apenas entra, para
      // que un cambio hecho desde la app se vea sin recargar ni ir a Perfil.
      this.authService.refreshCurrentUser();
      this.welcomeToast.showWelcome();
      if (this.isAdmin) {
        this.cargarNotificacionesAdmin();
      } else {
        this.cargarNotificaciones();
      }
    }
    // Refresh greeting every 60 seconds so it stays accurate without a page reload
    this._greetingSub = interval(60_000).subscribe(() => {
      this.greetingSignal.set(this._computeGreeting());
    });
  }

  /** Obtiene los avisos masivos enviados a los administradores, usados como campanita de notificaciones. */
  cargarNotificacionesAdmin() {
    this.http.get<any[]>(`${environment.apiUrl}/admin/anuncios`).subscribe({
      next: (data) => this.notificaciones.set(data || []),
      error: (err) => console.error('Error al cargar anuncios admin', err)
    });
  }

  /** Obtiene las notificaciones del usuario en sesión. */
  cargarNotificaciones() {
    if (!this.user()) return;
    this.http.get<any[]>(`${environment.apiUrl}/notificaciones?usuarioId=${this.user().id}`).subscribe({
      next: (data) => this.notificaciones.set(data),
      error: () => {}
    });
  }

  /**
   * Parte el texto de una notificación en tramos de texto plano y enlaces,
   * para poder mostrar un aviso como "hay una versión nueva: https://…" con
   * el enlace realmente clicable. `{{ }}` en la plantilla escapa el texto
   * (por seguridad, ya que el contenido lo escribe un admin) así que en vez
   * de innerHTML se arma la lista de tramos aquí y la plantilla los recorre.
   */
  segmentarMensaje(texto: string): { texto: string; url: string | null }[] {
    if (!texto) return [];
    const partes = texto.split(/(https?:\/\/[^\s]+)/g);
    return partes.filter(p => p.length > 0).map(p => ({
      texto: p,
      url: /^https?:\/\//.test(p) ? p : null,
    }));
  }

  /**
   * Clasifica una notificación por su `tipo` para pintarla con el color que
   * le corresponde: verde musgo para lo que viene de un dispositivo IoT
   * (incluye el diagnóstico manual del admin, que también es sobre un
   * aparato), dorado para un momento detectado por la cámara, terracota para
   * lo que viene de moderación, y el crema de siempre para los avisos
   * generales — el mismo criterio que ya usa `panel-alertas` para
   * CRITICA/ADVERTENCIA/INFO, aplicado aquí a `tipo` porque `/notificaciones`
   * no trae severidad.
   */
  categoriaNotificacion(tipo: string | null | undefined): 'iot' | 'momento' | 'moderacion' | 'anuncio' {
    const t = (tipo || '').toUpperCase();
    if (t === 'MOMENTO_MASCOTA') return 'momento';
    if (t.startsWith('IOT') || t === 'MANUAL_DIAGNOSTIC') return 'iot';
    if (t === 'ADVERTENCIA' || t.includes('STRIKE') || t.includes('MODERAC')) return 'moderacion';
    return 'anuncio';
  }

  /** Navega a la pantalla que corresponde al tipo de notificación, cuando tiene una. */
  abrirNotificacion(tipo: string | null | undefined) {
    if (this.categoriaNotificacion(tipo) === 'momento') {
      this.mostrarNotificaciones.set(false);
      this.router.navigate(['/momentos']);
    }
  }

  /** Muestra/oculta el panel de notificaciones y, al abrirlo, las recarga y marca como leídas. */
  toggleNotificaciones() {
    this.mostrarNotificaciones.update(v => !v);
    if (this.mostrarNotificaciones() && this.user()) {
      this.cargarNotificaciones();
      this.http.post(`${environment.apiUrl}/notificaciones/leidas?usuarioId=${this.user().id}`, {}).subscribe({
        next: () => {
          this.notificaciones.update(list => list.map(n => ({ ...n, estado: 'ENVIADO' })));
        }
      });
    }
  }

  /** Cancela el intervalo de refresco del saludo al destruir el componente. */
  ngOnDestroy() {
    this._greetingSub?.unsubscribe();
  }

  /** Cierra sesión: desconecta el chat, limpia datos cacheados y fuerza una recarga completa del navegador. */
  logout() {
    // 1. Desconectar WebSocket
    this.chatService.disconnect();
    // 2. Reset de datos cacheados
    this.dashboardService.reset();
    // 3. Limpiar sesión (localStorage + sessionStorage + signal)
    this.authService.logout();
    // 4. CRÍTICO: forzar recarga completa del navegador para destruir
    //    todo el árbol de componentes Angular y prevenir que el próximo
    //    usuario vea datos del anterior sin recargar manualmente.
    window.location.href = '/auth/login';
  }

  /** `true` si el usuario en sesión tiene rol de administrador. */
  get isAdmin(): boolean {
    return this.user()?.rol === 'ADMIN' || this.user()?.rol === 'ADMINISTRADOR';
  }

  debeCambiarPassword = computed(() => this.authService.currentUser()?.debe_cambiar_password === true);
  nuevaPasswordInput = signal('');
  confirmPasswordInput = signal('');
  errorCambioPassword = signal('');
  loadingCambioPassword = signal(false);

  /**
   * Valida y envía la nueva contraseña obligatoria, y redirige a la
   * pantalla correspondiente al rol del usuario al terminar.
   */
  guardarNuevaPassword() {
    const pass = this.nuevaPasswordInput().trim();
    const confirm = this.confirmPasswordInput().trim();
    this.errorCambioPassword.set('');

    if (pass.length < 6) {
      this.errorCambioPassword.set('La nueva contraseña debe tener al menos 6 caracteres.');
      return;
    }

    if (pass !== confirm) {
      this.errorCambioPassword.set('Las contraseñas no coinciden.');
      return;
    }

    this.loadingCambioPassword.set(true);
    this.authService.cambiarPasswordObligatorio(pass).subscribe({
      next: () => {
        this.loadingCambioPassword.set(false);
        this.nuevaPasswordInput.set('');
        this.confirmPasswordInput.set('');
        if (this.isMiembro) {
          this.router.navigate(['/dispositivos']);
        } else {
          this.router.navigate(['/dashboard']);
        }
      },
      error: (err) => {
        this.loadingCambioPassword.set(false);
        this.errorCambioPassword.set(err.error?.error || err.error?.message || 'Error al actualizar contraseña.');
      }
    });
  }

  /** `true` si el usuario en sesión tiene rol de miembro (acceso restringido). */
  get isMiembro(): boolean {
    return this.user()?.rol === 'MIEMBRO';
  }

  /** Elementos de navegación de la barra lateral, según el rol del usuario. */
  get navItems() {
    if (this.isAdmin) return this.adminNav;
    if (this.isMiembro) return this.miembroNav;
    return this.propietarioNav;
  }

  /** Primer nombre del usuario en sesión, para el saludo. */
  firstName = computed(() => {
    const n = this.user()?.nombre;
    return n ? n.split(' ')[0] : 'Usuario';
  });

  /** Navega a la pantalla completa del asistente de IA. */
  irAsistente() {
    this.router.navigate(['/asistente']);
  }
}
