package com.huellitas.auth;
import jakarta.persistence.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import java.time.ZonedDateTime;

/**
 * Vincula a un {@link Usuario} con un proveedor de autenticación externo
 * (Google, Facebook) y el identificador que ese proveedor le asigna,
 * permitiendo el inicio de sesión federado.
 */
@Entity
@Table(name = "usuario_proveedor")
public class UsuarioProveedor {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "usuario_id")
    private Usuario usuario;
    
    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(columnDefinition = "proveedor_auth")
    private ProveedorAuth proveedor;
    
    @Column(name = "proveedor_uid") private String proveedorUid;
    @Column(name = "created_at") private ZonedDateTime createdAt;
}