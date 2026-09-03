package com.huellitas.alerta;
import com.huellitas.casa.Casa;
import com.huellitas.perro.Perro;
import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import java.time.ZonedDateTime;

/**
 * Aviso generado por el sistema ante una condición relevante de una
 * {@link Perro mascota} o su entorno (por ejemplo, un sensor fuera de
 * rango), asociado a la {@link Casa} correspondiente y con un nivel de
 * {@link SeveridadAlerta severidad}.
 */
@Entity
@Table(name = "alerta")
public class Alerta {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "casa_id")
    private Casa casa;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "perro_id")
    private Perro perro;
    private String tipo;
    private String mensaje;
    
    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(columnDefinition = "severidad_alerta")
    private SeveridadAlerta severidad;
    
    private Boolean leida;
    private ZonedDateTime ts;
}