package com.huellitas.reporte;
import com.huellitas.casa.Casa;
import jakarta.persistence.*;
import java.time.LocalDate;
import java.time.ZonedDateTime;

/**
 * Reporte generado (por ejemplo, en PDF) con la actividad de una
 * {@link Casa} durante un período determinado, con el enlace al archivo resultante.
 */
@Entity
@Table(name = "reporte")
public class Reporte {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY) @JoinColumn(name = "casa_id")
    private Casa casa;
    private String tipo;
    @Column(name = "periodo_inicio") private LocalDate periodoInicio;
    @Column(name = "periodo_fin") private LocalDate periodoFin;
    @Column(name = "url_pdf") private String urlPdf;
    @Column(name = "created_at") private ZonedDateTime createdAt;
}