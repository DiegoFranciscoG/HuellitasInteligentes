package com.huellitas.casa;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * Acceso a datos de {@link Casa}, delegando el cálculo de los paneles de resumen en funciones almacenadas de PostgreSQL.
 */
public interface CasaRepository extends JpaRepository<Casa, Long> {

    /**
     * Calcula el dashboard general de una vivienda.
     *
     * @param casaId identificador de la vivienda.
     * @return un JSON (como texto) con el resumen de la vivienda.
     */
    @Query(value = "SELECT fn_dashboard_casa(:casaId)", nativeQuery = true)
    String dashboardCasa(@Param("casaId") Long casaId);

    /**
     * Calcula el panel de resumen de una zona de la vivienda.
     *
     * @param zonaId identificador de la zona.
     * @return un JSON (como texto) con el resumen de la zona.
     */
    @Query(value = "SELECT fn_panel_zona(:zonaId)", nativeQuery = true)
    String panelZona(@Param("zonaId") Long zonaId);

    /**
     * Calcula las estadísticas agregadas y públicas del sistema (hogares,
     * dispositivos, mascotas, % de actividad), para la barra de la landing.
     *
     * @return un JSON (como texto) con las estadísticas.
     */
    @Query(value = "SELECT fn_estadisticas_publicas()", nativeQuery = true)
    String estadisticasPublicas();
}