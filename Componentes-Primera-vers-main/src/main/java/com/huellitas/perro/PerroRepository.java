package com.huellitas.perro;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.time.LocalDate;
import java.math.BigDecimal;

/**
 * Acceso a datos de {@link Perro}, delegando el alta, edición y baja en funciones almacenadas de PostgreSQL.
 */
public interface PerroRepository extends JpaRepository<Perro, Long> {

    /**
     * Registra una nueva mascota.
     *
     * @param casaId identificador de la vivienda a la que pertenece.
     * @param nombre nombre de la mascota.
     * @param raza raza de la mascota.
     * @param fechaNacimiento fecha de nacimiento de la mascota.
     * @param peso peso de la mascota.
     * @param fotoUrl URL de la foto de perfil, si se subió una.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_registrar_perro(:casaId, :nombre, :raza, :fechaNacimiento, :peso, :fotoUrl)", nativeQuery = true)
    String registrarPerro(@Param("casaId") Long casaId, @Param("nombre") String nombre, @Param("raza") String raza, @Param("fechaNacimiento") LocalDate fechaNacimiento, @Param("peso") BigDecimal peso, @Param("fotoUrl") String fotoUrl);

    /**
     * Edita los datos de una mascota existente.
     *
     * @param perroId identificador de la mascota.
     * @param nombre nuevo nombre de la mascota.
     * @param raza nueva raza de la mascota.
     * @param peso nuevo peso de la mascota.
     * @param fotoUrl nueva URL de la foto de perfil.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_editar_perro(:perroId, :nombre, :raza, :peso, :fotoUrl)", nativeQuery = true)
    String editarPerro(@Param("perroId") Long perroId, @Param("nombre") String nombre, @Param("raza") String raza, @Param("peso") BigDecimal peso, @Param("fotoUrl") String fotoUrl);

    /**
     * Da de baja (borrado lógico) a una mascota.
     *
     * @param perroId identificador de la mascota.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_eliminar_perro(:perroId)", nativeQuery = true)
    String eliminarPerro(@Param("perroId") Long perroId);
}