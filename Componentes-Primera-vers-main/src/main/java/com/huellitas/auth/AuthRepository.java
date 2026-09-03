package com.huellitas.auth;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * Acceso a datos de {@link Usuario} que delega la mayor parte de la lógica
 * de autenticación y gestión de cuenta en funciones almacenadas de
 * PostgreSQL (registro, login, OAuth, recuperación de contraseña,
 * verificación de correo, onboarding), devolviendo sus resultados como JSON.
 */
public interface AuthRepository extends JpaRepository<Usuario, Long> {

    /**
     * Registra un nuevo usuario propietario junto con su vivienda inicial.
     *
     * @param email correo electrónico del nuevo propietario.
     * @param password contraseña en texto plano (se hashea en la función de base de datos).
     * @param nombre nombre del propietario.
     * @param casaNombre nombre de la vivienda a crear.
     * @param direccion dirección de la vivienda.
     * @param ciudad ciudad de la vivienda.
     * @param latitud latitud geográfica de la vivienda.
     * @param longitud longitud geográfica de la vivienda.
     * @return resultado de la operación en formato JSON (texto).
     */
    @Query(value = "SELECT fn_registrar_propietario(:email, :password, :nombre, :casaNombre, :direccion, :ciudad, :latitud, :longitud)", nativeQuery = true)
    String registrarPropietario(
            @Param("email") String email,
            @Param("password") String password,
            @Param("nombre") String nombre,
            @Param("casaNombre") String casaNombre,
            @Param("direccion") String direccion,
            @Param("ciudad") String ciudad,
            @Param("latitud") java.math.BigDecimal latitud,
            @Param("longitud") java.math.BigDecimal longitud
    );

    /**
     * Autentica a un usuario por email y contraseña.
     *
     * @param email correo electrónico del usuario.
     * @param password contraseña en texto plano a verificar.
     * @return datos de sesión del usuario en formato JSON si las credenciales son válidas.
     */
    @Query(value = "SELECT fn_login(:email, :password)", nativeQuery = true)
    String login(@Param("email") String email, @Param("password") String password);

    /** Datos actuales del usuario (sin la contraseña), para que los clientes
     *  puedan refrescar la sesión y ver cambios hechos desde otra plataforma. */
    @Query(value = "SELECT (row_to_json(u)::jsonb - 'password_hash')::text FROM usuario u WHERE u.id = :id", nativeQuery = true)
    String obtenerUsuarioPorId(@Param("id") Long id);

    /**
     * Autentica (o registra si es la primera vez) a un usuario mediante un proveedor OAuth externo.
     *
     * @param proveedor nombre del proveedor OAuth (por ejemplo, GOOGLE o FACEBOOK).
     * @param proveedorUid identificador único que el proveedor asigna al usuario.
     * @param email correo electrónico reportado por el proveedor.
     * @param nombre nombre reportado por el proveedor.
     * @param fotoUrl URL de la foto de perfil reportada por el proveedor.
     * @return datos de sesión del usuario en formato JSON.
     */
    @Query(value = "SELECT fn_login_oauth(CAST(:proveedor AS proveedor_auth), :proveedorUid, :email, :nombre, :fotoUrl)", nativeQuery = true)
    String loginOauth(@Param("proveedor") String proveedor, @Param("proveedorUid") String proveedorUid, @Param("email") String email, @Param("nombre") String nombre, @Param("fotoUrl") String fotoUrl);

    /**
     * Establece la contraseña de un usuario que aún no tiene una (por ejemplo, tras registrarse vía OAuth).
     *
     * @param usuarioId identificador del usuario.
     * @param password nueva contraseña en texto plano.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_establecer_password_inicial(:usuarioId, :password)", nativeQuery = true)
    String establecerPasswordInicial(@Param("usuarioId") Long usuarioId, @Param("password") String password);

    /**
     * Verifica si un usuario ya tiene una contraseña local configurada.
     *
     * @param usuarioId identificador del usuario.
     * @return {@code true} si el usuario tiene contraseña establecida.
     */
    @Query(value = "SELECT CASE WHEN password_hash IS NOT NULL THEN true ELSE false END FROM usuario WHERE id = :usuarioId", nativeQuery = true)
    Boolean tienePassword(@Param("usuarioId") Long usuarioId);

    /**
     * Invita a un nuevo miembro a unirse a una vivienda existente.
     *
     * @param casaId identificador de la vivienda a la que se invita.
     * @param email correo electrónico del miembro invitado.
     * @param password contraseña inicial asignada al miembro.
     * @param nombre nombre del miembro invitado.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_invitar_miembro(:casaId, :email, :password, :nombre)", nativeQuery = true)
    String invitarMiembro(@Param("casaId") Long casaId, @Param("email") String email, @Param("password") String password, @Param("nombre") String nombre);

    /**
     * Registra una solicitud de restablecimiento de contraseña para un correo dado.
     *
     * @param email correo electrónico del usuario que solicita el restablecimiento.
     * @param tokenHash hash del token de restablecimiento generado para validar el enlace enviado por correo.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_solicitar_reset(:email, :tokenHash)", nativeQuery = true)
    String solicitarReset(@Param("email") String email, @Param("tokenHash") String tokenHash);

    /**
     * Completa el restablecimiento de contraseña validando el token enviado por correo.
     *
     * @param tokenHash hash del token de restablecimiento recibido.
     * @param passwordNueva nueva contraseña en texto plano.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_resetear_password(:tokenHash, :passwordNueva)", nativeQuery = true)
    String resetearPassword(@Param("tokenHash") String tokenHash, @Param("passwordNueva") String passwordNueva);

    /**
     * Actualiza el nombre y/o la foto de perfil de un usuario.
     *
     * @param usuarioId identificador del usuario a actualizar.
     * @param nombre nuevo nombre del usuario.
     * @param fotoUrl nueva URL de la foto de perfil.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_actualizar_perfil(:usuarioId, :nombre, :fotoUrl)", nativeQuery = true)
    String actualizarPerfil(@Param("usuarioId") Long usuarioId, @Param("nombre") String nombre, @Param("fotoUrl") String fotoUrl);

    /**
     * Genera y registra un código de verificación de correo para un usuario ya autenticado.
     *
     * @param usuarioId identificador del usuario.
     * @param codigo código de verificación generado.
     * @param minutos minutos de validez del código.
     * @return {@code true} si el código quedó registrado correctamente.
     */
    @Query(value = "SELECT fn_solicitar_verificacion(:usuarioId, :codigo, :minutos)", nativeQuery = true)
    Boolean solicitarVerificacion(@Param("usuarioId") Long usuarioId, @Param("codigo") String codigo, @Param("minutos") Integer minutos);

    /**
     * Genera y registra un código de verificación de correo identificando al usuario por su email.
     *
     * @param email correo electrónico del usuario.
     * @param codigo código de verificación generado.
     * @param minutos minutos de validez del código.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_solicitar_verificacion_por_email(:email, :codigo, :minutos)", nativeQuery = true)
    String solicitarVerificacionPorEmail(@Param("email") String email, @Param("codigo") String codigo, @Param("minutos") Integer minutos);

    /**
     * Valida el código de verificación de correo enviado a un usuario.
     *
     * @param email correo electrónico del usuario.
     * @param codigo código de verificación ingresado por el usuario.
     * @return resultado de la validación en formato JSON.
     */
    @Query(value = "SELECT fn_verificar_codigo(:email, :codigo)", nativeQuery = true)
    String verificarCodigo(@Param("email") String email, @Param("codigo") String codigo);

    /**
     * Completa el proceso de onboarding de un usuario recién verificado,
     * registrando sus datos personales y la vivienda inicial.
     *
     * @param usuarioId identificador del usuario.
     * @param nombre nombre del usuario.
     * @param casaNombre nombre de la vivienda a crear.
     * @param direccion dirección de la vivienda.
     * @param ciudad ciudad de la vivienda.
     * @param latitud latitud geográfica de la vivienda.
     * @param longitud longitud geográfica de la vivienda.
     * @return resultado de la operación en formato JSON.
     */
    @Query(value = "SELECT fn_completar_onboarding(:usuarioId, :nombre, :casaNombre, :direccion, :ciudad, :latitud, :longitud)", nativeQuery = true)
    String completarOnboarding(
            @Param("usuarioId") Long usuarioId,
            @Param("nombre") String nombre,
            @Param("casaNombre") String casaNombre,
            @Param("direccion") String direccion,
            @Param("ciudad") String ciudad,
            @Param("latitud") java.math.BigDecimal latitud,
            @Param("longitud") java.math.BigDecimal longitud
    );
}