package com.huellitas.alerta;
import com.huellitas.auth.Usuario;
import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import java.time.ZonedDateTime;

/**
 * Notificación dirigida a un {@link Usuario} (avisos del sistema,
 * respuestas a reportes, cambios de plan, etc.), con su canal de entrega y estado de envío.
 */
@Entity
@Table(name = "notificacion")
public class Notificacion {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "usuario_id")
    private Usuario usuario;
    
    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(columnDefinition = "canal_notificacion")
    private CanalNotificacion canal;
    
    private String contenido;
    
    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(columnDefinition = "estado_notificacion")
    private EstadoNotificacion estado;
    
    @Column(name = "enviado_at") private ZonedDateTime enviadoAt;
}