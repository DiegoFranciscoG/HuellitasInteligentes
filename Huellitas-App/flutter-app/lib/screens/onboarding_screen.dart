import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import 'app_shell.dart';
import 'login_screen.dart';

const _verde = Color(0xFF1B3022);

/// Pantalla que recibe a una cuenta sin vivienda propia: un miembro recién
/// dado de baja (queda como PROPIETARIO sin `casa_id`) o una cuenta nueva
/// creada por Google/Facebook que todavía no completó el registro.
///
/// Antes de esta pantalla, esas cuentas entraban directo a [AppShell] y se
/// quedaban con un panel sin datos que mostrar —sin ninguna explicación—,
/// porque no había a dónde más ir. Ver [AuthService.needsOnboarding] y
/// `destinoTrasAutenticar()`.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  final _casaCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _ciudadCtrl = TextEditingController();

  bool _cargando = false;
  bool _buscandoUbicacion = false;
  String? _error;
  bool _sesionInvalida = false;
  String? _casaAnterior;
  bool _consultandoCasaAnterior = true;
  double? _latitud;
  double? _longitud;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: AuthService.userData?['nombre']?.toString() ?? '');
    _cargarCasaAnterior();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _casaCtrl.dispose();
    _direccionCtrl.dispose();
    _ciudadCtrl.dispose();
    super.dispose();
  }

  /// Si `casa_anterior_id` está presente, esta cuenta llegó aquí por haber
  /// sido removida de una vivienda, no por registrarse de cero: se pide el
  /// nombre para poder decirlo explícitamente.
  Future<void> _cargarCasaAnterior() async {
    if (AuthService.casaAnteriorId == null) {
      setState(() => _consultandoCasaAnterior = false);
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('${AuthService.baseUrl}/huellitas/auth/casa-anterior'),
        headers: AuthService.authHeaders,
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['ok'] == true) _casaAnterior = data['nombre'] as String?;
      }
    } catch (_) {
      // Sin esto la pantalla igual funciona: solo no muestra el aviso.
    } finally {
      if (mounted) setState(() => _consultandoCasaAnterior = false);
    }
  }

  /// Ubica al usuario por GPS y rellena dirección/ciudad con la geocodificación
  /// inversa de Nominatim (el mismo servicio, sin API key, que usa el mapa de
  /// la web) — para no obligarlo a escribir su dirección a mano.
  Future<void> _usarMiUbicacion() async {
    setState(() {
      _buscandoUbicacion = true;
      _error = null;
    });
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        setState(() => _error = 'Necesitas dar permiso de ubicación para usar esta opción.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 10));
      _latitud = pos.latitude;
      _longitud = pos.longitude;

      final res = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse'
            '?lat=${pos.latitude}&lon=${pos.longitude}&format=json'),
        headers: {'User-Agent': 'HuellitasInteligentes/1.0'},
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        final ciudad = address?['city'] ?? address?['town'] ?? address?['village'] ?? address?['county'];
        final nombreCompleto = (data['display_name'] as String?)?.split(',').take(2).join(',');

        setState(() {
          if (nombreCompleto != null && nombreCompleto.isNotEmpty) _direccionCtrl.text = nombreCompleto;
          if (ciudad != null) _ciudadCtrl.text = ciudad.toString();
        });
      } else {
        setState(() => _error = 'Se obtuvo tu ubicación, pero no se pudo resolver la dirección. Escríbela manualmente.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo obtener tu ubicación. Verifica el GPS o escribe la dirección manualmente.');
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  Future<http.Response> _postCompletarOnboarding() {
    return http.post(
      Uri.parse('${AuthService.baseUrl}/huellitas/auth/completar-onboarding'),
      headers: AuthService.authHeaders,
      body: jsonEncode({
        'nombre': _nombreCtrl.text.trim(),
        'casa_nombre': _casaCtrl.text.trim(),
        'direccion': _direccionCtrl.text.trim(),
        if (_ciudadCtrl.text.trim().isNotEmpty) 'ciudad': _ciudadCtrl.text.trim(),
        if (_latitud != null) 'latitud': _latitud.toString(),
        if (_longitud != null) 'longitud': _longitud.toString(),
      }),
    ).timeout(const Duration(seconds: 12));
  }

  Future<void> _crearVivienda() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
      _sesionInvalida = false;
    });
    try {
      var res = await _postCompletarOnboarding();

      // Un 401 aquí no significa necesariamente que la sesión esté vencida:
      // si el token vino de un login por enlace (Facebook), puede que se
      // mandara la petición antes de que la app terminara de confirmarlo.
      // Antes de rendirse, se comprueba la sesión con /me y, si sigue siendo
      // válida, se reintenta una vez —así una carrera pasajera no obliga a
      // cerrar sesión y volver a entrar por nada.
      if (res.statusCode == 401) {
        final sigueValida = await AuthService.refrescarUsuario();
        if (!mounted) return;
        if (sigueValida) {
          res = await _postCompletarOnboarding();
        }
      }

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        AuthService.handleAuthResponse(jsonEncode(data));
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AppShell()),
        );
        return;
      }
      if (res.statusCode == 401) {
        setState(() {
          _error = 'Tu sesión no es válida. Vuelve a iniciar sesión e inténtalo de nuevo.';
          _sesionInvalida = true;
        });
        return;
      }
      final body = jsonDecode(res.body);
      setState(() => _error = body['message'] ?? 'No se pudo crear la vivienda.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Sin conexión. Verifica tu internet e inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _cerrarSesionYEsperar() {
    AuthService.logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAED),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _verde, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.home_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 20),
                Text('Completa tu registro',
                    style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.bold, color: _verde)),
                const SizedBox(height: 6),
                Text('Necesitamos un par de datos para configurar tu hogar inteligente.',
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade700)),

                if (_consultandoCasaAnterior) ...[
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ],

                if (!_consultandoCasaAnterior && _casaAnterior != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6E5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF0C674)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fuiste removido de "$_casaAnterior"',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF8a6a00))),
                        const SizedBox(height: 6),
                        Text(
                          'Puedes crear tu propia vivienda ahora completando el formulario, '
                          'o cerrar sesión y esperar a que el propietario vuelva a agregarte.',
                          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF5a4a1f), height: 1.4),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _cerrarSesionYEsperar,
                          child: Text('Cerrar sesión y esperar',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF8a6a00),
                                decoration: TextDecoration.underline,
                              )),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_error!, style: GoogleFonts.inter(fontSize: 13, color: Colors.red.shade800)),
                        if (_sesionInvalida) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: _cerrarSesionYEsperar,
                            child: Text('Volver a iniciar sesión',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade900,
                                  decoration: TextDecoration.underline,
                                )),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                _campo(_nombreCtrl, 'Tu nombre completo', Icons.person_outline, requerido: true),
                const SizedBox(height: 14),
                _campo(_casaCtrl, 'Nombre de tu hogar', Icons.home_outlined, requerido: true),
                const SizedBox(height: 14),
                _campo(_direccionCtrl, 'Dirección', Icons.location_on_outlined, requerido: true),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _buscandoUbicacion ? null : _usarMiUbicacion,
                    icon: _buscandoUbicacion
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _verde))
                        : const Icon(Icons.my_location, size: 16, color: _verde),
                    label: Text(
                      _buscandoUbicacion ? 'Buscando ubicación...' : 'Usar mi ubicación actual',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _verde),
                    ),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                  ),
                ),
                const SizedBox(height: 6),
                _campo(_ciudadCtrl, 'Ciudad (opcional)', Icons.map_outlined, requerido: false),

                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _cargando ? null : _crearVivienda,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _verde,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _cargando
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Crear mi vivienda',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
                ),

                if (_casaAnterior == null && !_consultandoCasaAnterior) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _cargando ? null : _cerrarSesionYEsperar,
                    child: Text('Cerrar sesión', style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 13)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _campo(TextEditingController ctrl, String label, IconData icono, {required bool requerido}) {
    return TextFormField(
      controller: ctrl,
      style: GoogleFonts.inter(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icono, size: 20, color: Colors.grey.shade600),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      ),
      validator: requerido
          ? (v) => (v == null || v.trim().isEmpty) ? 'Este campo es obligatorio' : null
          : null,
    );
  }
}
