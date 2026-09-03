import { Component, computed, inject, OnInit, signal, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { LucideAngularModule, Cpu, CheckCircle2, Thermometer, Droplets, Wind, Zap, MoreVertical, Activity, Settings2, ShieldCheck, DoorOpen, Lightbulb, Beaker, Video, RotateCcw, RotateCw } from 'lucide-angular';
import { IotControlService, DeviceState, EstadoIotResponse } from '../services/iot-control.service';
import { Subscription, interval } from 'rxjs';

/**
 * En qué situación está el IoT de la vivienda, que es lo que decide si los
 * controles físicos se pueden usar.
 *
 * Son tres casos distintos y conviene no confundirlos, porque lo que el
 * usuario tiene que hacer en cada uno es diferente: si no hay ningún aparato
 * hay que darlo de alta; si lo hay pero está callado, hay que encenderlo.
 */
export type SituacionIot = 'SIN_IOT' | 'DESCONECTADO' | 'CONECTADO';

@Component({
  selector: 'app-panel-dispositivos',
  standalone: true,
  imports: [CommonModule, LucideAngularModule, RouterLink],
  templateUrl: './panel-dispositivos.html',
})
/**
 * Panel de control en vivo de los dispositivos ESP32 de la casa: muestra
 * el estado de sensores y actuadores, y permite controlarlos manualmente
 * (LEDs, ventiladores, bomba de agua, servos) cuando el modo automático
 * está desactivado. El estado se refresca por sondeo cada 2 segundos.
 */
export class PanelDispositivos implements OnInit, OnDestroy {
  private iotService = inject(IotControlService);
  
  deviceState = signal<DeviceState | null>(null);
  isLoading = signal<boolean>(true);
  errorMessage = signal<string | null>(null);

  /**
   * `true` cuando un sondeo en segundo plano falla después de que el panel
   * ya había cargado bien al menos una vez. A diferencia de `errorMessage`
   * (que reemplaza toda la pantalla), esto se muestra como un aviso chico
   * y se sigue reintentando cada 2 segundos con el estado anterior visible,
   * en vez de tirar todo a la pantalla de "Fallo de Conexión".
   */
  reconectando = signal<boolean>(false);

  /** Presencia del IoT de la vivienda, según los latidos que recibe el backend. */
  estadoIot = signal<EstadoIotResponse | null>(null);

  /**
   * Situación del IoT. Mientras no se sabe nada todavía se asume `CONECTADO`
   * para no parpadear un aviso de "sin dispositivos" durante la primera carga.
   */
  situacion = computed<SituacionIot>(() => {
    const e = this.estadoIot();
    if (!e) return 'CONECTADO';
    if (e.total === 0) return 'SIN_IOT';
    return e.conectado ? 'CONECTADO' : 'DESCONECTADO';
  });

  /**
   * Los controles físicos se bloquean sin IoT en línea, pero el bloqueo de
   * verdad vive en el backend: esto solo evita ofrecer botones que van a
   * fallar.
   */
  controlesBloqueados = computed(() => this.situacion() !== 'CONECTADO');
  
  // Loading states for buttons
  actionLoading = signal<Record<string, boolean>>({});

  private pollSub?: Subscription;

  // Icons
  Cpu = Cpu; CheckCircle2 = CheckCircle2; Thermometer = Thermometer; Droplets = Droplets;
  Wind = Wind; Zap = Zap; MoreVertical = MoreVertical; Activity = Activity;
  Settings2 = Settings2; ShieldCheck = ShieldCheck; DoorOpen = DoorOpen; Lightbulb = Lightbulb;
  Beaker = Beaker; Video = Video; RotateCcw = RotateCcw; RotateCw = RotateCw;

  /** Carga el estado inicial de los dispositivos y arranca el sondeo periódico cada 2 segundos. */
  ngOnInit() {
    this.loadDevices();
    this.cargarEstadoIot();
    // Poll every 2 seconds
    this.pollSub = interval(2000).subscribe(() => {
      this.loadDevices(true);
      this.cargarEstadoIot();
    });
  }

  /**
   * Consulta si la vivienda tiene aparatos dados de alta y si alguno sigue
   * latiendo. Un fallo aquí se ignora a propósito: el panel debe seguir
   * mostrando lo que sabe en vez de vaciarse por un sondeo perdido.
   */
  cargarEstadoIot() {
    this.iotService.estadoIot().subscribe({
      next: (e) => this.estadoIot.set(e),
      error: () => { /* se conserva el último estado conocido */ }
    });
  }

  /** Cancela el sondeo periódico al salir de la pantalla. */
  ngOnDestroy() {
    this.pollSub?.unsubscribe();
  }

  /**
   * Obtiene el estado actual de todos los dispositivos de la casa.
   * @param silent Si es `true`, no muestra el indicador de carga (usado en el sondeo periódico).
   */
  loadDevices(silent = false) {
    if (!silent) this.isLoading.set(true);
    
    this.iotService.getDevices().subscribe({
      next: (data) => {
        this.deviceState.set(data);
        // Si veníamos de un error (de carga o de un sondeo fallido), esta
        // respuesta buena lo cierra: sin esto, una vez que fallaba una
        // vez la pantalla se quedaba en "Fallo de Conexión" para siempre,
        // aunque el servidor ya hubiera vuelto a responder bien.
        this.errorMessage.set(null);
        this.reconectando.set(false);
        if (!silent) this.isLoading.set(false);
      },
      error: (err) => {
        console.error('Error fetching IoT state', err);
        if (!silent) {
          this.errorMessage.set('Error al conectar con los dispositivos de la casa.');
          this.isLoading.set(false);
        } else if (this.deviceState()) {
          // Ya habíamos cargado bien antes: no tiene sentido tirar todo a
          // la pantalla de error por un sondeo perdido. Se avisa con un
          // aviso chico y se sigue reintentando con el último estado
          // conocido a la vista.
          this.reconectando.set(true);
        }
      }
    });
  }

  /**
   * Marca (o desmarca) un control como "en progreso", para deshabilitar su
   * botón mientras se espera la respuesta del backend.
   * @param key Clave del control (ej. `"led1"`, `"pump"`).
   * @param state `true` mientras la acción está en curso.
   */
  setLoading(key: string, state: boolean) {
    this.actionLoading.update(prev => ({ ...prev, [key]: state }));
  }

  /** Activa/desactiva el modo automático de la casa (control manual deshabilitado mientras está activo). */
  toggleAutomaticMode() {
    const state = this.deviceState();
    if (!state) return;
    
    const newVal = !state.automaticMode;
    this.setLoading('autoMode', true);
    
    this.iotService.setAutomaticMode(newVal).subscribe({
      next: () => {
        this.loadDevices(true);
        setTimeout(() => this.setLoading('autoMode', false), 500);
      },
      error: () => this.setLoading('autoMode', false)
    });
  }

  // Controles manuales: no hacen nada si el modo automático está activo,
  // ya que en ese caso el ESP32 decide el estado por sí mismo.
  /**
   * Alterna el LED de una habitación.
   * @param room Habitación a controlar (1 o 2).
   */
  toggleLed(room: 1 | 2) {
    const state = this.deviceState();
    if (!state || state.automaticMode) return;

    this.setLoading(`led${room}`, true);
    const req = {
      room1Led: room === 1 ? !state.led.room1Led : state.led.room1Led,
      room2Led: room === 2 ? !state.led.room2Led : state.led.room2Led,
      automatic: state.led.automatic
    };

    this.iotService.updateLed(req).subscribe({
      next: () => {
        this.loadDevices(true);
        setTimeout(() => this.setLoading(`led${room}`, false), 500);
      },
      error: () => this.setLoading(`led${room}`, false)
    });
  }

  /**
   * Alterna el ventilador de una habitación.
   * @param room Habitación a controlar (1 o 2).
   */
  toggleFan(room: 1 | 2) {
    const state = this.deviceState();
    if (!state || state.automaticMode) return;

    this.setLoading(`fan${room}`, true);
    const req = {
      fan1: room === 1 ? !state.fan.fan1 : state.fan.fan1,
      fan2: room === 2 ? !state.fan.fan2 : state.fan.fan2,
      automatic: state.fan.automatic
    };

    this.iotService.updateFan(req).subscribe({
      next: () => {
        this.loadDevices(true);
        setTimeout(() => this.setLoading(`fan${room}`, false), 500);
      },
      error: () => this.setLoading(`fan${room}`, false)
    });
  }

  /** Alterna la bomba de agua. */
  togglePump() {
    const state = this.deviceState();
    if (!state || state.automaticMode) return;

    this.setLoading('pump', true);
    this.iotService.updatePump({ enabled: !state.pump.enabled }).subscribe({
      next: () => {
        this.loadDevices(true);
        setTimeout(() => this.setLoading('pump', false), 500);
      },
      error: () => this.setLoading('pump', false)
    });
  }

  /**
   * Establece el ángulo de un servomotor.
   * @param room Servo a controlar: 1 y 2 son las puertas, 3 orienta la cámara.
   * @param angle Ángulo destino, en grados.
   */
  setServo(room: 1 | 2 | 3, angle: number) {
    const state = this.deviceState();
    if (!state || state.automaticMode) return;

    this.setLoading(`servo${room}`, true);
    const obs = room === 1
      ? this.iotService.updateServo1({ angle })
      : room === 3
        ? this.iotService.updateServo3({ angle })
        : this.iotService.updateServo2({ angle });

    obs.subscribe({
      next: () => {
        this.loadDevices(true);
        setTimeout(() => this.setLoading(`servo${room}`, false), 500);
      },
      error: () => this.setLoading(`servo${room}`, false)
    });
  }

  /**
   * Gira la cámara en pasos de 30°, sin salir de los topes del servo.
   * @param delta Grados a sumar (positivo) o restar (negativo) al ángulo actual.
   */
  girarCamara(delta: number) {
    const state = this.deviceState();
    if (!state || state.automaticMode) return;

    const actual = state.servo3?.angle ?? 0;
    const destino = Math.min(180, Math.max(0, actual + delta));
    if (destino === actual) return;

    this.setServo(3, destino);
  }

  // ---------------------------------------------------------------------
  // Lecturas en crudo convertidas a algo legible.
  //
  // El firmware manda lo que sale del conversor analógico del ESP32, que va
  // de 0 a 4095, y la distancia del ultrasónico en centímetros. Mostrar esos
  // números tal cual no dice nada —y peor, poniéndoles "%" o "PPM" al lado
  // dice algo falso—, así que la conversión se hace aquí con los mismos
  // criterios que usa el firmware.
  // ---------------------------------------------------------------------

  /** Lectura del sensor de agua (0–4095) llevada a porcentaje del depósito. */
  porcentajeAgua(): number {
    const nivel = this.deviceState()?.water.level ?? 0;
    return Math.max(0, Math.min(100, Math.round((nivel / 4095) * 100)));
  }

  /** Texto del nivel de agua, con los mismos cortes que la interfaz del ESP32. */
  estadoAgua(): string {
    const p = this.porcentajeAgua();
    if (p <= 10) return 'Vacío';
    if (p <= 35) return 'Bajo';
    if (p <= 70) return 'Medio';
    return 'Lleno';
  }

  /**
   * Nivel de alimento a partir de la distancia del ultrasónico: cuanto más
   * cerca está la comida del sensor, más lleno está el depósito. Se toman
   * 30 cm como fondo del recipiente.
   */
  porcentajeComida(): number {
    const distancia = this.deviceState()?.ultrasonic.distance ?? 0;
    const fondo = 30;
    return Math.max(0, Math.min(100, Math.round(((fondo - distancia) * 100) / fondo)));
  }

  /** Texto del nivel de alimento. */
  estadoComida(): string {
    const p = this.porcentajeComida();
    if (p <= 10) return 'Vacío';
    if (p <= 30) return 'Poco alimento';
    if (p <= 70) return 'Nivel medio';
    return 'Suficiente';
  }

  /**
   * Calidad del aire según la lectura del MQ135. No son partes por millón:
   * es el valor en crudo del conversor, y etiquetarlo como PPM sería
   * inventar una unidad que el sensor no da sin calibrar.
   *
   * @param valor lectura en crudo del MQ135 (0–4095).
   */
  estadoAire(valor: number): string {
    if (valor < 1200) return 'Excelente';
    if (valor < 2000) return 'Buena';
    if (valor < 2800) return 'Regular';
    if (valor < 3400) return 'Mala';
    return 'Muy mala';
  }

  /** Color con el que se pinta la calidad del aire, del verde al rojo. */
  colorAire(valor: number): string {
    if (valor < 1200) return '#15803d';
    if (valor < 2000) return '#65a30d';
    if (valor < 2800) return '#a16207';
    if (valor < 3400) return '#c2410c';
    return '#b91c1c';
  }

  /** Recorrido máximo del dispensador según lo que declara el backend. */
  maximoDispensador(): number {
    return this.deviceState()?.stepper.maxPosition ?? 200;
  }

  /** `true` mientras el dispensador está fuera de su posición de reposo. */
  dispensadorActivo(): boolean {
    return (this.deviceState()?.stepper.position ?? 0) > 0;
  }

  /**
   * Enciende o apaga el dispensador de alimento llevando el motor al tope o
   * de vuelta al reposo.
   *
   * @param encender `true` para dispensar, `false` para volver a 0.
   */
  moverDispensador(encender: boolean) {
    const state = this.deviceState();
    if (!state || state.automaticMode) return;

    const destino = encender ? this.maximoDispensador() : 0;
    if (destino === state.stepper.position) return;

    this.setLoading('stepper', true);
    this.iotService.updateStepper({ position: destino }).subscribe({
      next: () => {
        this.loadDevices(true);
        this.setLoading('stepper', false);
      },
      error: () => this.setLoading('stepper', false)
    });
  }
}
