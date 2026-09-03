import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-skeleton-loader',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="skeleton-wrapper" [ngClass]="type">
      <div *ngFor="let _ of arrayRows" class="skeleton-row">
        <div *ngIf="type === 'card'" class="skeleton-img"></div>
        <div class="skeleton-content">
          <div class="skeleton-title"></div>
          <div class="skeleton-desc"></div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .skeleton-wrapper {
      display: flex;
      flex-direction: column;
      gap: 1rem;
    }
    .skeleton-row {
      display: flex;
      gap: 1rem;
      padding: 1rem;
      background: var(--surface, #ffffff);
      border-radius: 8px;
    }
    .skeleton-img {
      width: 48px;
      height: 48px;
      border-radius: 50%;
      background: #e2e8f0;
      animation: pulse 1.5s infinite ease-in-out;
    }
    .skeleton-content {
      flex: 1;
      display: flex;
      flex-direction: column;
      gap: 0.5rem;
      justify-content: center;
    }
    .skeleton-title {
      height: 16px;
      width: 40%;
      background: #e2e8f0;
      border-radius: 4px;
      animation: pulse 1.5s infinite ease-in-out;
    }
    .skeleton-desc {
      height: 12px;
      width: 80%;
      background: #e2e8f0;
      border-radius: 4px;
      animation: pulse 1.5s infinite ease-in-out;
    }
    @keyframes pulse {
      0% { opacity: 1; }
      50% { opacity: 0.5; }
      100% { opacity: 1; }
    }
  `]
})
/** Placeholder animado ("skeleton") mostrado mientras se cargan listas, tarjetas o tablas de datos. */
export class SkeletonLoaderComponent {
  /** Estilo visual del placeholder. */
  @Input() type: 'list' | 'card' | 'table' = 'list';
  /** Cantidad de filas/tarjetas placeholder a renderizar. */
  @Input() rows: number = 3;

  /** Arreglo auxiliar de longitud `rows`, usado para repetir el bloque placeholder con `*ngFor`. */
  get arrayRows() {
    return Array(this.rows).fill(0);
  }
}
