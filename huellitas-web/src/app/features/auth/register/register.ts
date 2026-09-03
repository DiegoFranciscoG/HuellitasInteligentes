import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../../core/services/auth.service';
import { CustomValidators } from '../../../core/utils/custom-validators';
import { LucideAngularModule, User, Mail, Lock, Home, MapPin, Eye, EyeOff, X, Compass, Map } from 'lucide-angular';
import * as L from 'leaflet';
import { environment } from '../../../../environments/environment';

@Component({
  selector: 'app-register',
  standalone: true,
  imports: [ReactiveFormsModule, RouterLink, CommonModule, LucideAngularModule],
  templateUrl: './register.html',
})
/**
 * Formulario de registro de un nuevo propietario: crea la cuenta y la
 * vivienda en un solo paso, con selector de ubicación por mapa interactivo
 * (Leaflet), geolocalización del navegador y geocodificación inversa.
 */
export class Register {
  private fb = inject(FormBuilder);
  private authService = inject(AuthService);
  private router = inject(Router);

  registerForm = this.fb.nonNullable.group({
    nombre:      ['', [Validators.required, CustomValidators.nombrePersona()]],
    email:       ['', [Validators.required, Validators.email]],
    password:    ['', [Validators.required, Validators.minLength(6)]],
    casa_nombre: ['', [Validators.required, CustomValidators.nombreEntidad()]],
    direccion:   [''],
    ciudad:      [''],
    latitud:     [''],
    longitud:    ['']
  });

  isLoading = signal(false);
  errorMessage = signal('');
  showPassword = signal(false);
  showMap = signal(false);
  private map: L.Map | null = null;
  private marker: L.Marker | null = null;

  // Íconos importados de Lucide
  User = User;
  Mail = Mail;
  Lock = Lock;
  Home = Home;
  MapPin = MapPin;
  Eye = Eye;
  EyeOff = EyeOff;
  X = X;
  Compass = Compass;
  MapIcon = Map;

  /** Registra al propietario y su vivienda; si el correo ya existe, muestra un mensaje específico. */
  onSubmit() {
    if (this.registerForm.valid) {
      this.isLoading.set(true);
      this.errorMessage.set('');
      this.authService.registroPropietario(this.registerForm.getRawValue()).subscribe({
        next: () => this.router.navigate(['/auth/verificar-email']),
        error: (err) => {
          const msg = err?.error?.message || err?.message || 'Error al crear la cuenta.';
          if (msg.includes('EMAIL_YA_REGISTRADO')) {
            this.errorMessage.set('Este correo ya está registrado. ¿Ya tienes cuenta?');
          } else {
            this.errorMessage.set(msg);
          }
          this.isLoading.set(false);
        },
        complete: () => this.isLoading.set(false)
      });
    } else {
      this.registerForm.markAllAsTouched();
    }
  }

  /** Redirige al flujo OAuth de Google. */
  loginWithGoogle() {
    window.location.href = `${environment.apiUrl}/auth/google/login`;
  }

  /** Redirige al flujo OAuth de Facebook. */
  loginWithFacebook() {
    window.location.href = `${environment.apiUrl}/auth/facebook/login`;
  }

  /** Indica si un campo del formulario de registro es inválido y ya fue tocado/modificado. */
  isFieldInvalid(field: string): boolean {
    const ctrl = this.registerForm.get(field);
    return !!(ctrl && ctrl.invalid && (ctrl.dirty || ctrl.touched));
  }

  /** Alterna la visibilidad del texto de la contraseña. */
  togglePassword() {
    this.showPassword.update(v => !v);
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
    
    this.map = L.map('leafletMap').setView([defaultLat, defaultLng], 13);
    
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
    this.registerForm.patchValue({
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
          
          this.registerForm.patchValue({ 
            ciudad: city,
            direccion: addressStr
          });
        }
      })
      .catch(err => {
        if (!this.registerForm.value.ciudad) {
          this.registerForm.patchValue({ ciudad: 'Ubicación seleccionada' });
        }
      });
  }
}
