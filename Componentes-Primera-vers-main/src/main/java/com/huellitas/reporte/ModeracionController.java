package com.huellitas.reporte;

import com.huellitas.config.AuthContext;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * Permite a los usuarios denunciar contenido o comportamiento de otro
 * usuario en la comunidad, y expone a los administradores el listado de
 * denuncias pendientes de moderación.
 */
@RestController
@RequestMapping("/api/huellitas/moderacion")
public class ModeracionController {

    private final ReporteModeracionRepository reporteRepo;
    private final AuthContext authContext;

    public ModeracionController(ReporteModeracionRepository reporteRepo, AuthContext authContext) {
        this.reporteRepo = reporteRepo;
        this.authContext = authContext;
    }

    /** Datos de una denuncia de contenido o comportamiento presentada por un usuario. */
    public record CrearReporteRequest(Long casaId, Long reportadorId, Long reportadoId, String motivo) {}

    /**
     * Registra una denuncia de un usuario contra otro (por ejemplo, sobre
     * una publicación o comentario), que quedará pendiente de moderación.
     *
     * @param request datos de la denuncia: casa, denunciante, denunciado y motivo.
     * @return el resultado del registro en formato JSON.
     */
    @PostMapping(value = "/reportar", produces = "application/json")
    public ResponseEntity<String> reportar(@RequestBody CrearReporteRequest request) {
        String jsonResult = reporteRepo.reportarModeracion(
            request.casaId(),
            authContext.usuarioIdActual(),
            request.reportadoId(),
            request.motivo()
        );
        return ResponseEntity.ok(jsonResult);
    }

    /**
     * Lista las denuncias de moderación, con filtro opcional por estado, para revisión administrativa.
     *
     * @param estado estado de la denuncia a filtrar (opcional).
     * @return un JSON (como texto) con la lista de denuncias.
     */
    @GetMapping(value = "/admin/reportes", produces = "application/json")
    public ResponseEntity<String> listarReportesAdmin(@RequestParam(required = false) String estado) {
        return ResponseEntity.ok(reporteRepo.listarReportesAdmin(estado));
    }
}
