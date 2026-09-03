package com.huellitas.casa;
import com.huellitas.admin.Plan;
import com.huellitas.admin.SuscripcionEstado;
import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import java.time.LocalDate;
import java.time.ZonedDateTime;

/**
 * Suscripción vigente (o histórica) de una {@link Casa} a un {@link Plan},
 * con su vigencia y método de pago.
 */
@Entity
@Table(name = "suscripcion")
public class Suscripcion {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @OneToOne(fetch = FetchType.LAZY) @JoinColumn(name = "casa_id")
    private Casa casa;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "plan_id")
    private Plan plan;
    
    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(columnDefinition = "suscripcion_estado")
    private SuscripcionEstado estado;
    
    @Column(name = "fecha_inicio") private LocalDate fechaInicio;
    @Column(name = "fecha_fin") private LocalDate fechaFin;
    @Column(name = "metodo_pago") private String metodoPago;
    @Column(name = "created_at") private ZonedDateTime createdAt;
    @Column(name = "updated_at") private ZonedDateTime updatedAt;
}