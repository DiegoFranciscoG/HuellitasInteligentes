package com.huellitas.casa;
import com.huellitas.auth.Usuario;
import jakarta.persistence.*;
import java.time.ZonedDateTime;

/**
 * Vivienda registrada por un {@link Usuario} propietario, unidad organizativa
 * a la que se asocian sus mascotas, dispositivos IoT, cámaras y miembros con acceso compartido.
 */
@Entity
@Table(name = "casa")
public class Casa {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "propietario_id")
    private Usuario propietario;
    private String nombre;
    private String direccion;
    /** Código único que identifica la vivienda ante los dispositivos IoT (ESP32). */
    @Column(name = "codigo_vinculacion")
    private String codigoVinculacion;
    @Column(name = "created_at") private ZonedDateTime createdAt;
    @Column(name = "updated_at") private ZonedDateTime updatedAt;
    @Column(name = "deleted_at") private ZonedDateTime deletedAt;

    public Long getId() { return id; }
    public String getNombre() { return nombre; }
    public String getCodigoVinculacion() { return codigoVinculacion; }
}