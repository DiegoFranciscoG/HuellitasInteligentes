import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../../environments/environment';

/** Estado en vivo de todos los sensores y actuadores del ESP32 de la casa. */
export interface DeviceState {
  servo: { angle: number; status: string };
  servo2: { angle: number };
  /**
   * Servomotor que orienta la cámara de la vivienda. Opcional a propósito:
   * un backend anterior a Servo3 no devuelve este bloque.
   */
  servo3?: { angle: number; status: string };
  /** `maxPosition` es opcional porque un backend anterior no lo devolvía. */
  stepper: { position: number; maxPosition?: number };
  pump: { enabled: boolean };
  motion: { room1Entry: boolean; room1Exit: boolean; room2Entry: boolean; room2Exit: boolean };
  led: { room1Led: boolean; room2Led: boolean; automatic: boolean };
  fan: { fan1: boolean; fan2: boolean; automatic: boolean };
  dht: { temperature1: number; humidity1: number; temperature2: number; humidity2: number };
  mq135: { airQuality1: number; airQuality2: number };
  water: { level: number };
  ultrasonic: { distance: number };
  automaticMode: boolean;
}

/**
 * A quién pertenece un aparato que está latiendo en la red.
 *
 * `LIBRE` es el único que se puede reclamar. `OCUPADO` se muestra a propósito
 * —para explicar por qué ese aparato no está disponible— pero el backend no
 * revela de qué vivienda es.
 */
export type PropiedadDispositivo = 'MIO' | 'LIBRE' | 'OCUPADO';

/** Dispositivo IoT detectado en la red por su último latido. */
export interface DispositivoDescubierto {
  /** Solo lo tienen los que ya están dados de alta; un aparato libre todavía no existe en la tabla. */
  id?: number;
  mac_address: string;
  modelo: string | null;
  categoria?: string;
  tipo?: string;
  ultima_conexion: string;
  /** Segundos transcurridos desde el último latido. */
  hace_segundos: number;
  ya_vinculado: boolean;
  camara_id?: number | null;
  /** Dirección del aparato en la red local; la manda la ESP32-CAM. */
  ip_local?: string | null;
  propiedad: PropiedadDispositivo;
  reclamable: boolean;
}

/** Respuesta de la búsqueda de dispositivos en la vivienda. */
export interface DescubrimientoResponse {
  ok: boolean;
  /** Segundos que el backend considera «en línea» desde el último latido. */
  ventanaSegundos: number;
  dispositivos: DispositivoDescubierto[];
}

/** Un aparato de la vivienda con su conexión al día. */
export interface DispositivoEstado {
  id: number;
  mac_address: string;
  categoria: string;
  modelo: string | null;
  ultima_conexion: string | null;
  en_linea: boolean;
}

/**
 * Estado de conexión del IoT de la vivienda. Es la única fuente de verdad
 * para habilitar o bloquear los controles físicos, y la comparten la web y
 * la aplicación para que no haya dos criterios distintos.
 */
export interface EstadoIotResponse {
  ok: boolean;
  /** `true` si al menos un aparato de la casa dio señal dentro de la ventana. */
  conectado: boolean;
  enLinea: number;
  total: number;
  ventanaSegundos: number;
  dispositivos: DispositivoEstado[];
}

@Injectable({
  providedIn: 'root'
})
/**
 * Cliente HTTP directo hacia el firmware ESP32 (endpoints propios del
 * dispositivo, no del backend Spring Boot) para leer el estado de sensores
 * y enviar comandos a los actuadores de la casa.
 */
export class IotControlService {
  private http = inject(HttpClient);
  // OJO: environment.apiUrl es ".../api/huellitas". Antes esto usaba
  // .replace('/huellitas', ''), que en producción rompía la URL entera:
  // como el dominio es "huellitasinteligentes.duckdns.org", la palabra
  // "huellitas" aparece primero ahí (dentro de "https://huellitas...") y
  // JS reemplaza esa primera aparición, no la del final. El ancla `$`
  // fuerza a que solo cuente el "/huellitas" que está al final de la cadena.
  private apiUrl = environment.apiUrl.replace(/\/huellitas$/, '');

  /** Obtiene el estado actual de todos los sensores y actuadores del ESP32. */
  getDevices(): Observable<DeviceState> {
    return this.http.get<DeviceState>(`${this.apiUrl}/devices`);
  }

  /**
   * Activa/desactiva el modo automático de control de la casa.
   * @param enabled `true` para activar el modo automático.
   */
  setAutomaticMode(enabled: boolean): Observable<boolean> {
    return this.http.post<boolean>(`${this.apiUrl}/automatic-mode`, enabled);
  }

  /** Actualiza el estado de los LEDs de ambas habitaciones. */
  updateLed(request: { room1Led: boolean; room2Led: boolean; automatic: boolean }): Observable<any> {
    return this.http.post(`${this.apiUrl}/led`, request);
  }

  /** Actualiza el estado de los ventiladores de ambas habitaciones. */
  updateFan(request: { fan1: boolean; fan2: boolean; automatic: boolean }): Observable<any> {
    return this.http.post(`${this.apiUrl}/fan`, request);
  }

  /** Activa/desactiva la bomba de agua. */
  updatePump(request: { enabled: boolean }): Observable<any> {
    return this.http.post(`${this.apiUrl}/pump`, request);
  }

  /** Mueve el servomotor 1 al ángulo indicado. */
  updateServo1(request: { angle: number }): Observable<any> {
    return this.http.post(`${this.apiUrl}/servo`, request);
  }

  /** Mueve el servomotor 2 al ángulo indicado. */
  updateServo2(request: { angle: number }): Observable<any> {
    return this.http.post(`${this.apiUrl}/servo2`, request);
  }

  /** Gira la cámara moviendo el servomotor 3 al ángulo indicado (0–180). */
  updateServo3(request: { angle: number }): Observable<any> {
    return this.http.post(`${this.apiUrl}/servo3`, request);
  }

  /**
   * Busca los dispositivos IoT de la vivienda que dieron señales de vida hace
   * poco. No escanea la red desde el navegador —cosa que el sandbox no
   * permite—: consulta al backend, que sabe qué aparatos reportaron su latido.
   * @param soloLibres si es `true`, oculta los que ya están vinculados a una cámara.
   */
  descubrirDispositivos(soloLibres = true): Observable<DescubrimientoResponse> {
    return this.http.get<DescubrimientoResponse>(
      `${environment.apiUrl}/dispositivo/descubrir?soloLibres=${soloLibres}`);
  }

  /**
   * Da de alta en esta vivienda un aparato que está latiendo y no tiene dueño.
   * El backend responde 409 si otra cuenta se le adelantó, porque la MAC solo
   * puede pertenecer a una casa.
   *
   * @param mac dirección del aparato tal como la reportó su latido.
   * @param nombre con qué nombre se quiere ver en la lista.
   * @param categoria tipo de aparato; `CAMARA` cuando es la ESP32-CAM.
   */
  reclamarDispositivo(mac: string, nombre?: string, categoria = 'CAMARA'): Observable<any> {
    return this.http.post(`${environment.apiUrl}/dispositivo/reclamar`, { mac, nombre, categoria });
  }

  /**
   * Consulta si el IoT de la vivienda está en línea. Los controles físicos se
   * habilitan a partir de esto, pero el bloqueo real vive en el backend: aquí
   * solo se refleja, para que la pantalla no ofrezca acciones que van a fallar.
   */
  estadoIot(): Observable<EstadoIotResponse> {
    return this.http.get<EstadoIotResponse>(`${environment.apiUrl}/dispositivo/estado`);
  }

  /** Mueve el motor paso a paso (stepper) a la posición indicada. */
  updateStepper(request: { position: number }): Observable<any> {
    return this.http.post(`${this.apiUrl}/stepper`, request);
  }
}
