import { Injectable, signal } from '@angular/core';

export interface ToastMessage {
  id: number;
  tipo: 'success' | 'error' | 'info' | 'warning';
  titulo?: string;
  mensaje: string;
}

/**
 * Gestiona las notificaciones tipo "toast" mostradas al usuario (éxito,
 * error, información, advertencia), manteniendo la cola de mensajes activos
 * como signal para que `ToastContainerComponent` la renderice.
 */
@Injectable({
  providedIn: 'root'
})
export class ToastService {
  /** Lista de toasts actualmente visibles, más recientes primero. */
  toasts = signal<ToastMessage[]>([]);
  private count = 0;

  /** Muestra un toast de éxito. */
  success(mensaje: string, titulo: string = '¡Éxito!') {
    this.addToast('success', mensaje, titulo);
  }

  /** Muestra un toast de error. */
  error(mensaje: string, titulo: string = 'Error') {
    this.addToast('error', mensaje, titulo);
  }

  /** Muestra un toast informativo. */
  info(mensaje: string, titulo: string = 'Información') {
    this.addToast('info', mensaje, titulo);
  }

  /** Muestra un toast de advertencia. */
  warning(mensaje: string, titulo: string = 'Atención') {
    this.addToast('warning', mensaje, titulo);
  }

  /**
   * Agrega un toast a la cola y programa su desaparición automática a los 4 segundos.
   * @param tipo Variante visual del toast.
   * @param mensaje Contenido del mensaje.
   * @param titulo Título opcional del toast.
   */
  private addToast(tipo: 'success' | 'error' | 'info' | 'warning', mensaje: string, titulo?: string) {
    const id = ++this.count;
    const item: ToastMessage = { id, tipo, mensaje, titulo };
    this.toasts.update(list => [item, ...list]);

    setTimeout(() => {
      this.remove(id);
    }, 4000);
  }

  /**
   * Retira un toast de la cola.
   * @param id Identificador del toast a remover.
   */
  remove(id: number) {
    this.toasts.update(list => list.filter(t => t.id !== id));
  }
}
