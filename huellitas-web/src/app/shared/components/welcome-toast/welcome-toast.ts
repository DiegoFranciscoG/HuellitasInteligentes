import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { WelcomeToastService } from '../../../core/services/welcome-toast.service';
import { LucideAngularModule, Droplets, Sun, Bone, Footprints, Heart, X } from 'lucide-angular';

@Component({
  selector: 'app-welcome-toast',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  templateUrl: './welcome-toast.html'
})
/** Renderiza el mensaje de bienvenida diario controlado por `WelcomeToastService`. */
export class WelcomeToastComponent {
  public toastService = inject(WelcomeToastService);

  // Icons registry
  Droplets = Droplets;
  Sun = Sun;
  Bone = Bone;
  Footprints = Footprints;
  Heart = Heart;
  X = X;

  /**
   * Resuelve el componente de ícono de Lucide a partir de su nombre textual.
   * @param name Nombre del ícono (ej. `"Droplets"`).
   */
  getIcon(name: string): any {
    switch(name) {
      case 'Droplets': return Droplets;
      case 'Sun': return Sun;
      case 'Bone': return Bone;
      case 'Footprints': return Footprints;
      case 'Heart': return Heart;
      default: return Heart;
    }
  }

  /** Oculta el mensaje de bienvenida. */
  close() {
    this.toastService.hide();
  }
}
