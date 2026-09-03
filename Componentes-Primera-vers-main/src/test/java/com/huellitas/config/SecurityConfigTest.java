package com.huellitas.config;

import com.fernando.esp32.Esp32Application;
import com.huellitas.auth.JwtUtil;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Verifica el comportamiento de {@link SecurityConfig}: las rutas de
 * administración y la mayoría de rutas de usuario exigen un JWT válido (con
 * el rol correcto donde aplica), las rutas genuinamente públicas siguen
 * siéndolo, y ningún controlador confía en el {@code usuarioId}/{@code casaId}
 * que manda el propio cliente — todo se deriva del token. Cubre exactamente
 * el hueco de seguridad identificado en la auditoría del proyecto (antes,
 * cualquiera podía llamar a la API sin autenticarse, o hacerse pasar por
 * otro usuario con solo cambiar un número en la petición).
 */
@SpringBootTest(classes = Esp32Application.class, webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SecurityConfigTest {

    @LocalServerPort
    private int port;

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private JwtUtil jwtUtil;

    private String url(String path) {
        return "http://localhost:" + port + path;
    }

    private String tokenPara(long usuarioId, String rol) {
        String userJson = "{\"id\":" + usuarioId + ",\"nombre\":\"Test\",\"email\":\"test@test.local\",\"rol\":\"" + rol + "\",\"casa_id\":1,\"email_verificado\":true}";
        return jwtUtil.generateTokenFromJsonUser(userJson);
    }

    private HttpHeaders headersCon(String token) {
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer " + token);
        return headers;
    }

    // ── Rutas de administración ──────────────────────────────────────────

    @Test
    void adminSinTokenDevuelve401() {
        ResponseEntity<String> res = restTemplate.getForEntity(url("/api/huellitas/admin/usuarios"), String.class);
        assertEquals(HttpStatus.UNAUTHORIZED, res.getStatusCode());
    }

    @Test
    void adminConRolIncorrectoDevuelve403() {
        ResponseEntity<String> res = restTemplate.exchange(url("/api/huellitas/admin/usuarios"), HttpMethod.GET,
            new HttpEntity<>(headersCon(tokenPara(999999L, "MIEMBRO"))), String.class);
        assertEquals(HttpStatus.FORBIDDEN, res.getStatusCode());
    }

    @Test
    void adminConTokenDeAdministradorFunciona() {
        ResponseEntity<String> res = restTemplate.exchange(url("/api/huellitas/admin/usuarios"), HttpMethod.GET,
            new HttpEntity<>(headersCon(tokenPara(999999L, "ADMINISTRADOR"))), String.class);
        assertEquals(HttpStatus.OK, res.getStatusCode());
    }

    @Test
    void adminConTokenForjadoDevuelve401() {
        HttpHeaders headers = new HttpHeaders();
        headers.set("Authorization", "Bearer eyJhbGciOiJIUzI1NiJ9.eyJyb2wiOiJBRE1JTklTVFJBRE9SIn0.firma_invalida");
        ResponseEntity<String> res = restTemplate.exchange(url("/api/huellitas/admin/usuarios"), HttpMethod.GET, new HttpEntity<>(headers), String.class);
        assertEquals(HttpStatus.UNAUTHORIZED, res.getStatusCode());
    }

    // ── Rutas de usuario normal ───────────────────────────────────────────

    @Test
    void feedSocialSinTokenDevuelve401() {
        ResponseEntity<String> res = restTemplate.getForEntity(url("/api/huellitas/social/feed?usuarioId=1&limite=1"), String.class);
        assertEquals(HttpStatus.UNAUTHORIZED, res.getStatusCode());
    }

    @Test
    void feedSocialConTokenFunciona() {
        ResponseEntity<String> res = restTemplate.exchange(url("/api/huellitas/social/feed?limite=1"), HttpMethod.GET,
            new HttpEntity<>(headersCon(tokenPara(USUARIO_DE_PRUEBA_REAL, "MIEMBRO"))), String.class);
        assertEquals(HttpStatus.OK, res.getStatusCode());
    }

    @Test
    void strikeSocialConRolIncorrectoDevuelve403() {
        ResponseEntity<String> res = restTemplate.exchange(url("/api/huellitas/social/strike?usuarioId=999999"), HttpMethod.POST,
            new HttpEntity<>(headersCon(tokenPara(999999L, "MIEMBRO"))), String.class);
        assertEquals(HttpStatus.FORBIDDEN, res.getStatusCode());
    }

    // ── La identidad del token manda, no la que mande el cliente ─────────

    /** Usuario de prueba real y persistente usado durante toda esta sesión de trabajo (Diego, Test Miembro). */
    private static final long USUARIO_DE_PRUEBA_REAL = 29L;

    @Test
    void publicarConUsuarioIdAjenoUsaLaIdentidadDelToken() {
        // El cliente manda un usuarioId de otra persona (999999999) en el
        // body, pero autenticado como el usuario de prueba real — el post
        // debe quedar guardado con el autor REAL (el del token), nunca con
        // el suplantado, o el fix de la auditoría no serviría de nada.
        long usuarioIdSuplantado = 888888888L;
        HttpHeaders headers = headersCon(tokenPara(USUARIO_DE_PRUEBA_REAL, "MIEMBRO"));
        headers.setContentType(MediaType.APPLICATION_JSON);
        String body = "{\"usuarioId\":" + usuarioIdSuplantado + ",\"contenido\":\"[test-seguridad] prueba de suplantacion de identidad\"}";

        ResponseEntity<String> res = restTemplate.postForEntity(url("/api/huellitas/social/publicacion"), new HttpEntity<>(body, headers), String.class);
        assertEquals(HttpStatus.OK, res.getStatusCode());
        assertTrue(res.getBody().contains("\"usuario_id\":" + USUARIO_DE_PRUEBA_REAL), "El post debe quedar con el usuario del token: " + res.getBody());
        assertFalse(res.getBody().contains(String.valueOf(usuarioIdSuplantado)), "El usuarioId suplantado no debe aparecer en la respuesta: " + res.getBody());

        // Limpieza: borrar el post de prueba recién creado.
        String idStr = res.getBody().replaceAll(".*\"id\":(\\d+).*", "$1");
        restTemplate.exchange(url("/api/huellitas/social/publicacion/" + idStr), HttpMethod.DELETE,
            new HttpEntity<>(headersCon(tokenPara(USUARIO_DE_PRUEBA_REAL, "MIEMBRO"))), String.class);
    }

    // ── Rutas genuinamente públicas siguen siéndolo ──────────────────────

    @Test
    void testimoniosPublicosSiguenSiendoPublicos() {
        ResponseEntity<String> res = restTemplate.getForEntity(url("/api/huellitas/social/testimonios-publicos"), String.class);
        assertEquals(HttpStatus.OK, res.getStatusCode());
    }

    @Test
    void estadisticasPublicasSiguenSiendoPublicas() {
        ResponseEntity<String> res = restTemplate.getForEntity(url("/api/huellitas/casa/estadisticas-publicas"), String.class);
        assertEquals(HttpStatus.OK, res.getStatusCode());
    }

    @Test
    void loginSigueSiendoPublico() {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        String body = "{\"email\":\"no-existe@test.local\",\"password\":\"x\"}";
        ResponseEntity<String> res = restTemplate.postForEntity(url("/api/huellitas/auth/login"), new HttpEntity<>(body, headers), String.class);
        // Credenciales inválidas (401 de negocio), pero llegó al controlador
        // — no lo bloqueó el filtro de seguridad antes de tiempo.
        assertEquals(HttpStatus.UNAUTHORIZED, res.getStatusCode());
        assertTrue(res.getBody().contains("Credenciales inválidas") || res.getBody().contains("CREDENCIALES_INVALIDAS"));
    }
}
