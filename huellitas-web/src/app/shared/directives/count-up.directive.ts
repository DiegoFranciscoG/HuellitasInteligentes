import { Directive, ElementRef, Input, OnChanges, SimpleChanges, Renderer2 } from '@angular/core';

@Directive({
  selector: '[appCountUp]',
  standalone: true
})
/** Anima el texto del elemento host contando desde 0 hasta `appCountUp`, usado para métricas numéricas destacadas. */
export class CountUpDirective implements OnChanges {
  /** Valor final al que debe llegar el contador. */
  @Input('appCountUp') endValue: number = 0;
  /** Duración de la animación, en milisegundos. */
  @Input() duration: number = 800; // ms

  constructor(private el: ElementRef, private renderer: Renderer2) {}

  /** Reinicia la animación de conteo cada vez que cambia el valor final. */
  ngOnChanges(changes: SimpleChanges): void {
    if (changes['endValue']) {
      this.animateCount();
    }
  }

  /** Anima el `textContent` del elemento host de 0 a `endValue` con una curva de desaceleración. */
  private animateCount(): void {
    const startValue = 0;
    const startTime = performance.now();
    const endValue = this.endValue || 0;
    const duration = this.duration;

    const easeOutQuad = (t: number): number => t * (2 - t);

    const updateCounter = (currentTime: number) => {
      const elapsedTime = currentTime - startTime;
      const progress = Math.min(elapsedTime / duration, 1);
      const easedProgress = easeOutQuad(progress);

      const currentValue = Math.floor(easedProgress * (endValue - startValue) + startValue);
      this.renderer.setProperty(this.el.nativeElement, 'textContent', currentValue.toString());

      if (progress < 1) {
        requestAnimationFrame(updateCounter);
      } else {
        this.renderer.setProperty(this.el.nativeElement, 'textContent', endValue.toString());
      }
    };

    requestAnimationFrame(updateCounter);
  }
}
