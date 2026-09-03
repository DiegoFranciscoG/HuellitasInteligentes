package com.huellitas.auth;
import com.huellitas.casa.Casa;
import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import java.time.ZonedDateTime;

/**
 * Representa a una persona registrada en el sistema (dueño de mascota,
 * miembro de una vivienda o administrador), con su rol, credenciales y la
 * {@link Casa} a la que pertenece.
 */
@Entity
@Table(name = "usuario")
public class Usuario {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private String email;
    @Column(name = "password_hash") private String passwordHash;
    private String nombre;
    
    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(columnDefinition = "rol_usuario")
    private RolUsuario rol;
    
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "casa_id")
    private Casa casa;
    
    private Boolean activo;
    @Column(name = "created_at") private ZonedDateTime createdAt;
    @Column(name = "updated_at") private ZonedDateTime updatedAt;
    @Column(name = "deleted_at") private ZonedDateTime deletedAt;
}