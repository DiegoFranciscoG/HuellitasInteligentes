package com.huellitas.social;
import com.huellitas.auth.Usuario;
import jakarta.persistence.*;
import java.time.ZonedDateTime;

/**
 * Mensaje directo entre dos usuarios de la comunidad, con su estado de lectura.
 */
@Entity
@Table(name = "mensaje")
public class Mensaje {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "emisor_id")
    private Usuario emisor;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "receptor_id")
    private Usuario receptor;
    private String contenido;
    private Boolean leido;
    @Column(name = "created_at") private ZonedDateTime createdAt;
}