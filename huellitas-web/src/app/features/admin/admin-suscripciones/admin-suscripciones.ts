import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { LucideAngularModule, CreditCard, RefreshCw, CheckCircle } from 'lucide-angular';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../../environments/environment';

@Component({
  selector: 'app-admin-suscripciones',
  standalone: true,
  imports: [CommonModule, LucideAngularModule],
  templateUrl: './admin-suscripciones.html',
})
/** Panel de administración que lista las suscripciones activas de todas las casas de la plataforma. */
export class AdminSuscripcionesComponent implements OnInit {
  private http = inject(HttpClient);

  CreditCard = CreditCard;
  RefreshCw = RefreshCw;
  CheckCircle = CheckCircle;

  suscripciones = signal<any[]>([]);
  isLoading = signal(true);

  ngOnInit() {
    this.cargarSuscripciones();
  }

  /** Obtiene todas las suscripciones registradas en la plataforma. */
  cargarSuscripciones() {
    this.isLoading.set(true);
    this.http.get<any[]>(`${environment.apiUrl}/admin/suscripciones`).subscribe({
      next: (data) => {
        this.suscripciones.set(data || []);
        this.isLoading.set(false);
      },
      error: () => this.isLoading.set(false)
    });
  }
}
