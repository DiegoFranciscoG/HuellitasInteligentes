import { Component, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AdminDashboardComponent } from '../admin/admin-dashboard/admin-dashboard';
import { PropietarioDashboardComponent } from './propietario-dashboard/propietario-dashboard';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, AdminDashboardComponent, PropietarioDashboardComponent],
  template: `
    @if (isAdmin()) {
      <app-admin-dashboard></app-admin-dashboard>
    } @else {
      <app-propietario-dashboard></app-propietario-dashboard>
    }
  `
})
/**
 * Punto de entrada de la ruta del dashboard: decide, según el rol del
 * usuario en sesión, si renderiza el panel de administración o el panel
 * del propietario/miembro de la casa.
 */
export class Dashboard implements OnInit {
  /** `true` si el usuario en sesión tiene rol de administrador. */
  isAdmin = signal(false);

  /** Lee el usuario guardado en `localStorage` para determinar qué dashboard mostrar. */
  ngOnInit() {
    const userStr = localStorage.getItem('user');
    if (userStr) {
      const user = JSON.parse(userStr);
      this.isAdmin.set(user.rol === 'ADMIN' || user.rol === 'ADMINISTRADOR');
    }
  }
}
