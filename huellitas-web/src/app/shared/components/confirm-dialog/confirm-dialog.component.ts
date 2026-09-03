import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { LucideAngularModule, AlertCircle, X } from 'lucide-angular';
import { ConfirmService } from '../../../core/services/confirm.service';

@Component({
  selector: 'app-confirm-dialog',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  template: `
    @if (confirmService.state().isOpen) {
      <div class="fixed inset-0 bg-black/60 backdrop-blur-sm z-[9999] flex items-center justify-center p-4" role="alertdialog" aria-modal="true" aria-labelledby="confirm-dialog-title">
        <div class="bg-white rounded-[32px] p-6 sm:p-8 max-w-md w-full shadow-2xl border border-gray-100 animate-scale-in">
          <div class="flex items-center justify-between mb-4">
            <div class="w-12 h-12 rounded-2xl flex items-center justify-center shrink-0"
                 [ngClass]="confirmService.state().esPeligroso ? 'bg-[var(--error-surface)] text-[var(--error)]' : 'bg-[var(--primary-surface)] text-[var(--primary)]'">
              <lucide-icon [img]="AlertCircle" class="w-6 h-6"></lucide-icon>
            </div>
            <button (click)="confirmService.state().onCancel?.()" class="p-2 hover:bg-gray-100 rounded-full text-gray-400 hover:text-gray-600" aria-label="Cancelar">
              <lucide-icon [img]="X" class="w-5 h-5"></lucide-icon>
            </button>
          </div>

          <h3 id="confirm-dialog-title" class="font-serif text-xl font-bold text-[var(--primary)] mb-2">{{ confirmService.state().titulo }}</h3>
          <p class="text-gray-600 text-sm leading-relaxed mb-6">{{ confirmService.state().mensaje }}</p>

          <div class="flex justify-end gap-3">
            <button (click)="confirmService.state().onCancel?.()" class="btn btn-ghost px-5 py-2.5 rounded-xl text-sm font-semibold">
              {{ confirmService.state().textoCancelar }}
            </button>
            <button (click)="confirmService.state().onConfirm?.()" 
                    class="btn px-6 py-2.5 rounded-xl text-sm font-bold text-white shadow-md transition-all"
                    [ngClass]="confirmService.state().esPeligroso ? 'bg-[var(--error)] hover:bg-[var(--error)]' : 'bg-[var(--primary)] hover:opacity-90'">
              {{ confirmService.state().textoConfirmar }}
            </button>
          </div>
        </div>
      </div>
    }
  `
})
/**
 * Diálogo de confirmación global montado una sola vez en el shell de la
 * app, que se muestra/oculta reactivamente según el estado de `ConfirmService`.
 */
export class ConfirmDialogComponent {
  confirmService = inject(ConfirmService);
  AlertCircle = AlertCircle;
  X = X;
}
