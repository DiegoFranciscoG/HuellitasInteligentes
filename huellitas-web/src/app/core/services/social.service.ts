import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

/**
 * Centraliza todas las operaciones sociales de la comunidad: feed de
 * publicaciones, reacciones, comentarios, reportes, grupos temáticos,
 * moderación y sugerencias de lenguaje inclusivo.
 */
@Injectable({
  providedIn: 'root'
})
export class SocialService {
  private http = inject(HttpClient);
  private apiUrl = `${environment.apiUrl}/social`;

  // --- COMUNIDAD ---
  /**
   * Obtiene el feed de publicaciones de la comunidad visible para un usuario.
   * @param usuarioId Identificador del usuario que consulta el feed.
   */
  getFeed(usuarioId: number): Observable<any[]> {
    return this.http.get<any[]>(`${this.apiUrl}/feed?usuarioId=${usuarioId}`);
  }

  /**
   * Crea una publicación de texto (con URL de imagen opcional ya subida).
   * @param usuarioId Autor de la publicación.
   * @param contenido Texto de la publicación.
   * @param imagenUrl URL de una imagen ya alojada, si aplica.
   */
  crearPublicacion(usuarioId: number, contenido: string, imagenUrl?: string, confirmado = false): Observable<any> {
    const body = { usuarioId, contenido, imagenUrl, confirmado };
    return this.http.post(`${this.apiUrl}/publicacion`, body);
  }

  /**
   * Crea una publicación adjuntando un archivo de imagen/video directamente.
   * @param usuarioId Autor de la publicación.
   * @param contenido Texto de la publicación.
   * @param file Archivo multimedia a subir.
   * @param confirmado Si el usuario ya vio la advertencia de moderación y decidió publicar de todas formas.
   */
  crearPublicacionConArchivo(usuarioId: number, contenido: string, file: File, confirmado = false): Observable<any> {
    const formData = new FormData();
    formData.append('usuarioId', usuarioId.toString());
    formData.append('contenido', contenido);
    formData.append('file', file);
    formData.append('confirmado', confirmado.toString());
    return this.http.post(`${this.apiUrl}/publicacion/upload`, formData);
  }

  /**
   * Agrega o quita una reacción (ej. "me gusta") sobre una publicación o comentario.
   * @param itemId Identificador del ítem reaccionado.
   * @param usuarioId Usuario que reacciona.
   * @param tipo Tipo de reacción (ej. "like").
   * @param tipoItem Tipo de ítem reaccionado (ej. "publicacion", "comentario").
   * @param quitar Si es `true`, retira la reacción en lugar de agregarla.
   */
  reaccionarItem(itemId: number, usuarioId: number, tipo: string, tipoItem: string, quitar: boolean = false): Observable<any> {
    const url = `${environment.apiUrl}/reacciones/${tipoItem}/${itemId}`;
    return this.http.post(url, null, {
      params: { 
        usuarioId: usuarioId.toString(),
        tipo: tipo,
        quitar: quitar.toString()
      }
    });
  }

  /**
   * Reporta una publicación ante moderación.
   * @param publicacionId Publicación reportada.
   * @param reportadorId Usuario que reporta.
   * @param motivo Motivo del reporte.
   */
  reportarPublicacion(publicacionId: number, reportadorId: number, motivo: string): Observable<any> {
    const body = { reportadorId, motivo };
    return this.http.post(`${this.apiUrl}/publicacion/${publicacionId}/reportar`, body);
  }

  /**
   * Lista los comentarios de una publicación.
   * @param publicacionId Identificador de la publicación.
   */
  listarComentarios(publicacionId: number, usuarioId?: number): Observable<any[]> {
    const params = usuarioId ? new HttpParams().set('usuarioId', usuarioId) : undefined;
    return this.http.get<any[]>(`${this.apiUrl}/publicacion/${publicacionId}/comentarios`, { params });
  }

  /**
   * Agrega un comentario a una publicación.
   * @param publicacionId Publicación comentada.
   * @param usuarioId Autor del comentario.
   * @param contenido Texto del comentario.
   */
  comentar(publicacionId: number, usuarioId: number, contenido: string, confirmado = false): Observable<any> {
    const body = { usuarioId, contenido, confirmado };
    return this.http.post(`${this.apiUrl}/publicacion/${publicacionId}/comentar`, body);
  }

  /**
   * Edita el contenido de una publicación propia.
   * @param id Identificador de la publicación.
   * @param usuarioId Usuario que edita (debe ser el autor).
   * @param contenido Nuevo texto de la publicación.
   */
  editarPublicacion(id: number, usuarioId: number, contenido: string): Observable<any> {
    const params = new HttpParams().set('usuarioId', usuarioId).set('contenido', contenido);
    return this.http.put(`${this.apiUrl}/publicacion/${id}`, null, { params });
  }

  /**
   * Elimina una publicación propia.
   * @param id Identificador de la publicación.
   * @param usuarioId Usuario que elimina (debe ser el autor).
   */
  eliminarPublicacion(id: number, usuarioId: number): Observable<any> {
    const params = new HttpParams().set('usuarioId', usuarioId);
    return this.http.delete(`${this.apiUrl}/publicacion/${id}`, { params });
  }

  // --- GRUPOS ---
  /**
   * Lista los grupos a los que pertenece o puede unirse un usuario.
   * @param usuarioId Identificador del usuario.
   */
  listarGrupos(usuarioId: number): Observable<any[]> {
    const params = new HttpParams().set('usuarioId', usuarioId);
    return this.http.get<any[]>(`${this.apiUrl}/grupos`, { params });
  }

  /**
   * Obtiene los mensajes publicados en un grupo.
   * @param grupoId Identificador del grupo.
   * @param usuarioId Usuario que consulta (para validar membresía).
   */
  getMensajesGrupo(grupoId: number, usuarioId: number): Observable<any[]> {
    const params = new HttpParams().set('usuarioId', usuarioId);
    return this.http.get<any[]>(`${this.apiUrl}/grupos/${grupoId}/mensajes`, { params });
  }

  /**
   * Publica un mensaje (con archivo adjunto opcional) en un grupo.
   * @param grupoId Grupo destino.
   * @param usuarioId Autor del mensaje.
   * @param contenido Texto del mensaje.
   * @param file Archivo adjunto opcional.
   */
  publicarEnGrupo(grupoId: number, usuarioId: number, contenido: string, file?: File | null, confirmado = false): Observable<any> {
    const formData = new FormData();
    formData.append('usuarioId', usuarioId.toString());
    formData.append('contenido', contenido);
    formData.append('confirmado', confirmado.toString());
    if (file) {
      formData.append('file', file);
    }
    return this.http.post(`${this.apiUrl}/grupos/${grupoId}/publicar`, formData);
  }

  /**
   * Crea un nuevo grupo temático de la comunidad.
   * @param nombre Nombre del grupo.
   * @param descripcion Descripción del grupo.
   * @param creadoPor Usuario creador (queda como administrador del grupo).
   */
  crearGrupo(nombre: string, descripcion: string, creadoPor: number): Observable<any> {
    const params = new HttpParams().set('nombre', nombre).set('descripcion', descripcion).set('creadoPor', creadoPor);
    return this.http.post(`${this.apiUrl}/grupos`, null, { params });
  }

  /**
   * Une a un usuario a un grupo existente.
   * @param grupoId Grupo al que se une.
   * @param usuarioId Usuario que se une.
   */
  unirseGrupo(grupoId: number, usuarioId: number): Observable<any> {
    const params = new HttpParams().set('usuarioId', usuarioId);
    return this.http.post(`${this.apiUrl}/grupos/${grupoId}/unirse`, null, { params });
  }

  /**
   * Saca a un usuario de un grupo del que es miembro.
   * @param grupoId Grupo del que sale.
   * @param usuarioId Usuario que sale.
   */
  salirGrupo(grupoId: number, usuarioId: number): Observable<any> {
    const params = new HttpParams().set('usuarioId', usuarioId);
    return this.http.post(`${this.apiUrl}/grupos/${grupoId}/salir`, null, { params });
  }

  // --- LENGUAJE INCLUSIVO ---
  /** Lista las sugerencias de reemplazo de lenguaje inclusivo usadas al validar publicaciones. */
  listarSugerenciasInclusivas(): Observable<any[]> {
    return this.http.get<any[]>(`${this.apiUrl}/lenguaje-inclusivo`);
  }

  // --- MODERACION ---
  /**
   * Aplica un strike (llamado de atención) de moderación a un usuario.
   * @param adminId Administrador que aplica el strike.
   * @param usuarioId Usuario sancionado.
   */
  darStrike(adminId: number, usuarioId: number): Observable<any> {
    const params = new HttpParams().set('adminId', adminId).set('usuarioId', usuarioId);
    return this.http.post(`${this.apiUrl}/strike`, null, { params });
  }

  /**
   * Edita un mensaje propio de un grupo.
   * @param id Identificador del mensaje.
   * @param usuarioId Usuario que edita (debe ser el autor).
   * @param contenido Nuevo contenido del mensaje.
   */
  editarMensajeGrupo(id: number, usuarioId: number, contenido: string): Observable<any> {
    const params = new HttpParams().set('usuarioId', usuarioId).set('contenido', contenido);
    return this.http.put(`${this.apiUrl}/grupos/mensaje/${id}`, null, { params });
  }

  /**
   * Elimina un mensaje de un grupo.
   * @param id Identificador del mensaje.
   * @param usuarioId Usuario que elimina (autor o administrador del grupo).
   */
  eliminarMensajeGrupo(id: number, usuarioId: number): Observable<any> {
    const params = new HttpParams().set('usuarioId', usuarioId);
    return this.http.delete(`${this.apiUrl}/grupos/mensaje/${id}`, { params });
  }

  /**
   * Transfiere la administración de un grupo a otro miembro.
   * @param grupoId Grupo afectado.
   * @param adminId Administrador actual que transfiere.
   * @param nuevoAdminId Miembro que recibe la administración.
   */
  transferirAdminGrupo(grupoId: number, adminId: number, nuevoAdminId: number): Observable<any> {
    const params = new HttpParams().set('adminId', adminId).set('nuevoAdminId', nuevoAdminId);
    return this.http.post(`${this.apiUrl}/grupos/${grupoId}/transferir-admin`, null, { params });
  }

  /**
   * Elimina un grupo por completo.
   * @param grupoId Grupo a eliminar.
   * @param adminId Administrador del grupo que solicita la eliminación.
   */
  eliminarGrupo(grupoId: number, adminId: number): Observable<any> {
    const params = new HttpParams().set('adminId', adminId);
    return this.http.delete(`${this.apiUrl}/grupos/${grupoId}`, { params });
  }

  /**
   * Lista los miembros de un grupo con su rol, para elegir a quién expulsar
   * o a quién transferir la administración.
   * @param grupoId Grupo consultado.
   */
  miembrosGrupo(grupoId: number): Observable<any[]> {
    return this.http.get<any[]>(`${this.apiUrl}/grupos/${grupoId}/miembros`);
  }

  /**
   * Expulsa a un miembro de un grupo.
   * @param grupoId Grupo afectado.
   * @param adminId Quien expulsa (debe ser el creador o un ADMIN del grupo).
   * @param usuarioId Miembro a expulsar.
   */
  expulsarMiembroGrupo(grupoId: number, adminId: number, usuarioId: number): Observable<any> {
    const params = new HttpParams().set('adminId', adminId).set('usuarioId', usuarioId);
    return this.http.post(`${this.apiUrl}/grupos/${grupoId}/expulsar`, null, { params });
  }

  /**
   * Reporta una publicación de un grupo ante moderación (no usa el mismo
   * endpoint que el feed principal, porque las publicaciones de grupo viven
   * en otra tabla).
   * @param publicacionId Publicación de grupo reportada.
   * @param reportadorId Usuario que reporta.
   * @param motivo Motivo del reporte.
   */
  reportarPublicacionGrupo(publicacionId: number, reportadorId: number, motivo: string): Observable<any> {
    return this.http.post(`${this.apiUrl}/grupos/mensaje/${publicacionId}/reportar`, { reportadorId, motivo });
  }

  /**
   * Oculta un contenido solo para el usuario que lo pide ("eliminar para
   * mí") — sigue visible para todos los demás.
   * @param usuarioId Quien oculta el contenido.
   * @param tipo 'PUBLICACION' | 'COMENTARIO' | 'PUBLICACION_GRUPO'.
   * @param contenidoId Identificador del contenido a ocultar.
   */
  ocultarContenido(usuarioId: number, tipo: 'PUBLICACION' | 'COMENTARIO' | 'PUBLICACION_GRUPO', contenidoId: number): Observable<any> {
    return this.http.post(`${this.apiUrl}/ocultar`, { usuarioId, tipo, contenidoId });
  }
}
