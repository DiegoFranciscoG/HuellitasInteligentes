import { Pipe, PipeTransform } from '@angular/core';
import { environment } from '../../../environments/environment';

@Pipe({
  name: 'mediaUrl',
  standalone: true
})
/** Convierte una URL relativa de archivo multimedia devuelta por el backend en una URL absoluta usable en templates. */
export class MediaUrlPipe implements PipeTransform {
  /**
   * @param value URL relativa o absoluta del recurso.
   * @returns URL absoluta lista para usar en `src`/`href`, o cadena vacía si no hay valor.
   */
  transform(value: string | null | undefined): string {
    if (!value) return '';
    if (value.startsWith('http') || value.startsWith('data:image') || value.startsWith('blob:')) {
      return value;
    }
    const baseUrl = environment.apiUrl.replace('/api/huellitas', '');
    return baseUrl + (value.startsWith('/') ? value : '/' + value);
  }
}
