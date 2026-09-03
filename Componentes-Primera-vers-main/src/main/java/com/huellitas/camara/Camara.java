package com.huellitas.camara;

import com.huellitas.casa.Casa;
import jakarta.persistence.*;
import java.time.ZonedDateTime;

/**
 * Cámara IP vinculada a una vivienda que transmite video en vivo (por
 * WebRTC) y que opcionalmente vigila a una mascota concreta.
 */
@Entity
@Table(name = "camara")
public class Camara {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(name = "casa_id", nullable = false)
    private Long casaId;
    
    @Column(nullable = false, length = 100)
    private String nombre;
    
    @Column(name = "url_stream", nullable = false, columnDefinition = "TEXT")
    private String urlStream;
    
    @Column(nullable = false)
    private Boolean activo = true;
    
    @Column(nullable = false)
    private Boolean conectada = false;

    /** Mascota que vigila esta cámara. Null si aún no se le asignó ninguna. */
    @Column(name = "perro_id")
    private Long perroId;

    @Column(name = "created_at", insertable = false, updatable = false)
    private ZonedDateTime createdAt;

    // Getters y Setters
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getCasaId() { return casaId; }
    public void setCasaId(Long casaId) { this.casaId = casaId; }

    public String getNombre() { return nombre; }
    public void setNombre(String nombre) { this.nombre = nombre; }

    public String getUrlStream() { return urlStream; }
    public void setUrlStream(String urlStream) { this.urlStream = urlStream; }

    public Boolean getActivo() { return activo; }
    public void setActivo(Boolean activo) { this.activo = activo; }

    public Boolean getConectada() { return conectada; }
    public void setConectada(Boolean conectada) { this.conectada = conectada; }

    public Long getPerroId() { return perroId; }
    public void setPerroId(Long perroId) { this.perroId = perroId; }

    public ZonedDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(ZonedDateTime createdAt) { this.createdAt = createdAt; }
}
