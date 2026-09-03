import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/device_model.dart';
import 'auth_service.dart';

/// Servicio central de acceso a la API de Huellitas Inteligentes.
///
/// Concentra las llamadas HTTP al backend (dashboard de la casa, cámaras,
/// dispositivos IoT del ESP32) y expone su resultado como estado observable
/// vía [ChangeNotifier], para que las pantallas se repinten solas cuando
/// llega una respuesta nueva. Los controles de los actuadores (LED,
/// ventilador, servos, bomba, stepper) aplican una actualización optimista
/// en el estado local antes de confirmar con el servidor, para que la UI
/// responda al instante.
class ApiService extends ChangeNotifier {
  /// URL base del backend (`API_URL` en `.env`, o `http://localhost:8087/api`
  /// si no está configurada).
  static String get baseUrl => dotenv.env['API_URL'] ?? 'http://localhost:8087/api';

  /// El backend guarda las imágenes (posts, avatares, mascotas) como rutas
  /// relativas (ej. `/api/huellitas/media/xxx.jpg`), esperando que el
  /// cliente anteponga el host — igual que hace `MediaUrlPipe` en
  /// `huellitas-web`. Pasar la ruta relativa directo a `Image.network` falla
  /// con "No host specified in URI".
  static String? resolveMediaUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('data:image')) {
      return url;
    }
    final origin = baseUrl.replaceFirst(RegExp(r'/api.*$'), '');
    return origin + (url.startsWith('/') ? url : '/$url');
  }

  DeviceState? _deviceState;
  bool _isLoading = true;
  String? _errorMessage;

  /// Último estado conocido de los sensores/actuadores del ESP32, o `null`
  /// si todavía no se ha cargado ninguno.
  DeviceState? get deviceState => _deviceState;
  /// `true` mientras hay una petición en curso.
  bool get isLoading => _isLoading;
  /// Mensaje del último error de red o del servidor, o `null` si no hay.
  String? get errorMessage => _errorMessage;
  /// `true` si el modo automático del dispositivo está activo.
  bool get isAutomaticMode => _deviceState?.automaticMode ?? true;

  /// Borra todo lo que este servicio tenía en memoria (mascotas, cámaras,
  /// dispositivos, dashboards). Este servicio vive durante toda la sesión de
  /// la app, así que si al cerrar sesión no se limpia, la siguiente cuenta
  /// que inicie sesión ve por un instante — o hasta que la próxima petición
  /// falle — los datos de la cuenta anterior (mascotas, cámaras ajenas).
  void clearAll() {
    _dashboardData = null;
    _adminDashboardData = null;
    _adminDevicesData = null;
    _camarasData = null;
    _deviceState = null;
    _errorMessage = null;
    notifyListeners();
  }

  // ============================================
  // OBTENER DASHBOARD DE LA CASA
  // ============================================
  Map<String, dynamic>? _dashboardData;
  /// Datos del dashboard de la casa del propietario (mascotas, plan, casa).
  Map<String, dynamic>? get dashboardData => _dashboardData;

  Map<String, dynamic>? _adminDashboardData;
  /// Datos del dashboard general de administración.
  Map<String, dynamic>? get adminDashboardData => _adminDashboardData;

  List<dynamic>? _adminDevicesData;
  /// Lista de dispositivos IoT registrados, para el panel de administración.
  List<dynamic>? get adminDevicesData => _adminDevicesData;

  List<dynamic>? _camarasData;
  /// Lista de cámaras registradas en la casa actual.
  List<dynamic>? get camarasData => _camarasData;

  /// Carga las cámaras de la casa [casaId] y actualiza [camarasData].
  Future<void> fetchCamaras(int casaId, String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/huellitas/camaras/casa/$casaId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        // utf8.decode para que los nombres con tildes (cámara y mascota)
        // no lleguen con caracteres rotos.
        _camarasData = jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        debugPrint('Error fetchCamaras: ${response.statusCode}');
        // Si falla, no dejamos las cámaras de la casa/cuenta anterior
        // mostrándose como si fueran las de esta.
        _camarasData = null;
      }
    } catch (e) {
      debugPrint('Error de conexión en fetchCamaras: $e');
      _camarasData = null;
    } finally {
      notifyListeners();
    }
  }

  /// Marca qué mascota vigila una cámara. `perroId` en null quita la asignación.
  Future<void> asignarMascotaCamara(int camaraId, int? perroId, String token) async {
    final response = await http.put(
      Uri.parse('$baseUrl/huellitas/camaras/$camaraId/mascota'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'perroId': perroId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Error al asignar la mascota a la cámara');
    }

    final actualizada = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final lista = _camarasData;
    if (lista != null) {
      final i = lista.indexWhere((c) => c['id'] == camaraId);
      if (i >= 0) lista[i] = actualizada;
      notifyListeners();
    }
  }

  /// Elimina la cámara [camaraId]. Lanza una excepción si el servidor
  /// responde con un código distinto de 200/204.
  Future<void> deleteCamara(int camaraId, String token) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/huellitas/camaras/$camaraId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Error al eliminar la cámara');
    }
  }

  /// Carga el dashboard de la casa [casaId] (mascotas, plan, resumen de
  /// dispositivos) y actualiza [dashboardData] e [isLoading].
  Future<void> fetchDashboard(int casaId, String token) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await http.get(
        Uri.parse('$baseUrl/huellitas/casa/$casaId/dashboard'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        _dashboardData = jsonDecode(utf8.decode(response.bodyBytes));
        _errorMessage = null;
      } else {
        _errorMessage = 'Error Dashboard: ${response.statusCode}';
        // Si falla, no dejamos el dashboard (mascotas incluidas) de la
        // cuenta/casa anterior mostrándose como si fuera de esta cuenta.
        _dashboardData = null;
      }
    } catch (e) {
      _errorMessage = 'Error de conexión (Dashboard): $e';
      _dashboardData = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carga el dashboard general de administración y actualiza
  /// [adminDashboardData].
  Future<void> fetchAdminDashboard(String token) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await http.get(
        Uri.parse('$baseUrl/huellitas/admin/dashboard'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        _adminDashboardData = jsonDecode(utf8.decode(response.bodyBytes));
        _errorMessage = null;
      } else {
        _errorMessage = 'Error Admin Dashboard: ${response.statusCode}';
        _adminDashboardData = null;
      }
    } catch (e) {
      _errorMessage = 'Error de conexión (Admin Dashboard): $e';
      _adminDashboardData = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carga la lista de dispositivos IoT registrados y actualiza
  /// [adminDevicesData], para el panel de administración.
  Future<void> fetchAdminDevices(String token) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await http.get(
        Uri.parse('$baseUrl/huellitas/admin/iot/dispositivos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        _adminDevicesData = jsonDecode(utf8.decode(response.bodyBytes));
        _errorMessage = null;
      } else {
        _errorMessage = 'Error Admin Devices: ${response.statusCode}';
        _adminDevicesData = null;
      }
    } catch (e) {
      _errorMessage = 'Error de conexión (Admin Devices): $e';
      _adminDevicesData = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ============================================
  // OBTENER DISPOSITIVOS
  // ============================================
  /// Pide al backend el estado actual del dispositivo ESP32 (sensores y
  /// actuadores) y actualiza [deviceState].
  Future<void> fetchDevices() async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await http.get(
        Uri.parse('$baseUrl/devices'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _deviceState = DeviceState.fromJson(data);
        _errorMessage = null;
      } else {
        _errorMessage = 'Error: ${response.statusCode}';
      }
    } catch (e) {
      _errorMessage = 'Error de conexión: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // La presencia va aparte porque `/devices` es público —lo consulta el
    // propio firmware— mientras que saber de quién son los aparatos exige
    // sesión. Se pide después para que la pantalla sepa si puede desbloquear.
    final token = AuthService.token;
    if (token != null) {
      await fetchEstadoIot(token);
    }
  }

  // ============================================
  // PRESENCIA DEL IoT DE LA VIVIENDA
  // ============================================

  Map<String, dynamic>? _estadoIot;

  /// Cuántos aparatos tiene dados de alta esta vivienda.
  int get iotTotal => (_estadoIot?['total'] as num?)?.toInt() ?? 0;

  /// `true` si al menos uno dio señal dentro de la ventana de presencia.
  bool get iotConectado => _estadoIot?['conectado'] == true;

  /// Segundos que el backend espera antes de dar un aparato por desconectado.
  int get iotVentanaSegundos => (_estadoIot?['ventanaSegundos'] as num?)?.toInt() ?? 30;

  /// `true` mientras no se ha podido leer el estado todavía: en ese caso no
  /// conviene bloquear nada, para no mostrar un aviso falso en la primera carga.
  bool get iotEstadoDesconocido => _estadoIot == null;

  /// Consulta al backend si la vivienda tiene IoT y si está en línea.
  ///
  /// Un fallo se ignora a propósito y conserva el último estado conocido: un
  /// sondeo perdido no debe bloquear una pantalla que estaba funcionando.
  ///
  /// @param token sesión del usuario, igual que en el resto de llamadas autenticadas.
  Future<void> fetchEstadoIot(String token) async {
    try {
      final r = await http.get(
        Uri.parse('$baseUrl/huellitas/dispositivo/estado'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        _estadoIot = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        notifyListeners();
      }
    } catch (_) {
      // Se conserva el último estado conocido.
    }
  }

  // ============================================
  // CAMBIAR MODO AUTOMÁTICO
  // ============================================
  /// Activa o desactiva el modo automático del dispositivo. Aplica el
  /// cambio de forma optimista en el estado local y lo revierte recargando
  /// desde el servidor si la petición falla.
  Future<void> toggleAutomaticMode() async {
    try {
      final newState = !isAutomaticMode;
      
      //  Actualización optimista
      if (_deviceState != null) {
        _deviceState = DeviceState(
          servo: _deviceState!.servo,
          servo2: _deviceState!.servo2,
          servo3: _deviceState!.servo3,
          stepper: _deviceState!.stepper,
          pump: _deviceState!.pump,
          motion: _deviceState!.motion,
          led: _deviceState!.led,
          fan: _deviceState!.fan,
          dht: _deviceState!.dht,
          mq135: _deviceState!.mq135,
          water: _deviceState!.water,
          ultrasonic: _deviceState!.ultrasonic,
          automaticMode: newState,
        );
        notifyListeners();
      }

      final response = await http.post(
        Uri.parse('$baseUrl/automatic-mode'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(newState),
      );

      if (response.statusCode == 200) {
        await fetchDevices();
      }
    } catch (e) {
      debugPrint('Error toggling automatic mode: $e');
      await fetchDevices(); // Revertir en caso de error
    }
  }

  // ============================================
  // CONTROLAR LED (CON ACTUALIZACIÓN OPTIMISTA)
  // ============================================
  /// Enciende o apaga el LED del cuarto [room] (1 o 2). Aplica el cambio de
  /// forma optimista en el estado local y revierte a [fetchDevices] si la
  /// petición al servidor falla.
  Future<void> toggleLed(int room) async {
    if (_deviceState == null) return;

    final oldState = _deviceState!;
    final oldLed = oldState.led;

    //  Nuevo estado local
    final newLed = LedState(
      room1Led: room == 1 ? !oldLed.room1Led : oldLed.room1Led,
      room2Led: room == 2 ? !oldLed.room2Led : oldLed.room2Led,
      automatic: oldLed.automatic,
    );

    //  Actualización optimista
    _deviceState = DeviceState(
      servo: oldState.servo,
      servo2: oldState.servo2,
      servo3: oldState.servo3,
      stepper: oldState.stepper,
      pump: oldState.pump,
      motion: oldState.motion,
      led: newLed,
      fan: oldState.fan,
      dht: oldState.dht,
      mq135: oldState.mq135,
      water: oldState.water,
      ultrasonic: oldState.ultrasonic,
      automaticMode: oldState.automaticMode,
    );
    notifyListeners();

    final request = {
      'room1Led': newLed.room1Led,
      'room2Led': newLed.room2Led,
      'automatic': newLed.automatic,
    };

    try {
      await http.post(
        Uri.parse('$baseUrl/led'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request),
      );
      //  Solo sincronizar sin recargar todo
      await _syncDeviceState();
    } catch (e) {
      debugPrint('Error toggling LED: $e');
      await fetchDevices(); // Revertir en caso de error
    }
  }

  // ============================================
  // CONTROLAR VENTILADOR
  /// Enciende o apaga el ventilador del cuarto [room] (1 o 2), con
  /// actualización optimista igual que [toggleLed].
  Future<void> toggleFan(int room) async {
    if (_deviceState == null) return;

    final oldState = _deviceState!;
    final oldFan = oldState.fan;

    final newFan = FanState(
      fan1: room == 1 ? !oldFan.fan1 : oldFan.fan1,
      fan2: room == 2 ? !oldFan.fan2 : oldFan.fan2,
      automatic: oldFan.automatic,
    );

    _deviceState = DeviceState(
      servo: oldState.servo,
      servo2: oldState.servo2,
      servo3: oldState.servo3,
      stepper: oldState.stepper,
      pump: oldState.pump,
      motion: oldState.motion,
      led: oldState.led,
      fan: newFan,
      dht: oldState.dht,
      mq135: oldState.mq135,
      water: oldState.water,
      ultrasonic: oldState.ultrasonic,
      automaticMode: oldState.automaticMode,
    );
    notifyListeners();

    final request = {
      'fan1': newFan.fan1,
      'fan2': newFan.fan2,
      'automatic': newFan.automatic,
    };

    try {
      await http.post(
        Uri.parse('$baseUrl/fan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request),
      );
      await _syncDeviceState();
    } catch (e) {
      debugPrint('Error toggling fan: $e');
      await fetchDevices();
    }
  }

  // ============================================
  // CONTROLAR SERVO
  /// Mueve el servo [room] al ángulo [angle], con actualización optimista
  /// igual que [toggleLed]. El 1 y el 2 son los de las habitaciones; el 3
  /// orienta la cámara y el backend le recorta el ángulo a 0–180.
  Future<void> changeServo(int room, int angle) async {
    if (_deviceState == null) return;

    final oldState = _deviceState!;

    //  Actualizar servo
    if (room == 1) {
      _deviceState = DeviceState(
        servo: ServoState(angle: angle, status: 'OK'),
        servo2: oldState.servo2,
        servo3: oldState.servo3,
        stepper: oldState.stepper,
        pump: oldState.pump,
        motion: oldState.motion,
        led: oldState.led,
        fan: oldState.fan,
        dht: oldState.dht,
        mq135: oldState.mq135,
        water: oldState.water,
        ultrasonic: oldState.ultrasonic,
        automaticMode: oldState.automaticMode,
      );
    } else if (room == 3) {
      _deviceState = DeviceState(
        servo: oldState.servo,
        servo2: oldState.servo2,
        servo3: Servo3State(angle: angle, status: 'OK'),
        stepper: oldState.stepper,
        pump: oldState.pump,
        motion: oldState.motion,
        led: oldState.led,
        fan: oldState.fan,
        dht: oldState.dht,
        mq135: oldState.mq135,
        water: oldState.water,
        ultrasonic: oldState.ultrasonic,
        automaticMode: oldState.automaticMode,
      );
    } else {
      _deviceState = DeviceState(
        servo: oldState.servo,
        servo2: Servo2State(angle: angle),
        servo3: oldState.servo3,
        stepper: oldState.stepper,
        pump: oldState.pump,
        motion: oldState.motion,
        led: oldState.led,
        fan: oldState.fan,
        dht: oldState.dht,
        mq135: oldState.mq135,
        water: oldState.water,
        ultrasonic: oldState.ultrasonic,
        automaticMode: oldState.automaticMode,
      );
    }
    notifyListeners();

    final endpoint = switch (room) {
      1 => 'servo',
      3 => 'servo3',
      _ => 'servo2',
    };
    final request = {'angle': angle};

    try {
      await http.post(
        Uri.parse('$baseUrl/$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request),
      );
      await _syncDeviceState();
    } catch (e) {
      debugPrint('Error changing servo: $e');
      await fetchDevices();
    }
  }

  // ============================================
  // CONTROLAR BOMBA
  // ============================================
  /// Enciende o apaga la bomba de agua/comida, con actualización optimista
  /// igual que [toggleLed].
  Future<void> togglePump() async {
    if (_deviceState == null) return;

    final oldState = _deviceState!;
    final newPumpState = !oldState.pump.enabled;

    _deviceState = DeviceState(
      servo: oldState.servo,
      servo2: oldState.servo2,
      servo3: oldState.servo3,
      stepper: oldState.stepper,
      pump: PumpState(enabled: newPumpState),
      motion: oldState.motion,
      led: oldState.led,
      fan: oldState.fan,
      dht: oldState.dht,
      mq135: oldState.mq135,
      water: oldState.water,
      ultrasonic: oldState.ultrasonic,
      automaticMode: oldState.automaticMode,
    );
    notifyListeners();

    final request = {'enabled': newPumpState};

    try {
      await http.post(
        Uri.parse('$baseUrl/pump'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request),
      );
      await _syncDeviceState();
    } catch (e) {
      debugPrint('Error toggling pump: $e');
      await fetchDevices();
    }
  }

  // ============================================
  // CONTROLAR STEPPER
  // ============================================
  /// Mueve el motor paso a paso (dispensador) a la posición [position], con
  /// actualización optimista igual que [toggleLed].
  Future<void> changeStepper(int position) async {
    if (_deviceState == null) return;

    final oldState = _deviceState!;

    _deviceState = DeviceState(
      servo: oldState.servo,
      servo2: oldState.servo2,
      servo3: oldState.servo3,
      stepper: StepperState(position: position),
      pump: oldState.pump,
      motion: oldState.motion,
      led: oldState.led,
      fan: oldState.fan,
      dht: oldState.dht,
      mq135: oldState.mq135,
      water: oldState.water,
      ultrasonic: oldState.ultrasonic,
      automaticMode: oldState.automaticMode,
    );
    notifyListeners();

    final request = {'position': position};

    try {
      await http.post(
        Uri.parse('$baseUrl/stepper'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request),
      );
      await _syncDeviceState();
    } catch (e) {
      debugPrint('Error changing stepper: $e');
      await fetchDevices();
    }
  }

  // ============================================
  //  SINCRONIZAR SOLO LOS VALORES QUE CAMBIARON
  // ============================================
  Future<void> _syncDeviceState() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/devices'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newState = DeviceState.fromJson(data);
        
        //  Solo actualizar si hay cambios reales
        if (_deviceState != newState) {
          _deviceState = newState;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error syncing device state: $e');
    }
  }

  // ============================================
  // REFRESH MANUAL (pull-to-refresh)
  // ============================================
  /// Vuelve a pedir el estado del dispositivo al backend; pensado para el
  /// gesto de "pull-to-refresh" en las pantallas de dispositivos.
  Future<void> refreshDevices() async {
    await fetchDevices();
  }

  // ============================================
  // CODIGO DE VINCULACION DE LA VIVIENDA
  // ============================================
  /// Código de vinculación (X-Device-Code) de la casa [casaId], o `null` si
  /// falla la petición.
  Future<String?> obtenerCodigoVivienda(int casaId) async {
    final token = AuthService.token;
    if (token == null) return null;
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/huellitas/casa/$casaId/codigo-vinculacion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return data['codigoVinculacion'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Error obteniendo código de vivienda: $e');
      return null;
    }
  }

  /// Regenera el código de vinculación de la casa [casaId]. Los dispositivos
  /// con el código anterior dejan de ser aceptados hasta que se actualicen.
  Future<String?> regenerarCodigoVivienda(int casaId) async {
    final token = AuthService.token;
    if (token == null) return null;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/huellitas/casa/$casaId/codigo-vinculacion/regenerar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return data['codigoVinculacion'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Error regenerando código de vivienda: $e');
      return null;
    }
  }
}