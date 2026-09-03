package com.huellitas.auth;
import jakarta.persistence.*;
import java.time.ZonedDateTime;

/**
 * Token de larga duración asociado a un {@link Usuario} que permite renovar
 * su sesión sin volver a solicitar credenciales, hasta que expire o sea revocado.
 */
@Entity
@Table(name = "refresh_token")
public class RefreshToken {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "usuario_id")
    private Usuario usuario;
    @Column(name = "token_hash") private String tokenHash;
    @Column(name = "expira_at") private ZonedDateTime expiraAt;
    private Boolean revocado;
    @Column(name = "created_at") private ZonedDateTime createdAt;
}