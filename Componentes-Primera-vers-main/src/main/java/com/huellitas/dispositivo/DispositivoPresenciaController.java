package com.huellitas.dispositivo;

import com.huellitas.config.AuthContext;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Presencia de los dispositivos IoT: recibe el latido que manda el firmware,
 * responde qué aparatos están en línea ahora mismo y permite que una casa
 * reclame uno que todavía no tiene dueño.
 *
 * <p>El descubrimiento funciona al revés de como suele imaginarse: en vez de
 * que la aplicación salga a rastrear la red —cosa que el navegador no puede
 * hacer y que el backend tampoco, porque no vive en la casa del usuario—, es
 * el propio dispositivo el que sale hacia afuera y avisa que está encendido.
 * Al ser una conexión saliente, el router y el NAT dejan de estorbar.</p>
 *
 * <p>La exclusividad de un aparato por vivienda no se defiende aquí sino en la
 * base: {@code dispositivo.mac_address} es {@code UNIQUE} desde la primera
 * migración, de modo que una MAC no puede colgar de dos zonas —y por tanto de
 * dos casas— a la vez. Lo que aporta este controlador es el camino y el aviso:
 * mostrar el aparato ocupado sin filtrar de quién es, y responder 409 a quien
 * intente quedárselo.</p>
 */
@RestController
@RequestMapping("/api/huellitas/dispositivo")
public class DispositivoPresenciaController {

    private final JdbcTemplate jdbc;
    private final AuthContext authContext;

    /**
     * Cuántos segundos se considera "en línea" a un aparato desde su último
     * latido. Por defecto tres latidos de 10 segundos, para que un paquete
     * perdido no lo apague en pantalla.
     */
    @Value("${iot.presencia.ventana-segundos:30}")
    private int ventanaSegundos;

    public DispositivoPresenciaController(JdbcTemplate jdbc, AuthContext authContext) {
        this.jdbc = jdbc;
        this.authContext = authContext;
    }

    /** Cuerpo del latido, por si el firmware prefiere mandarlo como JSON en vez de cabecera. */
    public record LatidoDTO(String mac, String modelo, String ip) {}

    /** Petición para quedarse con un aparato libre. */
    public record ReclamarDTO(String mac, String nombre, String categoria) {}

    /**
     * Registra que un dispositivo sigue encendido. Anota el latido en
     * {@code dispositivo_presencia} —tenga dueño o no— y, si la MAC ya está
     * dada de alta, sella también su {@code ultima_conexion}.
     *
     * <p>Es público a propósito: lo llama el firmware del ESP32, que no tiene
     * sesión de usuario.</p>
     *
     * @param macCabecera dirección MAC en la cabecera {@code X-Device-Mac}, que es la vía preferida.
     * @param ipCabecera dirección local del aparato, opcional; la ESP32-CAM la manda para que se le pueda pedir la foto.
     * @param cuerpo alternativa por JSON cuando mandar cabeceras resulta incómodo desde el firmware.
     * @return {@code ok:true} y si la MAC ya estaba vinculada; nunca falla, para no dejar al firmware reintentando.
     */
    @PostMapping(value = "/latido", produces = "application/json")
    public ResponseEntity<Map<String, Object>> latido(
            @RequestHeader(value = "X-Device-Mac", required = false) String macCabecera,
            @RequestHeader(value = "X-Device-Ip", required = false) String ipCabecera,
            @RequestBody(required = false) LatidoDTO cuerpo) {

        String mac = primeroNoVacio(macCabecera, cuerpo != null ? cuerpo.mac() : null);
        if (mac == null) {
            return ResponseEntity.badRequest().body(Map.of(
                "ok", false,
                "error", "Falta la MAC del dispositivo (cabecera X-Device-Mac o campo mac)"));
        }

        String ip = primeroNoVacio(ipCabecera, cuerpo != null ? cuerpo.ip() : null);
        String modelo = cuerpo != null ? recortar(cuerpo.modelo(), 50) : null;

        // El registro de presencia acepta cualquier MAC. Es justamente lo que
        // permite que un aparato recién estrenado se pueda descubrir después.
        jdbc.update(
            "INSERT INTO dispositivo_presencia (mac_address, modelo, ip_local, ultimo_latido) " +
            "VALUES (?, ?, ?, now()) " +
            "ON CONFLICT (mac_address) DO UPDATE SET " +
            "  ultimo_latido = now(), " +
            "  modelo   = COALESCE(EXCLUDED.modelo, dispositivo_presencia.modelo), " +
            "  ip_local = COALESCE(EXCLUDED.ip_local, dispositivo_presencia.ip_local)",
            mac, modelo, recortar(ip, 45));

        int filas = jdbc.update(
            "UPDATE dispositivo SET ultima_conexion = now() WHERE mac_address = ? AND deleted_at IS NULL",
            mac);

        // Una MAC desconocida no es un error del firmware: puede ser un
        // aparato que todavía nadie vinculó. Se responde 200 avisando que no
        // está registrado, para que el dispositivo no entre en bucle de reintentos.
        return ResponseEntity.ok(Map.of(
            "ok", true,
            "registrado", filas > 0,
            "mac", mac));
    }

    /**
     * Lista lo que la vivienda del usuario puede ver ahora mismo: sus propios
     * aparatos en línea, los que están libres para reclamar y —solo como aviso,
     * sin revelar de quién son— los que ya pertenecen a otra casa.
     *
     * @param soloLibres si es {@code true} (por defecto), oculta los propios que ya tienen una cámara vinculada.
     * @return los dispositivos visibles, cada uno con su estado de propiedad.
     */
    @GetMapping(value = "/descubrir", produces = "application/json")
    public ResponseEntity<?> descubrir(@RequestParam(defaultValue = "true") boolean soloLibres) {

        Long casaId = authContext.casaIdActual();
        if (casaId == null) {
            return ResponseEntity.status(401).body(Map.of(
                "ok", false, "error", "Necesitas una vivienda para buscar dispositivos"));
        }

        List<Map<String, Object>> resultado = new ArrayList<>();

        // 1. Los que ya son de esta casa.
        String sqlPropios =
            "SELECT d.id, d.mac_address, d.modelo, d.categoria::text AS categoria, d.tipo::text AS tipo, " +
            "       d.ultima_conexion, p.ip_local, " +
            "       EXTRACT(EPOCH FROM (now() - d.ultima_conexion))::int AS hace_segundos, " +
            "       (c.id IS NOT NULL) AS ya_vinculado, c.id AS camara_id " +
            "FROM dispositivo d " +
            "JOIN zona z ON z.id = d.zona_id " +
            "LEFT JOIN camara c ON c.dispositivo_id = d.id AND c.activo = true " +
            "LEFT JOIN dispositivo_presencia p ON p.mac_address = d.mac_address " +
            "WHERE z.casa_id = ? " +
            "  AND d.deleted_at IS NULL " +
            "  AND d.ultima_conexion IS NOT NULL " +
            "  AND d.ultima_conexion > now() - make_interval(secs => ?) " +
            (soloLibres ? "  AND c.id IS NULL " : "") +
            "ORDER BY d.ultima_conexion DESC";

        for (Map<String, Object> fila : jdbc.queryForList(sqlPropios, casaId, (double) ventanaSegundos)) {
            Map<String, Object> item = new java.util.LinkedHashMap<>(fila);
            item.put("propiedad", "MIO");
            item.put("reclamable", false);
            resultado.add(item);
        }

        // 2. Los que laten pero todavía no son de nadie: se pueden reclamar.
        String sqlLibres =
            "SELECT p.mac_address, p.modelo, p.ip_local, p.ultimo_latido AS ultima_conexion, " +
            "       EXTRACT(EPOCH FROM (now() - p.ultimo_latido))::int AS hace_segundos " +
            "FROM dispositivo_presencia p " +
            "WHERE p.ultimo_latido > now() - make_interval(secs => ?) " +
            "  AND NOT EXISTS (SELECT 1 FROM dispositivo d " +
            "                  WHERE d.mac_address = p.mac_address AND d.deleted_at IS NULL) " +
            "ORDER BY p.ultimo_latido DESC";

        for (Map<String, Object> fila : jdbc.queryForList(sqlLibres, (double) ventanaSegundos)) {
            Map<String, Object> item = new java.util.LinkedHashMap<>(fila);
            item.put("propiedad", "LIBRE");
            item.put("reclamable", true);
            item.put("ya_vinculado", false);
            resultado.add(item);
        }

        // 3. Los de otra casa. Se muestran para explicar por qué no aparecen
        //    como disponibles, pero sin filtrar un solo dato de esa vivienda.
        String sqlAjenos =
            "SELECT p.mac_address, " +
            "       EXTRACT(EPOCH FROM (now() - p.ultimo_latido))::int AS hace_segundos " +
            "FROM dispositivo_presencia p " +
            "JOIN dispositivo d ON d.mac_address = p.mac_address AND d.deleted_at IS NULL " +
            "JOIN zona z ON z.id = d.zona_id " +
            "WHERE p.ultimo_latido > now() - make_interval(secs => ?) " +
            "  AND z.casa_id <> ? " +
            "ORDER BY p.ultimo_latido DESC";

        for (Map<String, Object> fila : jdbc.queryForList(sqlAjenos, (double) ventanaSegundos, casaId)) {
            Map<String, Object> item = new java.util.LinkedHashMap<>(fila);
            item.put("propiedad", "OCUPADO");
            item.put("reclamable", false);
            item.put("ya_vinculado", true);
            item.put("modelo", null);
            resultado.add(item);
        }

        return ResponseEntity.ok(Map.of(
            "ok", true,
            "ventanaSegundos", ventanaSegundos,
            "dispositivos", resultado));
    }

    /**
     * Da de alta en esta vivienda un aparato que está latiendo y no tiene dueño.
     *
     * <p>Es el paso que faltaba para que un ESP32 recién estrenado pueda usarse:
     * antes el latido de una MAC desconocida se perdía y no había forma de
     * adoptarla desde la aplicación.</p>
     *
     * @param peticion MAC del aparato, nombre con el que se quiere ver y categoría (CAMARA por defecto).
     * @return el dispositivo creado, 404 si esa MAC no está latiendo, o 409 si ya es de otra casa.
     */
    @PostMapping(value = "/reclamar", produces = "application/json")
    public ResponseEntity<?> reclamar(@RequestBody ReclamarDTO peticion) {
        Long casaId = authContext.casaIdActual();
        if (casaId == null) {
            return ResponseEntity.status(401).body(Map.of(
                "ok", false, "error", "Necesitas una vivienda para vincular un dispositivo"));
        }
        if (peticion == null || peticion.mac() == null || peticion.mac().isBlank()) {
            return ResponseEntity.badRequest().body(Map.of(
                "ok", false, "error", "Falta la MAC del dispositivo"));
        }

        String mac = peticion.mac().trim();

        // Que otra casa lo tenga es el caso que el requisito pide bloquear, y
        // merece un mensaje propio: la MAC es UNIQUE, así que sin esta
        // comprobación el INSERT reventaría con un error de base ilegible.
        List<Map<String, Object>> duenos = jdbc.queryForList(
            "SELECT z.casa_id FROM dispositivo d JOIN zona z ON z.id = d.zona_id " +
            "WHERE d.mac_address = ? AND d.deleted_at IS NULL", mac);
        if (!duenos.isEmpty()) {
            Long casaDelAparato = ((Number) duenos.get(0).get("casa_id")).longValue();
            boolean esMio = casaId.equals(casaDelAparato);
            return ResponseEntity.status(409).body(Map.of(
                "ok", false,
                "error", esMio
                    ? "Este dispositivo ya está vinculado a tu vivienda"
                    : "Este dispositivo ya está vinculado a otra cuenta"));
        }

        List<Map<String, Object>> visto = jdbc.queryForList(
            "SELECT modelo, ip_local FROM dispositivo_presencia " +
            "WHERE mac_address = ? AND ultimo_latido > now() - make_interval(secs => ?)",
            mac, (double) ventanaSegundos);
        if (visto.isEmpty()) {
            return ResponseEntity.status(404).body(Map.of(
                "ok", false,
                "error", "Ese dispositivo no está dando señal. Comprueba que esté encendido y en la misma red."));
        }

        Long zonaId = zonaDeLaCasa(casaId);
        if (zonaId == null) {
            return ResponseEntity.badRequest().body(Map.of(
                "ok", false, "error", "Tu vivienda todavía no tiene zonas configuradas"));
        }

        String categoria = peticion.categoria() != null && !peticion.categoria().isBlank()
            ? peticion.categoria().trim().toUpperCase()
            : "CAMARA";
        String nombre = peticion.nombre() != null && !peticion.nombre().isBlank()
            ? recortar(peticion.nombre().trim(), 50)
            : recortar((String) visto.get(0).get("modelo"), 50);

        jdbc.update(
            "INSERT INTO dispositivo (zona_id, mac_address, tipo, categoria, modelo, ultima_conexion) " +
            "VALUES (?, ?, 'ACTUADOR'::tipo_dispositivo, ?::categoria_dispositivo, ?, now())",
            zonaId, mac, categoria, nombre);

        List<Map<String, Object>> creado = jdbc.queryForList(
            "SELECT d.id, d.mac_address, d.modelo, d.categoria::text AS categoria, d.tipo::text AS tipo, " +
            "       d.ultima_conexion, p.ip_local " +
            "FROM dispositivo d " +
            "LEFT JOIN dispositivo_presencia p ON p.mac_address = d.mac_address " +
            "WHERE d.mac_address = ?", mac);

        return ResponseEntity.ok(Map.of(
            "ok", true,
            "dispositivo", creado.isEmpty() ? Map.of() : creado.get(0)));
    }

    /**
     * Estado de conexión del IoT de esta vivienda, que es lo que la web y la
     * aplicación consultan para habilitar o bloquear los controles físicos.
     *
     * @return cuántos aparatos hay y cuántos están en línea, más el detalle de cada uno.
     */
    @GetMapping(value = "/estado", produces = "application/json")
    public ResponseEntity<?> estado() {
        Long casaId = authContext.casaIdActual();
        if (casaId == null) {
            return ResponseEntity.status(401).body(Map.of(
                "ok", false, "error", "Necesitas una vivienda para consultar el estado del IoT"));
        }

        List<Map<String, Object>> aparatos = jdbc.queryForList(
            "SELECT d.id, d.mac_address, d.categoria::text AS categoria, d.modelo, d.ultima_conexion, " +
            "       (d.ultima_conexion IS NOT NULL " +
            "        AND d.ultima_conexion > now() - make_interval(secs => ?)) AS en_linea " +
            "FROM dispositivo d JOIN zona z ON z.id = d.zona_id " +
            "WHERE z.casa_id = ? AND d.deleted_at IS NULL " +
            "ORDER BY d.categoria",
            (double) ventanaSegundos, casaId);

        long enLinea = aparatos.stream().filter(a -> Boolean.TRUE.equals(a.get("en_linea"))).count();

        return ResponseEntity.ok(Map.of(
            "ok", true,
            "conectado", enLinea > 0,
            "enLinea", enLinea,
            "total", aparatos.size(),
            "ventanaSegundos", ventanaSegundos,
            "dispositivos", aparatos));
    }

    /** Primera zona de la casa; sirve para colgar de ahí un aparato recién adoptado. */
    private Long zonaDeLaCasa(Long casaId) {
        List<Map<String, Object>> zonas = jdbc.queryForList(
            "SELECT id FROM zona WHERE casa_id = ? ORDER BY id LIMIT 1", casaId);
        return zonas.isEmpty() ? null : ((Number) zonas.get(0).get("id")).longValue();
    }

    private static String primeroNoVacio(String a, String b) {
        if (a != null && !a.isBlank()) return a.trim();
        if (b != null && !b.isBlank()) return b.trim();
        return null;
    }

    private static String recortar(String valor, int maximo) {
        if (valor == null || valor.isBlank()) return null;
        String limpio = valor.trim();
        return limpio.length() > maximo ? limpio.substring(0, maximo) : limpio;
    }
}
