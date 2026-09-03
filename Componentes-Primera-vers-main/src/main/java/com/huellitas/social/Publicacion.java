package com.huellitas.social;
import com.huellitas.auth.Usuario;
import jakarta.persistence.*;
import java.time.ZonedDateTime;

/**
 * Publicación de un {@link Usuario} en el muro social de la comunidad, con texto e imagen opcional.
 */
@Entity
@Table(name = "publicacion")
public class Publicacion {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "usuario_id")
    private Usuario usuario;
    private String contenido;
    @Column(name = "imagen_url") private String imagenUrl;
    @Column(name = "created_at") private ZonedDateTime createdAt;
}