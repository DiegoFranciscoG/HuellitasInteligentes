import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../../core/services/auth.service';
import { CustomValidators } from '../../../core/utils/custom-validators';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { environment } from '../../../../environments/environment';
import { LucideAngularModule, User, Home, MapPin, Loader2, LogOut, Compass, Map } from 'lucide-angular';
import * as L from 'leaflet';

@Component({
  selector: 'app-onboarding',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, LucideAngularModule],
  templateUrl: './onboarding.html'
})
/**
 * Formulario de configuración inicial del propietario tras registrarse:
 * completa nombre y datos de la vivienda (dirección/ubicación), con un
 * mapa interactivo (Leaflet) para fijar la ubicación por clic, arrastre o
 * geolocalización del navegador, con geocodificación inversa automática.
 */
export class Onboarding {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);
  private http = inject(HttpClient);

  // Icons
  User = User;
  Home = Home;
  MapPin = MapPin;
  Loader2 = Loader2;
  LogOut = LogOut;
  Compass = Compass;
  MapIcon = Map;

  showMap = signal(false);
  private map: L.Map | null = null;
  private marker: L.Marker | null = null;

  /**
   * Nombre de la vivienda de la que este usuario fue dado de baja como
   * miembro, si la hay. `null` mientras no se sabe todavía o si nunca fue
   * miembro de ninguna — en ambos casos no se muestra el aviso.
   */
  casaAnterior = signal<string | null>(null);

  constructor() {
    this.cargarCasaAnterior();
  }

  /** Consulta si el usuario llegó aquí por haber sido removido de una vivienda. */
  private cargarCasaAnterior() {
    const headers = new HttpHeaders({ Authorization: `Bearer ${this.authService.getToken() || ''}` });
    this.http.get<{ ok: boolean; nombre?: string }>(`${environment.apiUrl}/auth/casa-anterior`, { headers })
      .subscribe({
        next: (res) => { if (res.ok && res.nombre) this.casaAnterior.set(res.nombre); },
        error: () => { /* si falla, simplemente no se muestra el aviso */ }
      });
  }

  /** Cierra sesión sin crear una casa, para esperar a que el propietario vuelva a agregarlo. */
  cerrarSesionYEsperar() {
    this.authService.logout();
    this.router.navigate(['/auth/login']);
  }

  onboardingForm = this.fb.nonNullable.group({
    nombre: [this.authService.currentUser()?.nombre || '', [Validators.required, CustomValidators.nombrePersona()]],
    casa_nombre: ['', [Validators.required, CustomValidators.nombreEntidad()]],
    direccion: ['', Validators.required],
    ciudad: [''],
    latitud: [''],
    longitud: ['']
  });

  isLoading = signal(false);
  errorMessage = signal('');

  /** Envía los datos de onboarding, refresca la sesión con el nuevo token y navega al dashboard. */
  onSubmit() {
    if (this.onboardingForm.valid) {
      this.isLoading.set(true);
      this.errorMessage.set('');
      
      const payload = this.onboardingForm.getRawValue();
      const headers = new HttpHeaders({
        'Authorization': `Bearer ${this.authService.getToken() || ''}`
      });

      this.http.post<any>(`${environment.apiUrl}/auth/completar-onboarding`, payload, { headers })
        .subscribe({
          next: (res) => {
            this.authService.setSessionFromToken(res.token);
            this.router.navigate(['/dashboard']);
          },
          error: (err) => {
            this.errorMessage.set(err?.error?.message || 'Error al completar el registro.');
            this.isLoading.set(false);
          }
        });
    } else {
      this.onboardingForm.markAllAsTouched();
    }
  }

  /** Indica si un campo del formulario de onboarding es inválido y ya fue tocado/modificado. */
  isFieldInvalid(field: string): boolean {
    const ctrl = this.onboardingForm.get(field);
    return !!(ctrl && ctrl.invalid && (ctrl.dirty || ctrl.touched));
  }

  /** Cierra la sesión y vuelve a la landing (para no dejar al usuario atascado en el onboarding). */
  logout() {
    this.authService.logout();
    this.router.navigate(['/']);
  }

  /** Pide la ubicación del navegador y centra el mapa y el formulario en ella. */
  getLocation() {
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition((pos) => {
        const lat = pos.coords.latitude;
        const lng = pos.coords.longitude;
        
        this.updateLocationFromMap(lat, lng);
        
        if (this.map && this.marker) {
          const latlng = new L.LatLng(lat, lng);
          this.map.setView(latlng, 15);
          this.marker.setLatLng(latlng);
        }
      }, (err) => {
        this.errorMessage.set('No pudimos acceder a tu ubicación. Por favor, da permisos en el navegador o usa el mapa interactivo.');
      });
    } else {
      this.errorMessage.set('Tu navegador no soporta geolocalización.');
    }
  }

  /** Muestra/oculta el mapa interactivo, inicializándolo (o recalculando su tamaño) al abrirlo. */
  toggleMap() {
    this.showMap.update(v => !v);
    if (this.showMap()) {
      setTimeout(() => {
        if (!this.map) {
          this.initMap();
        } else {
          this.map.invalidateSize();
        }
      }, 100);
    }
  }

  /** Crea el mapa Leaflet con un marcador arrastrable, centrado por defecto en Quito. */
  initMap() {
    if (this.map) {
      this.map.invalidateSize();
      return;
    }
    
    // Default to a central location (e.g., Quito)
    const defaultLat = -0.180653;
    const defaultLng = -78.467838;
    
    this.map = L.map('leafletMapOnboarding').setView([defaultLat, defaultLng], 13);
    
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap'
    }).addTo(this.map);
    
    const icon = L.icon({
      iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
      iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
      shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
      iconSize: [25, 41],
      iconAnchor: [12, 41],
      popupAnchor: [1, -34],
      shadowSize: [41, 41]
    });
    
    this.marker = L.marker([defaultLat, defaultLng], { icon, draggable: true }).addTo(this.map);
    
    this.marker.on('dragend', (e) => {
      const pos = e.target.getLatLng();
      this.updateLocationFromMap(pos.lat, pos.lng);
    });
    
    this.map.on('click', (e: L.LeafletMouseEvent) => {
      if (this.marker) {
        this.marker.setLatLng(e.latlng);
        this.updateLocationFromMap(e.latlng.lat, e.latlng.lng);
      }
    });
  }

  /**
   * Actualiza las coordenadas del formulario y resuelve la dirección/ciudad
   * correspondiente mediante geocodificación inversa (Nominatim/OpenStreetMap).
   * @param lat Latitud seleccionada.
   * @param lng Longitud seleccionada.
   */
  updateLocationFromMap(lat: number, lng: number) {
    this.onboardingForm.patchValue({
      latitud: lat.toString(),
      longitud: lng.toString()
    });
    
    // Reverse Geocoding
    fetch(`https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json`)
      .then(res => res.json())
      .then(data => {
        if (data && data.address) {
          const city = data.address.city || data.address.town || data.address.village || data.address.county || 'Ubicación encontrada';
          const addressStr = data.display_name.split(',').slice(0, 2).join(',');
          
          this.onboardingForm.patchValue({ 
            ciudad: city,
            direccion: addressStr
          });
        }
      })
      .catch(err => {
        if (!this.onboardingForm.value.ciudad) {
          this.onboardingForm.patchValue({ ciudad: 'Ubicación seleccionada' });
        }
      });
  }
}
