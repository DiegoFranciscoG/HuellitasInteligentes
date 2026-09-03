import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

/**
 * Gestiona las alertas generadas por los dispositivos IoT y el sistema
 * (por ejemplo, sensores fuera de rango o comportamientos anómalos de las
 * mascotas), permitiendo consultarlas y marcarlas como leídas.
 */
@Injectable({
  providedIn: 'root'
})
export class AlertaService {
  private http = inject(HttpClient);
  private apiUrl = `${environment.apiUrl}/alerta`;

  /**
   * Busca alertas, opcionalmente filtradas por casa y por estado de lectura.
   * Siempre pagina los primeros 50 resultados desde el offset 0.
   * @param casaId Identificador de la casa/vivienda a filtrar (opcional).
   * @param soloNoLeidas Si es `true`, solo devuelve alertas no leídas.
   */
  buscarAlertas(casaId?: number, soloNoLeidas: boolean = false): Observable<any[]> {
    let params = new HttpParams()
      .set('soloNoLeidas', soloNoLeidas.toString())
      .set('limite', '50')
      .set('offset', '0');
    if (casaId) {
      params = params.set('casaId', casaId.toString());
    }
    return this.http.get<any[]>(`${this.apiUrl}`, { params });
  }

  /**
   * Marca una alerta como leída.
   * @param id Identificador de la alerta.
   */
  marcarLeida(id: number): Observable<any> {
    return this.http.post(`${this.apiUrl}/${id}/marcar-leida`, {});
  }
}
