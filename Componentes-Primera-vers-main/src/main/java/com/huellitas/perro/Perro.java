package com.huellitas.perro;
import com.huellitas.casa.Casa;
import jakarta.persistence.*;
import java.time.LocalDate;
import java.time.ZonedDateTime;
import java.math.BigDecimal;

/**
 * Mascota (perro) registrada por el propietario de una {@link Casa}, con sus
 * datos básicos (raza, fecha de nacimiento, peso) y foto de perfil.
 */
@Entity
@Table(name = "perro")
public class Perro {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "casa_id")
    private Casa casa;
    private String nombre;
    private String raza;
    @Column(name = "fecha_nacimiento") private LocalDate fechaNacimiento;
    private BigDecimal peso;
    @Column(name = "foto_url") private String fotoUrl;
    @Column(name = "created_at") private ZonedDateTime createdAt;
    @Column(name = "updated_at") private ZonedDateTime updatedAt;
    @Column(name = "deleted_at") private ZonedDateTime deletedAt;
}