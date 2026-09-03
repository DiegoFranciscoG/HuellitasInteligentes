import { Injectable, signal } from '@angular/core';

export interface WelcomeMessage {
  text: string;
  icon: string;
}

/**
 * Muestra, una vez por sesión, un mensaje de bienvenida con un consejo de
 * cuidado de mascotas, elegido de forma determinista según el día del año.
 */
@Injectable({
  providedIn: 'root'
})
export class WelcomeToastService {
  /** Indica si el toast de bienvenida está actualmente visible. */
  public isVisible = signal(false);
  /** Mensaje de bienvenida actualmente mostrado, o `null` si no hay ninguno activo. */
  public currentMessage = signal<WelcomeMessage | null>(null);

  private messages: WelcomeMessage[] = [
    { text: "¡El agua fresca siempre es clave para un perrito feliz!", icon: "Droplets" },
    { text: "Un buen paseo matutino evita destrozos vespertinos.", icon: "Sun" },
    { text: "Premia siempre los buenos comportamientos de tu peludo.", icon: "Bone" },
    { text: "Revisar sus patitas después de pasear es un súper hábito.", icon: "Footprints" },
    { text: "¡Mucho amor y paciencia hacen al mejor compañero!", icon: "Heart" }
  ];

  /**
   * Muestra el mensaje de bienvenida correspondiente al día actual, una
   * única vez por sesión de navegador (controlado vía `sessionStorage`), y
   * lo oculta automáticamente a los 20 segundos.
   */
  showWelcome() {
    // Si ya mostró, no repetimos (opcional: o revisar localStorage)
    if (sessionStorage.getItem('welcome_shown')) return;
    sessionStorage.setItem('welcome_shown', 'true');

    const now = new Date();
    const start = new Date(now.getFullYear(), 0, 0);
    const diff = (now.getTime() - start.getTime()) + ((start.getTimezoneOffset() - now.getTimezoneOffset()) * 60 * 1000);
    const dayOfYear = Math.floor(diff / (1000 * 60 * 60 * 24));
    
    // Semilla basada en el día actual
    const index = dayOfYear % this.messages.length;
    const todayMsg = this.messages[index];
    
    this.currentMessage.set(todayMsg);
    this.isVisible.set(true);

    setTimeout(() => {
      this.isVisible.set(false);
    }, 20000); // 20 segundos
  }

  /** Oculta el toast de bienvenida inmediatamente. */
  hide() {
    this.isVisible.set(false);
  }
}
