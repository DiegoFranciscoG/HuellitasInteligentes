import { Component, signal, OnInit, OnDestroy, AfterViewInit, HostListener, ElementRef, ViewChild, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../environments/environment';
import { MediaUrlPipe } from '../../shared/pipes/media-url.pipe';

@Component({
  selector: 'app-landing',
  standalone: true,
  imports: [RouterLink, CommonModule, MediaUrlPipe],
  templateUrl: './landing.html',
})
/**
 * Página pública de aterrizaje (marketing) de Huellitas Inteligentes:
 * rota las características destacadas, anima contadores estadísticos al
 * hacer scroll y controla el estilo de la barra de navegación fija.
 */
export class Landing implements OnInit, AfterViewInit, OnDestroy {
  private http = inject(HttpClient);

  isScrolled = signal(false);
  activeSection = signal('inicio');

  // Animated counters. Los valores finales (`statsTarget`) ya no son fijos:
  // se piden al backend (fn_estadisticas_publicas) y son los conteos reales
  // del sistema — antes decían "500+", "2400+", etc. sin relación con los
  // datos reales.
  counterCasas = signal(0);
  counterDisp = signal(0);
  counterUptime = signal(0);
  counterPets = signal(0);
  countersStarted = false;
  private statsTarget = { hogares: 0, dispositivos: 0, mascotas: 0, actividad: 100 };

  // Antes los contadores solo arrancaban si `window.scrollY` pasaba de 400px,
  // sin importar si la sección de estadísticas ya estaba a la vista o no. En
  // pantallas donde esa sección aparece antes de esos 400px de scroll (o si
  // el usuario nunca hace scroll, como al volver aquí desde el botón "X" del
  // login), los contadores se quedaban en "0+" para siempre. Un
  // IntersectionObserver sobre la sección misma dispara la animación en el
  // momento correcto sin importar el tamaño de pantalla ni cómo se llegó aquí.
  @ViewChild('statsSection') statsSection?: ElementRef<HTMLElement>;
  private statsObserver?: IntersectionObserver;

  // Current feature index for hero display
  currentFeatureIndex = signal(0);
  private featureInterval: any;

  features = [
    { icon: 'thermostat', label: 'Temperatura', value: '22.5°C', status: 'Óptimo', statusClass: 'text-[var(--primary)]' },
    { icon: 'water_drop', label: 'Agua', value: '78%', status: 'Normal', statusClass: 'text-[var(--primary)]' },
    { icon: 'restaurant', label: 'Alimento', value: '65%', status: 'Suficiente', statusClass: 'text-[var(--primary)]' },
  ];

  /** Arranca la rotación automática de la característica destacada en el hero, cada 2.8s, y pide las estadísticas reales al backend. */
  ngOnInit() {
    this.featureInterval = setInterval(() => {
      this.currentFeatureIndex.update(i => (i + 1) % this.features.length);
    }, 2800);

    this.http.get<{ hogares: number; dispositivos: number; mascotas: number; actividad_pct: number }>(
      `${environment.apiUrl}/casa/estadisticas-publicas`
    ).subscribe({
      next: (data) => {
        this.statsTarget = {
          hogares: data.hogares ?? 0,
          dispositivos: data.dispositivos ?? 0,
          mascotas: data.mascotas ?? 0,
          actividad: data.actividad_pct ?? 100,
        };
        // Si la sección de estadísticas ya está visible y esperando datos
        // (llegaron tarde), animamos ahora que ya tenemos los valores reales.
        if (this.countersStarted) this.animateCounters();
      },
      error: () => {
        // Sin datos reales disponibles, no inventamos cifras: se quedan en 0.
      },
    });

    this.http.get<{ nombre: string; foto_url: string | null; contenido: string }[]>(
      `${environment.apiUrl}/social/testimonios-publicos`
    ).subscribe({
      next: (data) => {
        this.testimonials.set(data ?? []);
        this.startTestimonialRotation();
      },
      error: () => this.testimonials.set([]),
    });
  }

  /** Observa la sección de estadísticas y arranca los contadores apenas entra en la pantalla, sin depender de cuánto haya hecho scroll la ventana. */
  ngAfterViewInit() {
    const el = this.statsSection?.nativeElement;
    if (!el) return;
    this.statsObserver = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting && !this.countersStarted) {
        this.countersStarted = true;
        this.animateCounters();
        this.statsObserver?.disconnect();
      }
    }, { threshold: 0.3 });
    this.statsObserver.observe(el);
  }

  /** Detiene la rotación de características y el observer al destruir el componente. */
  ngOnDestroy() {
    if (this.featureInterval) clearInterval(this.featureInterval);
    if (this.testimonialInterval) clearInterval(this.testimonialInterval);
    this.statsObserver?.disconnect();
  }

  /** Actualiza el estilo de la barra de navegación al hacer scroll. */
  @HostListener('window:scroll')
  onScroll() {
    this.isScrolled.set(window.scrollY > 60);
  }

  /** Anima los contadores estadísticos (casas, dispositivos, uptime, mascotas) de 0 a su valor real, ya traído del backend. */
  animateCounters() {
    this.animateCounter(this.counterCasas, 0, this.statsTarget.hogares, 1800);
    this.animateCounter(this.counterDisp, 0, this.statsTarget.dispositivos, 2000);
    this.animateCounter(this.counterUptime, 0, this.statsTarget.actividad, 1600);
    this.animateCounter(this.counterPets, 0, this.statsTarget.mascotas, 2200);
  }

  devices = [
    { icon: 'thermostat', name: 'Sensor DHT11', desc: 'Temperatura y humedad' },
    { icon: 'water_drop', name: 'Nivel de Agua', desc: 'Sensor ultrasónico' },
    { icon: 'smart_toy', name: 'Dispensador', desc: 'Motor alimentador auto' },
    { icon: 'plumbing', name: 'Bomba de Agua', desc: 'Control inteligente' },
  ];

  // Testimonios reales: publicaciones de la Comunidad que su propio autor
  // etiquetó con #testimonio, con su nombre y foto reales — antes eran 3
  // personas inventadas ("María Rodríguez", "Carlos Mendoza"...) que no
  // existen en el sistema. El backend ya entrega como mucho uno por usuario
  // (el más reciente de cada quien), así que aquí solo hace falta rotarlos.
  testimonials = signal<{ nombre: string; foto_url: string | null; contenido: string }[]>([]);
  currentTestimonialIndex = signal(0);
  testimonialVisible = signal(true);
  private testimonialInterval: any;

  /** El testimonio que se muestra ahora mismo en el carrusel. */
  get currentTestimonial() {
    const list = this.testimonials();
    return list.length > 0 ? list[this.currentTestimonialIndex() % list.length] : null;
  }

  /**
   * Arranca la rotación del carrusel de testimonios: cada [intervalMs] hace
   * un fundido de salida, avanza al siguiente y hace un fundido de entrada.
   * Se reinicia cada vez que llegan datos nuevos, para no dejar dos
   * intervalos corriendo a la vez.
   */
  private startTestimonialRotation(intervalMs = 5000) {
    if (this.testimonialInterval) clearInterval(this.testimonialInterval);
    if (this.testimonials().length < 2) return;
    this.testimonialInterval = setInterval(() => {
      this.testimonialVisible.set(false);
      setTimeout(() => {
        this.currentTestimonialIndex.update(i => (i + 1) % this.testimonials().length);
        this.testimonialVisible.set(true);
      }, 300);
    }, intervalMs);
  }

  /** Característica actualmente mostrada en la rotación del hero. */
  get currentFeature() {
    return this.features[this.currentFeatureIndex()];
  }

  /**
   * Anima un contador numérico (signal) desde un valor inicial hasta uno
   * final con una curva de desaceleración (ease-out cúbico).
   * @param sig Signal numérica a animar.
   * @param from Valor inicial.
   * @param to Valor final.
   * @param duration Duración de la animación, en milisegundos.
   */
  animateCounter(sig: any, from: number, to: number, duration: number) {
    const start = Date.now();
    const frame = () => {
      const elapsed = Date.now() - start;
      const progress = Math.min(elapsed / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3);
      sig.set(Math.round(from + (to - from) * eased));
      if (progress < 1) requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }

  /**
   * Hace scroll suave hasta la sección indicada de la página.
   * @param sectionId Id del elemento destino.
   */
  scrollTo(sectionId: string) {
    document.getElementById(sectionId)?.scrollIntoView({ behavior: 'smooth' });
  }
}
