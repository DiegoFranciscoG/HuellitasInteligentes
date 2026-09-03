import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Servicio centralizado de autenticación.
/// Guarda el JWT en memoria durante la sesión.
class AuthService {
  static String? _token;
  static String? _rol;
  static Map<String, dynamic>? _userData;

  /// URL base del backend (`API_URL` en `.env`, o `http://localhost:8087/api`
  /// si no está configurada).
  static String get baseUrl =>
      dotenv.env['API_URL'] ?? 'http://localhost:8087/api';

  /// JWT de la sesión activa, o `null` si nadie ha iniciado sesión.
  static String? get token => _token;
  /// Rol del usuario autenticado (`PROPIETARIO`, `MIEMBRO`, `ADMINISTRADOR`, etc.).
  static String? get rol => _rol;
  /// Datos del usuario autenticado tal como los devolvió el backend (normalizados).
  static Map<String, dynamic>? get userData => _userData;
  /// `true` si hay un token guardado en memoria, es decir, si hay sesión activa.
  static bool get isLoggedIn => _token != null;

  /// Cierto mientras el usuario siga con la contraseña provisional que se le
  /// envió por correo. El servidor la marca al crear el miembro y la limpia en
  /// cuanto elige una propia, aquí o en la web; por eso quien ya la cambió
  /// desde la web entra directo sin que se le vuelva a pedir.
  static bool get debeCambiarPassword {
    final v = _userData?['debe_cambiar_password'] ?? _userData?['debeCambiarPassword'];
    return v == true || v?.toString().toLowerCase() == 'true';
  }

  /// `true` si la cuenta no tiene ninguna vivienda asociada: un miembro
  /// recién dado de baja (que queda como PROPIETARIO sin `casa_id`) o una
  /// cuenta nueva creada por Google/Facebook que todavía no completó el
  /// registro. Se excluye al administrador, que no gestiona una vivienda
  /// propia. Quien esté en este caso debe pasar por [OnboardingScreen] antes
  /// que por el resto de la app, o sus pantallas se quedan sin datos.
  static bool get needsOnboarding {
    final rol = (_userData?['rol'] ?? '').toString().toUpperCase();
    if (rol == 'ADMINISTRADOR' || rol == 'ADMIN') return false;
    return (_userData?['casa_id'] ?? _userData?['casaId']) == null;
  }

  /// Id de la vivienda de la que esta cuenta fue dada de baja como miembro,
  /// o `null` si nunca lo fue. Lo pone `casa_anterior_id` en la fila de
  /// `usuario`; solo sirve para explicar por qué está en onboarding, no da
  /// ningún acceso a esa vivienda.
  static int? get casaAnteriorId {
    final v = _userData?['casa_anterior_id'] ?? _userData?['casaAnteriorId'];
    if (v == null) return null;
    return v is int ? v : int.tryParse(v.toString());
  }

  /// Fija la contraseña definitiva. Devuelve null si salió bien.
  static Future<String?> cambiarPasswordObligatorio(String nuevaPassword) async {
    if (nuevaPassword.trim().length < 6) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/huellitas/auth/cambiar-password-obligatorio'),
        headers: authHeaders,
        body: jsonEncode({'nuevaPassword': nuevaPassword.trim()}),
      );

      if (response.statusCode == 200) {
        // Se limpia en memoria para que la app no vuelva a pedirla en esta sesión.
        if (_userData != null) {
          _userData!['debe_cambiar_password'] = false;
          _userData!['debeCambiarPassword'] = false;
          _marcarUsuarioActualizado();
        }
        return null;
      }
      return _describirError('cambiar la contraseña', response.statusCode, response.body);
    } catch (e) {
      return 'No se pudo conectar con el servidor: $e';
    }
  }

  /// Se incrementa cada vez que cambian los datos del usuario. Las pantallas
  /// que muestran su foto o nombre (por ejemplo el encabezado del menú) lo
  /// escuchan para repintarse en el momento, sin reiniciar la app.
  static final ValueNotifier<int> userVersion = ValueNotifier<int>(0);

  static void _marcarUsuarioActualizado() {
    userVersion.value++;
  }

  /// Reemplaza los datos del usuario en memoria (normalizándolos primero) y
  /// avisa a los listeners de [userVersion] para que la UI se repinte.
  static void updateUserData(Map<String, dynamic> newUserData) {
    _userData = normalizeUser(newUserData);
    _marcarUsuarioActualizado();
  }

  /// El backend devuelve la fila de `usuario` tal cual (snake_case:
  /// `foto_url`, `casa_id`), pero la app lee `fotoUrl`/`casa_id`. Sin
  /// normalizar, al guardar el perfil la foto nueva llegaba como `foto_url`
  /// y la UI —que lee `fotoUrl`— seguía mostrando la anterior o ninguna.
  /// Dejamos ambas claves pobladas para que no importe cuál se lea.
  static Map<String, dynamic> normalizeUser(Map<String, dynamic> user) {
    final normalized = Map<String, dynamic>.from(user);
    // `foto_url` es el campo real del servidor y manda: `fotoUrl` es solo un
    // alias que guardamos en el cliente. Al revés, un alias viejo en memoria
    // le ganaba a la foto recién subida y la imagen no cambiaba nunca.
    final foto = normalized['foto_url'] ?? normalized['fotoUrl'];
    if (foto != null) {
      normalized['fotoUrl'] = foto;
      normalized['foto_url'] = foto;
    }
    final casa = normalized['casa_id'] ?? normalized['casaId'];
    if (casa != null) {
      normalized['casa_id'] = casa;
      normalized['casaId'] = casa;
    }
    return normalized;
  }

  /// Login email/password → devuelve null si OK, mensaje de error si falla
  static Future<String?> loginEmail(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/huellitas/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        handleAuthResponse(res.body);
        return null;
      }
      try {
        final body = jsonDecode(res.body);
        return body['message'] ?? body['error'] ?? 'Credenciales incorrectas.';
      } catch (_) {
        return 'Error del servidor (${res.statusCode}).';
      }
    } catch (e) {
      return 'Sin conexión. Verifica que el servidor esté encendido y el firewall abierto.';
    }
  }

  /// Login con Google ID token → devuelve null si OK, mensaje de error si falla
  static Future<String?> loginGoogle(String idToken) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/huellitas/auth/google/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        handleAuthResponse(res.body);
        return null;
      }
      try {
        final body = jsonDecode(res.body);
        return body['message'] ?? 'Error en autenticación Google.';
      } catch (_) {
        return 'Error del servidor (${res.statusCode}).';
      }
    } catch (e) {
      return 'Error de conexión: $e';
    }
  }

  /// Registro de propietario
  static Future<String?> registerOwner({
    required String email,
    required String password,
    required String nombre,
    required String nombreCasa,
    String? direccion,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/huellitas/auth/registro-propietario'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'nombre': nombre,
          // El backend lee "casa_nombre" (snake_case, así lo manda la web).
          // Esta app mandaba "nombreCasa", que el backend ignora — llegaba
          // null, y el rechazo de ese campo se mostraba como si el nombre
          // de la persona estuviera vacío, aunque sí estaba lleno.
          'casa_nombre': nombreCasa,
          if (direccion != null && direccion.isNotEmpty) 'direccion': direccion,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        // En caso de éxito, el backend suele devolver el JWT directamente
        // o podemos requerir que el usuario haga login manualmente.
        // Asumimos que podemos parsear la respuesta si trae el token:
        try {
          handleAuthResponse(res.body);
        } catch (_) {
          // Si no devuelve token, no importa, devuelve null (éxito) y el usuario hará login manual.
        }
        return null;
      }
      try {
        final body = jsonDecode(res.body);
        return body['message'] ?? body['error'] ?? 'Error al registrar. Verifica los datos.';
      } catch (_) {
        return 'Error del servidor (${res.statusCode}).';
      }
    } catch (e) {
      return 'Sin conexión. Verifica que el servidor esté encendido.';
    }
  }

  static void handleAuthResponse(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    _token = data['token'] ?? data['accessToken'] ?? data['jwt'];
    
    if (data.containsKey('usuario')) {
      if (data['usuario'] is String) {
        try {
          _userData = jsonDecode(data['usuario']) as Map<String, dynamic>;
        } catch (_) {
          _userData = data;
        }
      } else if (data['usuario'] is Map) {
        _userData = data['usuario'] as Map<String, dynamic>;
      } else {
        _userData = data;
      }
    } else {
      _userData = data;
    }

    if (_userData != null) {
      _userData = normalizeUser(_userData!);
      _marcarUsuarioActualizado();
    }

    // Al igual que en Angular, extraemos datos extra del JWT (como casa_id)
    if (_token != null) {
      try {
        final parts = _token!.split('.');
        if (parts.length == 3) {
          String normalized = base64Url.normalize(parts[1]);
          final String decoded = utf8.decode(base64Url.decode(normalized));
          final Map<String, dynamic> jwtData = jsonDecode(decoded);
          
          final int? payloadCasaId = (jwtData['casa_id'] != null) ? int.tryParse(jwtData['casa_id'].toString()) : null;
          
          _userData = {
            ...?_userData,
            if (jwtData['rol'] != null) 'rol': jwtData['rol'],
            if (payloadCasaId != null) 'casa_id': payloadCasaId,
          };
        }
      } catch (e) {
        // ignore
      }
    }
    
    // El rol puede venir como "PROPIETARIO", "MIEMBRO", "ADMINISTRADOR", etc.
    _rol = (_userData?['rol'] ?? _userData?['role'] ?? _userData?['tipoUsuario'] ?? '').toString().toUpperCase();
  }

  /// Cabeceras HTTP estándar para llamadas autenticadas: `Content-Type` JSON
  /// más el `Authorization: Bearer` con el token actual, si existe.
  static Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// Convierte una respuesta de error del backend en un mensaje que dice qué
  /// pasó de verdad. Antes todos los fallos mostraban el mismo texto genérico,
  /// lo que hacía imposible distinguir "sesión vencida" de "datos inválidos".
  static String _describirError(String accion, int statusCode, String body) {
    if (statusCode == 401 || statusCode == 403) {
      return 'Tu sesión expiró. Cierra sesión y vuelve a entrar para $accion.';
    }
    String detalle = '';
    try {
      final data = jsonDecode(body);
      if (data is Map) detalle = (data['error'] ?? data['message'] ?? '').toString();
    } catch (_) {}
    if (detalle.isEmpty) detalle = 'HTTP $statusCode';
    return 'No se pudo $accion: $detalle';
  }

  /// Cierra la sesión actual: borra el token, el rol y los datos de usuario
  /// guardados en memoria.
  static void logout() {
    _token = null;
    _rol = null;
    _userData = null;
  }

  /// Completa el login que vuelve por el enlace `huellitas://oauth-callback`
  /// tras iniciar sesión con Facebook en el navegador.
  ///
  /// Ese enlace solo trae el JWT (Facebook redirige a una URL fija, no
  /// puede llevar el usuario completo cómodamente), así que primero se fija
  /// el token y después se pide `/me` para completar `_userData` y `_rol` —
  /// los mismos datos que un login normal deja listos de una vez.
  ///
  /// Devuelve `true` solo si el servidor confirmó ese token. Si no, lo borra
  /// en vez de dejarlo puesto: antes, un token inválido dejaba la app "con
  /// sesión" en apariencia —entraba a la pantalla de completar registro
  /// igual, porque sin datos de usuario todo parece faltar una vivienda—
  /// hasta que la primera acción real chocaba con un 401 sin explicación.
  static Future<bool> completarLoginPorEnlace(String token) async {
    _token = token;
    final ok = await refrescarUsuario();
    if (!ok) logout();
    return ok;
  }

  /// Setea la autenticación a partir del payload del QR de cámara
  static void setAuthFromQrPayload(Map<String, dynamic> qrData) {
    _token = qrData['token'];
    _userData = {
      'id': qrData['userId'],
      'casa_id': qrData['casaId'],
      'rol': 'PROPIETARIO' // o MIEMBRO, no importa mucho para la cámara
    };
    _rol = 'PROPIETARIO';
  }

  // ─── PERFIL Y MIEMBROS ─────────────────────────────────────────────────────

  /// Lista los miembros de la casa del usuario autenticado. Devuelve una
  /// lista vacía si la petición falla, en vez de lanzar una excepción.
  static Future<List<dynamic>> listarMiembros() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/huellitas/auth/miembros'),
        headers: authHeaders,
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Invita a un nuevo miembro a la casa del usuario autenticado, creándole
  /// una cuenta con la contraseña provisional dada. Devuelve null si salió
  /// bien, o un mensaje de error si falla.
  static Future<String?> invitarMiembro(String email, String nombre, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/huellitas/auth/miembros'),
        headers: authHeaders,
        body: jsonEncode({'email': email, 'nombre': nombre, 'password': password}),
      );
      if (res.statusCode == 200 || res.statusCode == 201) return null;
      debugPrint('[INVITAR] HTTP ${res.statusCode} tokenPresente=${_token != null} body=${res.body}');
      return _describirError('invitar al miembro', res.statusCode, res.body);
    } catch (e) {
      return 'Error de conexión: $e';
    }
  }

  /// Elimina de la casa al miembro con el `id` dado. Devuelve null si salió
  /// bien, o un mensaje de error si falla.
  static Future<String?> eliminarMiembro(int id) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/huellitas/auth/miembros/$id'),
        headers: authHeaders,
      );
      if (res.statusCode == 200) return null;
      return 'Error al eliminar miembro';
    } catch (e) {
      return 'Error de conexión: $e';
    }
  }

  /// Pide al backend un token de acceso rápido por QR (para escanear e
  /// iniciar sesión, o para autenticar una cámara). [miembroId] limita el QR
  /// a ese miembro; [tipo] identifica el uso que se le dará al token.
  /// Devuelve el payload del QR, o null si falla.
  static Future<Map<String, dynamic>?> generarQrToken({int? miembroId, String tipo = 'ACCESO_RAPIDO'}) async {
    try {
      final uri = Uri.parse('$baseUrl/huellitas/auth/qr/generar').replace(queryParameters: {
        'tipo': tipo,
        if (miembroId != null) 'miembroId': miembroId.toString(),
      });
      final res = await http.post(uri, headers: authHeaders);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      debugPrint('[QR] HTTP ${res.statusCode} tokenPresente=${_token != null} body=${res.body}');
      return null;
    } catch (e) {
      debugPrint('[QR] excepcion: $e');
      return null;
    }
  }

  /// Recarga el usuario desde el servidor para reflejar cambios hechos en la
  /// web (foto, nombre) sin tener que cerrar sesión.
  ///
  /// Devuelve si de verdad se pudo confirmar la sesión contra el servidor.
  /// [completarLoginPorEnlace] depende de esto: sin saber si `/me` respondió
  /// 200, seguía adelante igual con un token inválido —quedaba "con sesión"
  /// en apariencia, hasta que la primera acción real (por ejemplo crear la
  /// vivienda) se encontraba con un 401 sin ninguna pista de por qué.
  static Future<bool> refrescarUsuario() async {
    if (_token == null) return false;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/huellitas/auth/me'),
        headers: authHeaders,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map<String, dynamic>) {
          _userData = normalizeUser({...?_userData, ...data});
          // `/me` trae la fila de usuario tal cual está en la base, así que
          // si el rol cambió desde otro lado (la web, un ajuste directo en
          // la base) esto lo pone al día. Antes solo `handleAuthResponse`
          // (llamado al iniciar sesión) actualizaba `_rol`, de modo que un
          // cambio de rol no se veía hasta cerrar sesión y volver a entrar.
          _rol = (_userData?['rol'] ?? _userData?['role'] ?? '').toString().toUpperCase();
          _marcarUsuarioActualizado();
          return true;
        }
      } else {
        debugPrint('[ME] HTTP ${res.statusCode} body=${res.body}');
      }
    } catch (e) {
      debugPrint('[ME] excepcion: $e');
    }
    return false;
  }

  /// Actualiza el nombre (y opcionalmente la foto) del perfil del usuario
  /// autenticado. Si se pasa [foto], se envía como `multipart/form-data`;
  /// si no, como JSON. Devuelve null si salió bien, o un mensaje de error.
  static Future<String?> actualizarPerfil(String nombre, {File? foto}) async {
    try {
      if (foto != null) {
        final request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/huellitas/auth/perfil'));
        request.headers['Authorization'] = 'Bearer $_token';
        request.fields['nombre'] = nombre;
        // El backend exige extensión y content-type reconocidos; una foto de
        // cámara puede llegar con una ruta sin extensión válida, así que se
        // fuerzan ambos según la extensión real del archivo (JPG si no hay).
        final rawExt = foto.path.contains('.') ? foto.path.split('.').last.toLowerCase() : '';
        const extAMime = {
          'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
          'webp': 'image/webp', 'gif': 'image/gif',
        };
        final ext = extAMime.containsKey(rawExt) ? rawExt : 'jpg';
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          foto.path,
          filename: 'foto.$ext',
          contentType: MediaType.parse(extAMime[ext]!),
        ));

        final streamed = await request.send();
        final body = await streamed.stream.bytesToString();
        if (streamed.statusCode == 200) {
          final updatedData = jsonDecode(body);
          _userData = normalizeUser({...?_userData, ...updatedData});
          _marcarUsuarioActualizado();
          return null;
        }
        debugPrint('[PERFIL/FOTO] HTTP ${streamed.statusCode} tokenPresente=${_token != null} body=$body');
        return _describirError('actualizar perfil', streamed.statusCode, body);
      }

      // JSON, no form-urlencoded: el endpoint recibe un @RequestBody PerfilDTO
      // y Spring no sabe convertir form-urlencoded a un objeto, devolvía
      // HTTP 500 "Content-Type ... is not supported".
      final res = await http.put(
        Uri.parse('$baseUrl/huellitas/auth/perfil'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'nombre': nombre}),
      );
      if (res.statusCode == 200) {
        final updatedData = jsonDecode(res.body);
        _userData = normalizeUser({ ...?_userData, ...updatedData });
        _marcarUsuarioActualizado();
        return null;
      }
      debugPrint('[PERFIL] HTTP ${res.statusCode} tokenPresente=${_token != null} body=${res.body}');
      return _describirError('actualizar perfil', res.statusCode, res.body);
    } catch (e) {
      return 'Error de conexión: $e';
    }
  }

  /// Indica si el usuario autenticado ya tiene una contraseña propia
  /// establecida (relevante para cuentas creadas por invitación o Google).
  /// Ante un error asume `true` para no bloquear el flujo normal.
  static Future<bool> tienePassword() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/huellitas/auth/tiene-password'),
        headers: authHeaders,
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['tiene_password'] == true;
      }
      return true; // Por defecto asumimos true para no bloquear
    } catch (_) {
      return true;
    }
  }

  /// Establece por primera vez la contraseña del usuario autenticado (para
  /// cuentas que hasta ahora solo entraban con Google o invitación).
  /// Devuelve null si salió bien, o un mensaje de error si falla.
  static Future<String?> establecerPassword(String nuevaPassword) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/huellitas/auth/establecer-password'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'nuevaPassword': nuevaPassword},
      );
      if (res.statusCode == 200) return null;
      return jsonDecode(res.body)['error'] ?? 'Error al establecer contraseña';
    } catch (e) {
      return 'Error de conexión: $e';
    }
  }

  /// Valida un token de acceso rápido leído de un código QR y, si es
  /// correcto, inicia sesión con él igual que un login normal. Devuelve
  /// null si salió bien, o un mensaje de error si el QR es inválido o expiró.
  static Future<String?> validarQrToken(String rawToken) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/huellitas/auth/qr/validar'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'rawToken': rawToken}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['token'] != null) {
        handleAuthResponse(res.body);
        return null; // Return null on success
      }
      return data['error'] ?? 'Código QR inválido o expirado';
    } catch (e) {
      return 'Error de conexión';
    }
  }

  /// Solicita el correo de recuperación de contraseña → null si se envió, mensaje de error si falla
  static Future<String?> solicitarReset(String email) async {
    try {
      final uri = Uri.parse('$baseUrl/huellitas/auth/solicitar-reset').replace(queryParameters: {'email': email});
      final res = await http.post(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return null;
      try {
        final body = jsonDecode(res.body);
        return body['error'] ?? body['message'] ?? 'No se pudo enviar el correo de recuperación.';
      } catch (_) {
        return 'Error del servidor (${res.statusCode}).';
      }
    } catch (e) {
      return 'Sin conexión. Verifica tu internet.';
    }
  }

  /// Verifica el código de 6 dígitos enviado por correo → null si OK (deja sesión iniciada)
  static Future<String?> verificarCodigo(String email, String codigo) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/huellitas/auth/verificar-codigo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'codigo': codigo}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        handleAuthResponse(res.body);
        return null;
      }
      try {
        final body = jsonDecode(res.body);
        return body['message'] ?? 'Código inválido o expirado.';
      } catch (_) {
        return 'Error del servidor (${res.statusCode}).';
      }
    } catch (e) {
      return 'Sin conexión. Verifica tu internet.';
    }
  }

  /// Reenvía el código de verificación de email → null si OK
  static Future<String?> reenviarCodigo(String email) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/huellitas/auth/reenviar-codigo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return null;
      try {
        final body = jsonDecode(res.body);
        return body['message'] ?? 'No se pudo reenviar el código.';
      } catch (_) {
        return 'Error del servidor (${res.statusCode}).';
      }
    } catch (e) {
      return 'Sin conexión. Verifica tu internet.';
    }
  }
}
