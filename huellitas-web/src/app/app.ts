import { Component, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { ConfirmDialogComponent } from './shared/components/confirm-dialog/confirm-dialog.component';
import { ToastContainerComponent } from './shared/components/toast-container/toast-container.component';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, ConfirmDialogComponent, ToastContainerComponent],
  templateUrl: './app.html',
  styleUrl: './app.scss'
})
/** Componente raíz de la aplicación (bootstrap), monta el router, el diálogo de confirmación y los toasts globales. */
export class App {
  protected readonly title = signal('huellitas-web');
}
