package com.huellitas.reporte;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

/**
 * Acceso a datos usado por el flujo de denuncias de moderación de la
 * comunidad, delegado en funciones almacenadas de PostgreSQL.
 */
@Repository
public interface ReporteModeracionRepository extends JpaRepository<Reporte, Long> {

    /**
     * Registra una denuncia de un usuario contra otro.
     *
     * @param casaId identificador de la vivienda del denunciante.
     * @param reportadorId identificador del usuario que denuncia.
     * @param reportadoId identificador del usuario denunciado.
     * @param motivo motivo de la denuncia.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_reportar_moderacion(:casaId, :reportadorId, :reportadoId, :motivo)", nativeQuery = true)
    String reportarModeracion(
        @Param("casaId") Long casaId,
        @Param("reportadorId") Long reportadorId,
        @Param("reportadoId") Long reportadoId,
        @Param("motivo") String motivo
    );

    /**
     * Lista las denuncias de moderación, con filtro opcional por estado.
     *
     * @param estado estado de la denuncia a filtrar (puede ser {@code null}).
     * @return un JSON (como texto) con la lista de denuncias.
     */
    @Query(value = "SELECT fn_listar_reportes_admin(:estado)", nativeQuery = true)
    String listarReportesAdmin(@Param("estado") String estado);
}
