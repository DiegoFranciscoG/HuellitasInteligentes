import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { environment } from '../../../environments/environment';

@Component({
  selector: 'app-descargar',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './descargar.html',
})
/**
 * Página pública de descarga de la app Android. Es a donde llevan tanto el
 * botón "Descarga la App" de la landing como el enlace que trae un aviso de
 * versión nueva por notificación — un solo lugar para el archivo, en vez de
 * repetir la URL del .apk en varios sitios del código.
 */
export class Descargar {
  /** URL del .apk publicado (`environment.apkDownloadUrl`); vacía si aún no se ha subido ninguna versión. */
  apkUrl = environment.apkDownloadUrl;
}
