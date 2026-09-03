package com.huellitas.admin;
import jakarta.persistence.*;
import java.time.ZonedDateTime;
import java.math.BigDecimal;

/**
 * Plan de suscripción ofrecido a los propietarios, con su precio mensual y
 * los límites de dispositivos y almacenamiento que otorga.
 */
@Entity
@Table(name = "plan")
public class Plan {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private String nombre;
    @Column(name = "precio_mensual") private BigDecimal precioMensual;
    @Column(name = "limite_dispositivos") private Integer limiteDispositivos;
    @Column(name = "limite_almacenamiento_mb") private Integer limiteAlmacenamientoMb;
    private String descripcion;
    private Boolean activo;
    @Column(name = "created_at") private ZonedDateTime createdAt;
    @Column(name = "updated_at") private ZonedDateTime updatedAt;
}