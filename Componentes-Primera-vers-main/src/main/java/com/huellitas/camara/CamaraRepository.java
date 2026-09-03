package com.huellitas.camara;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * Acceso a datos de {@link Camara}, con búsquedas por vivienda y por URL de streaming.
 */
@Repository
public interface CamaraRepository extends JpaRepository<Camara, Long> {
    List<Camara> findByCasaId(Long casaId);
    List<Camara> findByCasaIdAndActivoTrue(Long casaId);
    List<Camara> findByUrlStream(String urlStream);
}
