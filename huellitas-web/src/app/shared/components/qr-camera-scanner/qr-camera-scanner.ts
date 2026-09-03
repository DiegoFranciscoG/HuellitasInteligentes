import {
  Component, ElementRef, EventEmitter, OnDestroy, Output,
  ViewChild, AfterViewInit, signal
} from '@angular/core';
import { CommonModule } from '@angular/common';
import jsQR from 'jsqr';

/**
 * Lector de códigos QR usando la cámara del equipo.
 * Pensado para escanear, desde la PC, el QR que se muestra en el celular.
 *
 * Emite `scanned` con el texto del código en cuanto lo reconoce y libera la
 * cámara automáticamente al destruirse para que no quede el led encendido.
 */
@Component({
  selector: 'app-qr-camera-scanner',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="w-full max-w-sm mx-auto">
      <div class="relative w-full aspect-square overflow-hidden rounded-2xl bg-black">
        <video #video class="w-full h-full object-cover" playsinline muted></video>

        <!-- Guía de encuadre -->
        @if (!error()) {
          <div class="pointer-events-none absolute inset-0 flex items-center justify-center">
            <div class="w-3/5 h-3/5 rounded-xl border-2 border-white/80 shadow-[0_0_0_9999px_rgba(0,0,0,0.35)]"></div>
          </div>
        }

        @if (cargando()) {
          <div class="absolute inset-0 flex items-center justify-center bg-black/70">
            <span class="text-white text-sm">Abriendo cámara…</span>
          </div>
        }
      </div>

      <canvas #canvas class="hidden"></canvas>

      @if (error()) {
        <p class="mt-3 text-sm text-[var(--error)] text-center">{{ error() }}</p>
      } @else {
        <p class="mt-3 text-sm text-slate-500 text-center">
          Muestra el código QR de tu celular frente a la cámara.
        </p>
      }
    </div>
  `
})
export class QrCameraScannerComponent implements AfterViewInit, OnDestroy {
  @ViewChild('video') videoRef!: ElementRef<HTMLVideoElement>;
  @ViewChild('canvas') canvasRef!: ElementRef<HTMLCanvasElement>;

  /** Emite el texto decodificado en cuanto la cámara reconoce un código QR válido. */
  @Output() scanned = new EventEmitter<string>();

  cargando = signal(true);
  error = signal('');

  private stream: MediaStream | null = null;
  private frameId: number | null = null;
  private detenido = false;

  /** Solicita acceso a la cámara trasera (o única, en PC) y arranca el bucle de escaneo. */
  async ngAfterViewInit() {
    if (!navigator.mediaDevices?.getUserMedia) {
      this.cargando.set(false);
      this.error.set('Este navegador no permite usar la cámara.');
      return;
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment' },
        audio: false
      });
      const video = this.videoRef.nativeElement;
      video.srcObject = this.stream;
      await video.play();
      this.cargando.set(false);
      this.escanear();
    } catch (e: any) {
      this.cargando.set(false);
      this.error.set(
        e?.name === 'NotAllowedError'
          ? 'Permiso de cámara denegado. Actívalo en el navegador para escanear.'
          : 'No se pudo acceder a la cámara de este equipo.'
      );
    }
  }

  /**
   * Captura el fotograma actual del video, intenta decodificar un QR en él
   * y, si lo logra, emite `scanned` y detiene la cámara; si no, se
   * reprograma para el siguiente fotograma vía `requestAnimationFrame`.
   */
  private escanear = () => {
    if (this.detenido) return;

    const video = this.videoRef.nativeElement;
    const canvas = this.canvasRef.nativeElement;

    if (video.readyState === video.HAVE_ENOUGH_DATA) {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const ctx = canvas.getContext('2d', { willReadFrequently: true });

      if (ctx && canvas.width && canvas.height) {
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        const imagen = ctx.getImageData(0, 0, canvas.width, canvas.height);
        const codigo = jsQR(imagen.data, imagen.width, imagen.height, {
          inversionAttempts: 'dontInvert'
        });

        if (codigo?.data) {
          this.detener();
          this.scanned.emit(codigo.data);
          return;
        }
      }
    }

    this.frameId = requestAnimationFrame(this.escanear);
  };

  /** Detiene el bucle de escaneo y libera la cámara (apaga el led). */
  private detener() {
    this.detenido = true;
    if (this.frameId !== null) {
      cancelAnimationFrame(this.frameId);
      this.frameId = null;
    }
    this.stream?.getTracks().forEach(t => t.stop());
    this.stream = null;
  }

  /** Libera la cámara al destruir el componente. */
  ngOnDestroy() {
    this.detener();
  }
}
