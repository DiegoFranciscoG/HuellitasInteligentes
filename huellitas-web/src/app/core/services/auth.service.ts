import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable, tap } from 'rxjs';
import { environment } from '../../../environments/environment';

/** Resultado de una operación de autenticación exitosa: token JWT emitido y datos del usuario. */
export interface AuthResponse {
  token: string;
  usuario: any;
}

/**
 * Gestiona la autenticación y sesión del usuario (login, registro, OAuth,
 * QR, recuperación/cambio de contraseña) y la administración de miembros
 * de la vivienda. Mantiene la sesión sincronizada entre pestañas del
 * navegador mediante `BroadcastChannel` (con fallback al evento `storage`)
 * y expone al usuario actual como una signal reactiva (`currentUser`).
 */
@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private http = inject(HttpClient);
  private apiUrl = `${environment.apiUrl}/auth`;

  /** Usuario autenticado actualmente, o `null` si no hay sesión activa. */
  currentUser = signal<any | null>(null);
  private authChannel: BroadcastChannel | null = null;

  constructor() {
    this.initAuthSync();
    this.loadSession();
  }

  /**
   * Configura la sincronización de sesión entre pestañas: escucha eventos
   * de login/logout en un `BroadcastChannel` (o el evento `storage` como
   * respaldo en navegadores/entornos sin soporte) para reflejar en esta
   * pestaña los cambios de sesión hechos en otra.
   */
  private initAuthSync() {
    if (typeof window !== 'undefined' && 'BroadcastChannel' in window) {
      this.authChannel = new BroadcastChannel('auth-sync');
      this.authChannel.onmessage = (event) => {
        const { type } = event.data || {};
        if (type === 'LOGOUT') {
          this.clearAllLocal();
          if (window.location.pathname !== '/auth/login') {
            window.location.href = '/auth/login';
          }
        } else if (type === 'LOGIN' || type === 'TOKEN_REFRESHED') {
          this.loadSession();
        }
      };
    } else {
      (window as any).addEventListener('storage', (event: any) => {
        if (event.key === 'token') {
          if (!event.newValue) {
            this.clearAllLocal();
            if (window.location.pathname !== '/auth/login') {
              window.location.href = '/auth/login';
            }
          } else {
            this.loadSession();
          }
        }
      });
    }
  }

  /**
   * Notifica a las demás pestañas un evento de sesión (login/logout/token
   * refrescado) a través del `BroadcastChannel`.
   * @param type Tipo de evento (`LOGIN`, `LOGOUT`, `TOKEN_REFRESHED`).
   * @param data Datos adicionales a incluir en el mensaje.
   */
  private postAuthMessage(type: string, data?: any) {
    if (this.authChannel) {
      this.authChannel.postMessage({ type, ...data });
    }
  }

  /** Carga la sesión (usuario) desde `localStorage`/`sessionStorage` hacia `currentUser`. */
  private loadSession() {
    const token = localStorage.getItem('token') || sessionStorage.getItem('token');
    const userStr = localStorage.getItem('user') || sessionStorage.getItem('user');
    if (token && userStr) {
      try {
        this.currentUser.set(JSON.parse(userStr));
      } catch (_) {
        this.clearAll();
      }
    } else {
      this.currentUser.set(null);
    }
  }

  /** Devuelve el token JWT vigente (de `localStorage` o `sessionStorage`), o `null` si no hay sesión. */
  getToken(): string | null {
    return localStorage.getItem('token') || sessionStorage.getItem('token');
  }

  /**
   * Vuelve a pedir los datos del usuario al servidor y actualiza la sesión.
   * `loadSession()` solo lee de localStorage, así que un cambio hecho desde
   * la app móvil (por ejemplo la foto de perfil) nunca se veía aquí hasta
   * volver a iniciar sesión.
   */
  refreshCurrentUser(): void {
    if (!this.getToken()) return;
    this.http.get<any>(`${this.apiUrl}/me`).subscribe({
      next: (usuario) => {
        if (!usuario) return;
        this.currentUser.set(usuario);
        const store = localStorage.getItem('user') ? localStorage : sessionStorage;
        store.setItem('user', JSON.stringify(usuario));
      },
      error: () => { /* si falla, se mantiene la sesión cacheada */ }
    });
  }

  /**
   * Inicia sesión con email y contraseña. Al recibir la respuesta, guarda
   * la sesión localmente y notifica al resto de pestañas.
   * @param email Correo del usuario.
   * @param contrasena Contraseña en texto plano (viaja sobre HTTPS).
   */
  login(email: string, contrasena: string): Observable<AuthResponse> {
    return this.http.post<AuthResponse>(`${this.apiUrl}/login`, { email, contrasena }).pipe(
      tap(res => {
        this.setSession(res);
        this.postAuthMessage('LOGIN');
      })
    );
  }

  /**
   * Inicia sesión mediante un proveedor externo (OAuth), intercambiando el
   * token del proveedor por la sesión propia de la aplicación.
   * @param provider Nombre del proveedor OAuth (ej. "google").
   * @param token Token de acceso emitido por el proveedor.
   */
  loginOauth(provider: string, token: string): Observable<AuthResponse> {
    return this.http.post<AuthResponse>(`${this.apiUrl}/login-oauth`, { provider, token }).pipe(
      tap(res => {
        this.setSession(res);
        this.postAuthMessage('LOGIN');
      })
    );
  }

  /**
   * Registra una nueva cuenta de propietario (crea la vivienda/casa y el
   * usuario administrador de la misma) e inicia sesión automáticamente.
   * @param data Datos del formulario de registro del propietario.
   */
  registroPropietario(data: any): Observable<AuthResponse> {
    return this.http.post<AuthResponse>(`${this.apiUrl}/registro-propietario`, data).pipe(
      tap(res => {
        this.setSession(res);
        this.postAuthMessage('LOGIN');
      })
    );
  }

  /**
   * Invita a un nuevo miembro a la vivienda del usuario autenticado.
   * @param email Correo del miembro invitado.
   * @param nombre Nombre del miembro invitado.
   * @param password Contraseña inicial opcional para el miembro.
   */
  invitarMiembro(email: string, nombre: string, password?: string): Observable<any> {
    const headers = new HttpHeaders({
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.getToken() || ''}`
    });
    return this.http.post(`${this.apiUrl}/miembros`, { email, nombre, password }, { headers });
  }

  /** Lista los miembros de la vivienda del usuario autenticado. */
  listarMiembros(): Observable<any[]> {
    const headers = new HttpHeaders({
      'Authorization': `Bearer ${this.getToken() || ''}`
    });
    return this.http.get<any[]>(`${this.apiUrl}/miembros`, { headers });
  }

  /**
   * Elimina un miembro de la vivienda.
   * @param id Identificador del miembro a eliminar.
   */
  eliminarMiembro(id: number): Observable<any> {
    const headers = new HttpHeaders({
      'Authorization': `Bearer ${this.getToken() || ''}`
    });
    return this.http.delete(`${this.apiUrl}/miembros/${id}`, { headers });
  }

  /**
   * Genera un token QR para acceso rápido o bienvenida de un miembro,
   * usado por la app móvil/ESP32 para autenticación sin contraseña.
   * @param miembroId Miembro para el que se genera el QR (opcional, por defecto el propio usuario).
   * @param tipo Propósito del QR: acceso rápido recurrente o bienvenida inicial.
   */
  generarQrToken(miembroId?: number, tipo: 'ACCESO_RAPIDO' | 'BIENVENIDA' = 'ACCESO_RAPIDO'): Observable<any> {
    const headers = new HttpHeaders({
      'Authorization': `Bearer ${this.getToken() || ''}`
    });
    return this.http.post(`${this.apiUrl}/qr/generar`, null, {
      headers,
      params: {
        ...(miembroId ? { miembroId: miembroId.toString() } : {}),
        tipo
      }
    });
  }

  /**
   * Cambia la contraseña cuando el usuario está forzado a hacerlo (primer
   * ingreso o restablecimiento por un administrador), y actualiza la
   * bandera `debe_cambiar_password` en la sesión local.
   * @param nuevaPassword Nueva contraseña a establecer.
   */
  cambiarPasswordObligatorio(nuevaPassword: string): Observable<any> {
    const headers = new HttpHeaders({
      'Authorization': `Bearer ${this.getToken() || ''}`
    });
    return this.http.post(`${this.apiUrl}/cambiar-password-obligatorio`, { nuevaPassword }, { headers }).pipe(
      tap(() => {
        const u = this.currentUser();
        if (u) {
          const updatedUser = { ...u, debe_cambiar_password: false };
          this.currentUser.set(updatedUser);
          sessionStorage.setItem('user', JSON.stringify(updatedUser));
          localStorage.setItem('user', JSON.stringify(updatedUser));
        }
      })
    );
  }

  /**
   * Valida un token QR (generado por `generarQrToken`) e inicia sesión con
   * la cuenta asociada.
   * @param rawToken Token QR leído/escaneado.
   */
  validarQrToken(rawToken: string): Observable<AuthResponse> {
    return this.http.post<AuthResponse>(`${this.apiUrl}/qr/validar`, { rawToken }).pipe(
      tap(res => {
        this.setSession(res);
        this.postAuthMessage('LOGIN');
      })
    );
  }

  /** Cierra la sesión local y notifica el logout a las demás pestañas. */
  logout() {
    this.clearAll();
    this.postAuthMessage('LOGOUT');
  }

  /** Elimina el token y usuario de `localStorage`/`sessionStorage` y limpia `currentUser`, sin notificar a otras pestañas. */
  private clearAllLocal() {
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    sessionStorage.removeItem('token');
    sessionStorage.removeItem('user');
    this.currentUser.set(null);
  }

  /** Limpia por completo la sesión local (token y usuario). */
  clearAll() {
    this.clearAllLocal();
  }

  /**
   * Reconstruye la sesión a partir de un JWT ya emitido (sin volver a
   * llamar al backend), decodificando su payload para extraer los datos
   * básicos del usuario. Usado en flujos de callback OAuth.
   * @param token Token JWT recibido.
   */
  setSessionFromToken(token: string) {
    try {
      const base64Url = token.split('.')[1];
      const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
      const jsonPayload = decodeURIComponent(atob(base64).split('').map(function(c) {
          return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
      }).join(''));
      
      const payload = JSON.parse(jsonPayload);
      const user = {
        id: payload.usuario_id || payload.id,
        nombre: payload.nombre,
        email: payload.email,
        rol: payload.rol,
        casa_id: payload.casa_id,
        email_verificado: payload.email_verificado,
        debe_cambiar_password: payload.debe_cambiar_password
      };
      this.setSession({ token, usuario: user });
      this.postAuthMessage('LOGIN');
    } catch (e) {
      console.error('Error parsing token', e);
    }
  }

  /**
   * Solicita el correo de recuperación de contraseña para el email indicado.
   * @param email Correo del usuario que olvidó su contraseña.
   */
  solicitarReset(email: string): Observable<any> {
    return this.http.post(`${this.apiUrl}/solicitar-reset`, null, { params: { email } });
  }

  /**
   * Completa el restablecimiento de contraseña usando el token enviado por correo.
   * @param token Token de restablecimiento recibido por email.
   * @param nuevaPassword Nueva contraseña a establecer.
   */
  resetearPassword(token: string, nuevaPassword: string) {
    const body = { token, nuevaPassword };
    return this.http.post<any>(`${this.apiUrl}/resetear-password`, body, {
      headers: { 'Content-Type': 'application/json' }
    });
  }

  /**
   * Actualiza el nombre y/o la foto de perfil del usuario autenticado y
   * refresca la sesión local con los datos devueltos.
   * @param nombre Nuevo nombre a mostrar (vacío para no cambiarlo).
   * @param file Nueva imagen de perfil, o `null` para no cambiarla.
   */
  actualizarPerfil(nombre: string, file: File | null) {
    const formData = new FormData();
    if (nombre) {
      formData.append('nombre', nombre);
    }
    if (file) {
      formData.append('file', file);
    }
    
    const headers = new HttpHeaders({
      'Authorization': `Bearer ${this.getToken() || ''}`
    });
    
    return this.http.put<any>(`${this.apiUrl}/perfil`, formData, { headers }).pipe(
      tap(res => {
        localStorage.setItem('user', JSON.stringify(res));
        sessionStorage.setItem('user', JSON.stringify(res));
        this.currentUser.set(res);
      })
    );
  }

  /** Indica si el usuario autenticado ya tiene una contraseña establecida (relevante para cuentas creadas por OAuth o QR). */
  tienePassword(): Observable<{tiene_password: boolean}> {
    const headers = new HttpHeaders({
      'Authorization': `Bearer ${this.getToken() || ''}`
    });
    return this.http.get<{tiene_password: boolean}>(`${this.apiUrl}/tiene-password`, { headers });
  }

  /**
   * Establece por primera vez una contraseña para una cuenta que no tenía
   * (por ejemplo, creada vía OAuth o QR).
   * @param nuevaPassword Contraseña a establecer.
   */
  establecerPassword(nuevaPassword: string): Observable<any> {
    const body = new URLSearchParams();
    body.set('nuevaPassword', nuevaPassword);
    const headers = new HttpHeaders({
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization': `Bearer ${this.getToken() || ''}`
    });
    return this.http.post<any>(`${this.apiUrl}/establecer-password`, body.toString(), { headers });
  }

  /**
   * Persiste el resultado de autenticación (token + usuario) en
   * `localStorage` y `sessionStorage`, y actualiza `currentUser`. Si el
   * backend no envía el usuario completo (o falta `casa_id`), lo reconstruye
   * decodificando el payload del JWT como respaldo.
   * @param authResult Respuesta de autenticación con `token` y `usuario`.
   */
  setSession(authResult: any) {
    if (authResult?.token) {
      localStorage.setItem('token', authResult.token);
      sessionStorage.setItem('token', authResult.token);
      
      let userObj = authResult.usuario;
      if (!userObj || userObj.casa_id === undefined) {
        try {
          const base64Url = authResult.token.split('.')[1];
          const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
          const jsonPayload = decodeURIComponent(atob(base64).split('').map(function(c) {
              return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
          }).join(''));
          const payload = JSON.parse(jsonPayload);
          
          userObj = {
            id: payload.usuario_id || userObj?.id,
            nombre: payload.nombre || userObj?.nombre,
            email: payload.email || userObj?.email,
            rol: payload.rol || userObj?.rol,
            casa_id: payload.casa_id !== undefined ? payload.casa_id : userObj?.casa_id,
            email_verificado: payload.email_verificado || userObj?.email_verificado
          };
        } catch (e) {
          console.error('Error fallback parsing token', e);
        }
      }

      localStorage.setItem('user', JSON.stringify(userObj));
      sessionStorage.setItem('user', JSON.stringify(userObj));
      this.currentUser.set(userObj);
    }
  }
}
