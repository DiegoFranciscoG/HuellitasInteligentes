package com.huellitas.social;
import com.huellitas.auth.Usuario;
import jakarta.persistence.*;
import java.time.ZonedDateTime;

/**
 * Comentario dejado por un {@link Usuario} en una {@link Publicacion} de la comunidad.
 */
@Entity
@Table(name = "comentario")
public class Comentario {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "publicacion_id")
    private Publicacion publicacion;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "usuario_id")
    private Usuario usuario;
    private String contenido;
    @Column(name = "created_at") private ZonedDateTime createdAt;
}