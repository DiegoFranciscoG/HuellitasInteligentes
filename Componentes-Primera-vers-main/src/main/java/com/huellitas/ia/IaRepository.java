package com.huellitas.ia;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * Acceso a datos de {@link RecomendacionIa}, con la búsqueda de recomendaciones delegada en una función de PostgreSQL.
 */
public interface IaRepository extends JpaRepository<RecomendacionIa, Long> {

    /**
     * Obtiene las recomendaciones generadas por IA para una mascota.
     *
     * @param perroId identificador de la mascota.
     * @param limite cantidad máxima de recomendaciones a devolver.
     * @return un JSON (como texto) con las recomendaciones.
     */
    @Query(value = "SELECT fn_recomendaciones_perro(:perroId, :limite)", nativeQuery = true)
    String recomendacionesPerro(@Param("perroId") Long perroId, @Param("limite") Integer limite);
}