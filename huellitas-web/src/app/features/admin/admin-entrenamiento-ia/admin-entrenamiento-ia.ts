import { Component, inject, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { LucideAngularModule, Bot, FileText, Link, Plus, Upload, CheckCircle, Eye, X } from 'lucide-angular';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../../../environments/environment';
import { AuthService } from '../../../core/services/auth.service';

@Component({
  selector: 'app-admin-entrenamiento-ia',
  standalone: true,
  imports: [CommonModule, FormsModule, LucideAngularModule],
  templateUrl: './admin-entrenamiento-ia.html'
})
/**
 * Panel de administración para alimentar el conocimiento del asistente de
 * IA: registrar fuentes confiables (URLs) y subir documentos PDF que
 * nutren el sistema RAG de recomendaciones.
 */
export class AdminEntrenamientoIaComponent implements OnInit {
  private http = inject(HttpClient);
  private authService = inject(AuthService);

  user = this.authService.currentUser;

  Bot = Bot;
  FileText = FileText;
  Link = Link;
  Plus = Plus;
  Upload = Upload;
  CheckCircle = CheckCircle;
  Eye = Eye;
  X = X;

  urlFuente = signal('');
  descripcionFuente = signal('');
  subiendoPdf = signal(false);
  mensajeFeedback = signal('');

  fuentes = signal<any[]>([]);
  documentosRag = signal<any[]>([]);

  /** Documento cuyo contenido indexado se está mostrando en el modal de vista previa (null si el modal está cerrado). */
  documentoEnVista = signal<{ fuente: string; fragmentos: string[] } | null>(null);
  cargandoContenido = signal(false);

  ngOnInit() {
    this.cargarFuentes();
    this.cargarDocumentosRag();
  }

  /** Obtiene las fuentes confiables (URLs) registradas para el conocimiento de la IA. */
  cargarFuentes() {
    this.http.get<any[]>(`${environment.apiUrl}/admin/rag/fuentes`).subscribe({
      next: (res) => this.fuentes.set(res || []),
      error: () => {}
    });
  }

  /** Obtiene los documentos PDF ya registrados en la base de conocimiento RAG. */
  cargarDocumentosRag() {
    this.http.get<any[]>(`${environment.apiUrl}/admin/rag/documentos`).subscribe({
      next: (res) => this.documentosRag.set(res || []),
      error: () => {}
    });
  }

  /** Abre el modal de vista previa con el contenido real que quedó indexado para un documento. */
  verContenido(nombreArchivo: string) {
    this.cargandoContenido.set(true);
    this.documentoEnVista.set({ fuente: nombreArchivo, fragmentos: [] });
    this.http.get<any>(`${environment.apiUrl}/admin/rag/documentos/contenido`, { params: { fuente: nombreArchivo } }).subscribe({
      next: (res) => {
        this.cargandoContenido.set(false);
        this.documentoEnVista.set({ fuente: nombreArchivo, fragmentos: res?.fragmentos || [] });
      },
      error: () => {
        this.cargandoContenido.set(false);
        this.documentoEnVista.set({ fuente: nombreArchivo, fragmentos: [] });
      }
    });
  }

  /** Cierra el modal de vista previa de contenido. */
  cerrarContenido() {
    this.documentoEnVista.set(null);
  }

  /** Registra una nueva URL como fuente confiable de conocimiento para la IA. */
  agregarFuente() {
    if (!this.urlFuente().trim()) return;

    const payload = {
      adminId: this.user()?.id ?? null,
      url: this.urlFuente().trim(),
      descripcion: this.descripcionFuente().trim()
    };

    this.http.post<any>(`${environment.apiUrl}/admin/rag/fuentes`, payload).subscribe({
      next: (res) => {
        // El backend ahora ingiere la URL de verdad al guardarla (antes solo
        // quedaba anotada, nunca se leía) — mostramos su mensaje real, que
        // incluye cuántos fragmentos reales se agregaron.
        this.mensajeFeedback.set(res?.message || 'Fuente confiable agregada al conocimiento de la IA.');
        this.urlFuente.set('');
        this.descripcionFuente.set('');
        this.cargarFuentes();
        setTimeout(() => this.mensajeFeedback.set(''), 6000);
      },
      error: (err) => {
        this.mensajeFeedback.set('Error: ' + (err.message || 'No se pudo agregar la fuente.'));
        setTimeout(() => this.mensajeFeedback.set(''), 6000);
      }
    });
  }

  /**
   * Sube el PDF elegido para incorporarlo a la base de conocimiento RAG de la IA.
   * @param event Evento `change` del input de tipo archivo.
   */
  onPdfSelected(event: any) {
    const file = event.target.files[0];
    if (!file) return;

    this.subiendoPdf.set(true);
    const formData = new FormData();
    formData.append('file', file);
    if (this.user()?.id) formData.append('adminId', String(this.user()!.id));

    this.http.post<any>(`${environment.apiUrl}/admin/rag/subir-pdf`, formData).subscribe({
      next: (res) => {
        // Igual que con las fuentes: el backend ahora sí lee el PDF de
        // verdad (antes solo guardaba el nombre del archivo con un "15"
        // inventado). Mostramos su mensaje real con el conteo verdadero.
        this.subiendoPdf.set(false);
        this.mensajeFeedback.set(res?.message || `PDF "${file.name}" subido y registrado con éxito.`);
        this.cargarDocumentosRag();
        setTimeout(() => this.mensajeFeedback.set(''), 6000);
      },
      error: (err) => {
        this.subiendoPdf.set(false);
        this.mensajeFeedback.set('Error: ' + (err.message || `No se pudo subir "${file.name}".`));
        setTimeout(() => this.mensajeFeedback.set(''), 6000);
      }
    });
  }
}
