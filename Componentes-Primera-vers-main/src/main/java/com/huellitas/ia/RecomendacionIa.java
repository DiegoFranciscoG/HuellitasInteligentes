package com.huellitas.ia;
import com.huellitas.perro.Perro;
import jakarta.persistence.*;
import java.time.ZonedDateTime;
import java.math.BigDecimal;

/**
 * Recomendación generada por el asistente IA para una {@link Perro
 * mascota} (por ejemplo, sobre nutrición o cuidados), con su nivel de confianza.
 */
@Entity
@Table(name = "recomendacion_ia")
public class RecomendacionIa {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "perro_id")
    private Perro perro;
    private String tipo;
    private String contenido;
    private BigDecimal confianza;
    @Column(name = "created_at") private ZonedDateTime createdAt;
}