import { Routes } from '@angular/router';
import { roleGuard } from './core/guards/role.guard';
import { onboardingGuard } from './core/guards/onboarding.guard';

const PROPIETARIO_ROLES = ['PROPIETARIO', 'MIEMBRO'];
const ADMIN_ROLES       = ['ADMIN', 'ADMINISTRADOR'];

/**
 * Tabla de rutas de la aplicación: rutas públicas de autenticación y, bajo
 * el shell autenticado (`AppShellComponent`), las secciones de propietario/
 * miembro y de administración, cada una protegida por `roleGuard` y
 * `onboardingGuard` según corresponda. Todos los componentes se cargan de
 * forma perezosa (`loadComponent`).
 */
export const routes: Routes = [
  // ── PUBLIC ──────────────────────────────────────────────────────────────
  {
    path: '',
    loadComponent: () => import('./features/landing/landing').then(m => m.Landing)
  },
  {
    path: 'descargar',
    loadComponent: () => import('./features/descargar/descargar').then(m => m.Descargar),
  },
  {
    path: 'terminos',
    loadComponent: () => import('./features/legal/terminos/terminos').then(m => m.Terminos),
  },
  {
    path: 'privacidad',
    loadComponent: () => import('./features/legal/privacidad/privacidad').then(m => m.Privacidad),
  },
  {
    path: 'auth/login',
    loadComponent: () => import('./features/auth/login/login').then(m => m.Login),
  },
  {
    path: 'auth/register',
    loadComponent: () => import('./features/auth/register/register').then(m => m.Register),
  },
  {
    path: 'auth/onboarding',
    loadComponent: () => import('./features/auth/onboarding/onboarding').then(m => m.Onboarding),
  },
  {
    path: 'auth/forgot-password',
    loadComponent: () => import('./features/auth/forgot-password/forgot-password').then(m => m.ForgotPassword),
  },
  {
    path: 'auth/nueva-contrasena',
    loadComponent: () => import('./features/auth/reset-password/reset-password').then(m => m.ResetPassword),
  },
  {
    path: 'auth/reset-password',
    loadComponent: () => import('./features/auth/reset-password/reset-password').then(m => m.ResetPassword),
  },
  {
    path: 'auth/verificar-email',
    loadComponent: () => import('./features/auth/verificar-email/verificar-email').then(m => m.VerificarEmail),
  },
  {
    path: 'auth/qr-login',
    loadComponent: () => import('./features/auth/qr-login/qr-login').then(m => m.QrLoginComponent),
  },
  {
    path: 'oauth/callback',
    loadComponent: () => import('./features/auth/oauth-callback/oauth-callback').then(m => m.OauthCallback),
  },

  // ── APP SHELL (requires auth) ────────────────────────────────────────────
  {
    path: '',
    loadComponent: () => import('./shared/layout/app-shell/app-shell').then(m => m.AppShellComponent),
    canActivate: [roleGuard, onboardingGuard],
    children: [

      // Dashboard — router decides which sub-dashboard to render internally
      {
        path: 'dashboard',
        loadComponent: () => import('./features/dashboard/dashboard').then(m => m.Dashboard),
      },

      // ── PROPIETARIO / MIEMBRO ONLY ────────────────────────────────────
      {
        path: 'dispositivos',
        canActivate: [roleGuard],
        data: { roles: PROPIETARIO_ROLES },
        loadComponent: () => import('./features/dispositivos/panel-dispositivos/panel-dispositivos').then(m => m.PanelDispositivos),
      },
      {
        path: 'camaras',
        canActivate: [roleGuard],
        data: { roles: PROPIETARIO_ROLES },
        loadComponent: () => import('./features/camaras/camaras').then(m => m.CamarasComponent),
      },
      {
        path: 'momentos',
        canActivate: [roleGuard],
        data: { roles: PROPIETARIO_ROLES },
        loadComponent: () => import('./features/momentos/momentos').then(m => m.MomentosComponent),
      },
      {
        path: 'mascotas',
        canActivate: [roleGuard],
        data: { roles: PROPIETARIO_ROLES },
        loadComponent: () => import('./features/mascotas/mascotas').then(m => m.MascotasComponent),
      },
      {
        path: 'alertas',
        canActivate: [roleGuard],
        data: { roles: PROPIETARIO_ROLES },
        loadComponent: () => import('./features/alertas/panel-alertas/panel-alertas').then(m => m.PanelAlertas),
      },
      {
        path: 'planes',
        canActivate: [roleGuard],
        data: { roles: PROPIETARIO_ROLES },
        loadComponent: () => import('./features/planes/planes').then(m => m.Planes),
      },

      // ── SHARED (ambos roles) ──────────────────────────────────────────
      {
        path: 'comunidad',
        loadComponent: () => import('./features/comunidad/comunidad-huellitas/comunidad-huellitas').then(m => m.ComunidadHuellitas),
      },
      {
        path: 'grupos',
        loadComponent: () => import('./features/grupos/grupos').then(m => m.Grupos),
      },
      {
        path: 'chat',
        loadComponent: () => import('./features/chat/chat').then(m => m.Chat),
      },
      {
        path: 'perfil',
        loadComponent: () => import('./features/perfil/perfil').then(m => m.PerfilComponent),
      },
      {
        path: 'historial',
        loadComponent: () => import('./features/historial/historial').then(m => m.Historial),
      },
      {
        path: 'historial-dispositivos',
        loadComponent: () => import('./features/dispositivos/historial-dispositivos/historial-dispositivos').then(m => m.HistorialDispositivos),
      },
      {
        path: 'asistente',
        canActivate: [roleGuard],
        data: { roles: PROPIETARIO_ROLES },
        loadComponent: () => import('./features/asistente/asistente').then(m => m.AsistenteComponent),
      },

      // ── ADMIN ONLY ────────────────────────────────────────────────────
      {
        path: 'admin/dashboard',
        canActivate: [roleGuard],
        data: { roles: ADMIN_ROLES },
        loadComponent: () => import('./features/admin/admin-dashboard/admin-dashboard').then(m => m.AdminDashboardComponent),
      },
      {
        path: 'admin/usuarios',
        canActivate: [roleGuard],
        data: { roles: ADMIN_ROLES },
        loadComponent: () => import('./features/admin/admin-usuarios/admin-usuarios').then(m => m.AdminUsuariosComponent),
      },
      {
        path: 'admin/planes',
        canActivate: [roleGuard],
        data: { roles: ADMIN_ROLES },
        loadComponent: () => import('./features/admin/admin-planes/admin-planes').then(m => m.AdminPlanesComponent),
      },
      {
        path: 'admin/suscripciones',
        canActivate: [roleGuard],
        data: { roles: ADMIN_ROLES },
        loadComponent: () => import('./features/admin/admin-suscripciones/admin-suscripciones').then(m => m.AdminSuscripcionesComponent),
      },
      {
        path: 'admin/exportar-datos',
        canActivate: [roleGuard],
        data: { roles: ADMIN_ROLES },
        loadComponent: () => import('./features/admin/admin-exportar-datos/admin-exportar-datos').then(m => m.AdminExportarDatosComponent),
      },
      {
        path: 'admin/moderacion',
        canActivate: [roleGuard],
        data: { roles: ADMIN_ROLES },
        loadComponent: () => import('./features/admin/admin-moderacion/admin-moderacion').then(m => m.AdminModeracionComponent),
      },
      {
        path: 'admin/avisos',
        canActivate: [roleGuard],
        data: { roles: ADMIN_ROLES },
        loadComponent: () => import('./features/admin/admin-avisos/admin-avisos').then(m => m.AdminAvisosComponent),
      },
      {
        path: 'admin/grupos',
        canActivate: [roleGuard],
        data: { roles: ADMIN_ROLES },
        loadComponent: () => import('./features/admin/admin-grupos/admin-grupos').then(m => m.AdminGruposComponent),
      },
      {
        path: 'admin/actividad',
        canActivate: [roleGuard],
        data: { roles: ADMIN_ROLES },
        loadComponent: () => import('./features/admin/admin-actividad/admin-actividad').then(m => m.AdminActividadComponent),
      },
      {
        path: 'admin/iot',
        canActivate: [roleGuard],
        data: { roles: ADMIN_ROLES },
        loadComponent: () => import('./features/admin/admin-iot/admin-iot').then(m => m.AdminIotComponent),
      },
      {
        path: 'admin/entrenamiento-ia',
        canActivate: [roleGuard],
        data: { roles: ADMIN_ROLES },
        loadComponent: () => import('./features/admin/admin-entrenamiento-ia/admin-entrenamiento-ia').then(m => m.AdminEntrenamientoIaComponent),
      },
    ]
  },

  { path: '**', redirectTo: '/' }
];
