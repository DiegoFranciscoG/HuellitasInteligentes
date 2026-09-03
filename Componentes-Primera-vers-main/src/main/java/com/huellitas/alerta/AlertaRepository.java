package com.huellitas.alerta;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * Acceso a datos de {@link Alerta}, delegando la búsqueda filtrada y el
 * marcado de lectura en funciones almacenadas de PostgreSQL.
 */
public interface AlertaRepository extends JpaRepository<Alerta, Long> {

    /**
     * Busca alertas de una vivienda con filtros de severidad, estado de lectura y paginación.
     *
     * @param casaId identificador de la vivienda.
     * @param severidad severidad a filtrar (puede ser {@code null}).
     * @param soloNoLeidas si se deben devolver solo las alertas no leídas.
     * @param limite cantidad máxima de resultados.
     * @param offset cantidad de resultados a saltar.
     * @return un JSON (como texto) con las alertas encontradas.
     */
    @Query(value = "SELECT fn_buscar_alertas(:casaId, CAST(:severidad AS severidad_alerta), :soloNoLeidas, :limite, :offset)", nativeQuery = true)
    String buscarAlertas(@Param("casaId") Long casaId, @Param("severidad") String severidad, @Param("soloNoLeidas") Boolean soloNoLeidas, @Param("limite") Integer limite, @Param("offset") Integer offset);

    /**
     * Marca una alerta como leída.
     *
     * @param alertaId identificador de la alerta.
     */
    @Query(value = "SELECT fn_marcar_alerta_leida(:alertaId)", nativeQuery = true)
    void marcarAlertaLeida(@Param("alertaId") Long alertaId);
}