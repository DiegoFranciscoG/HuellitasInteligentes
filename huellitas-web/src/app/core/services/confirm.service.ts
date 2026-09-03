import { Injectable, signal } from '@angular/core';

export interface ConfirmState {
  isOpen: boolean;
  titulo: string;
  mensaje: string;
  textoConfirmar?: string;
  textoCancelar?: string;
  esPeligroso?: boolean;
  onConfirm?: () => void;
  onCancel?: () => void;
}

/**
 * Reemplaza el `confirm()` nativo del navegador con un diálogo de
 * confirmación propio de la aplicación (renderizado por un componente
 * compartido que lee el estado `state`), resuelto mediante una Promise.
 */
@Injectable({
  providedIn: 'root'
})
export class ConfirmService {
  /** Estado actual del diálogo de confirmación (visibilidad, textos y callbacks). */
  state = signal<ConfirmState>({
    isOpen: false,
    titulo: '',
    mensaje: ''
  });

  /**
   * Muestra el diálogo de confirmación con las opciones dadas y devuelve
   * una promesa que se resuelve con `true` si el usuario confirma o
   * `false` si cancela.
   * @param options Título, mensaje y textos de los botones del diálogo.
   */
  ask(options: {
    titulo: string;
    mensaje: string;
    textoConfirmar?: string;
    textoCancelar?: string;
    esPeligroso?: boolean;
  }): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      this.state.set({
        isOpen: true,
        titulo: options.titulo,
        mensaje: options.mensaje,
        textoConfirmar: options.textoConfirmar || 'Sí, confirmar',
        textoCancelar: options.textoCancelar || 'Cancelar',
        esPeligroso: options.esPeligroso ?? true,
        onConfirm: () => {
          this.close();
          resolve(true);
        },
        onCancel: () => {
          this.close();
          resolve(false);
        }
      });
    });
  }

  /** Cierra el diálogo de confirmación sin alterar el resultado ya resuelto. */
  close() {
    this.state.update(s => ({ ...s, isOpen: false }));
  }
}
