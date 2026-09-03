import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { LucideAngularModule, CheckCircle2, AlertTriangle, Info, XCircle, X } from 'lucide-angular';
import { ToastService } from '../../../core/services/toast.service';

@Component({
  selector: 'app-toast-container',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  template: `
    <div class="fixed top-5 right-5 z-[9999] flex flex-col gap-3 max-w-sm w-full pointer-events-none" role="status" aria-live="polite">
      @for (toast of toastService.toasts(); track toast.id) {
        <div class="pointer-events-auto flex items-start gap-3 p-4 rounded-[24px] shadow-xl border backdrop-blur-md transition-all animate-slide-down"
             [ngClass]="{
               'bg-[rgba(27,48,34,0.9)] text-white border-[rgba(27,48,34,0.3)]': toast.tipo === 'success',
               'bg-[rgba(186,26,26,0.9)] text-white border-[rgba(186,26,26,0.3)]': toast.tipo === 'error',
               'bg-[rgba(253,192,3,0.9)] text-[var(--primary)] border-[rgba(253,192,3,0.3)]': toast.tipo === 'warning',
               'bg-slate-900/90 text-white border-slate-700/50': toast.tipo === 'info'
             }">
          <div class="shrink-0 mt-0.5">
            @if (toast.tipo === 'success') { <lucide-icon [img]="CheckCircle2" class="w-5 h-5 text-[var(--accent)]"></lucide-icon> }
            @else if (toast.tipo === 'error') { <lucide-icon [img]="XCircle" class="w-5 h-5 text-white"></lucide-icon> }
            @else if (toast.tipo === 'warning') { <lucide-icon [img]="AlertTriangle" class="w-5 h-5 text-[var(--primary)]"></lucide-icon> }
            @else { <lucide-icon [img]="Info" class="w-5 h-5 text-white"></lucide-icon> }
          </div>
          
          <div class="flex-1 text-sm">
            @if (toast.titulo) {
              <h4 class="font-bold text-xs uppercase tracking-wider mb-0.5 opacity-90">{{ toast.titulo }}</h4>
            }
            <p class="leading-snug text-sm font-medium">{{ toast.mensaje }}</p>
          </div>

          <button (click)="toastService.remove(toast.id)" class="p-1 transition-colors opacity-60 hover:opacity-100" aria-label="Cerrar notificación">
            <lucide-icon [img]="X" class="w-4 h-4"></lucide-icon>
          </button>
        </div>
      }
    </div>
  `
})
/**
 * Contenedor global de notificaciones tipo "toast", montado una vez en el
 * shell de la app, que renderiza la cola de mensajes de `ToastService`.
 */
export class ToastContainerComponent {
  toastService = inject(ToastService);
  CheckCircle2 = CheckCircle2;
  AlertTriangle = AlertTriangle;
  Info = Info;
  XCircle = XCircle;
  X = X;
}
