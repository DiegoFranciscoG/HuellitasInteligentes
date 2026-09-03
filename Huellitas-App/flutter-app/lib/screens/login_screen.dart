import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../utils/nav_after_auth.dart';
import 'register_screen.dart';
import 'qr_scanner_screen.dart';
import 'forgot_password_screen.dart';
import 'verify_email_screen.dart';

/// Etiqueta de compilación visible en el login. Cámbiala en cada entrega para
/// verificar sin dudas qué versión está corriendo el dispositivo.
const String kBuildTag = 'NOCHE-27';

// Web Client ID de Google Cloud Console (el mismo que usa el backend)
const _googleServerClientId =
    '711330016273-gou6a7ur6jvfmt9vdlq6ipfo04kk483t.apps.googleusercontent.com';

/// Pantalla de inicio de sesión: permite entrar con correo/contraseña,
/// escaneando un QR de acceso rápido (miembros invitados), o con Google o
/// Facebook, y enlaza a registro, recuperación de contraseña y verificación
/// de correo.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  // ─── Email / Password ──────────────────────────────────────────────────────
  Future<void> _loginEmail() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      _snack('Ingresa correo y contraseña.');
      return;
    }
    setState(() => _loading = true);
    final err = await AuthService.loginEmail(_emailCtrl.text.trim(), _passCtrl.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (err == null) {
      _goHome();
    } else {
      _snack(err);
    }
  }

  Future<void> _scanQR() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    
    if (result != null && result.isNotEmpty) {
      setState(() => _loading = true);
      final error = await AuthService.validarQrToken(result);
      if (!mounted) return;
      setState(() => _loading = false);
      
      if (error == null) {
        _goHome();
      } else {
        _snack(error);
      }
    }
  }

  // ─── Google Sign-In nativo ─────────────────────────────────────────────────
  Future<void> _loginGoogle() async {
    setState(() => _loading = true);
    try {
      // Inicializa con el Server Client ID del backend para obtener idToken
      await GoogleSignIn.instance.initialize(serverClientId: _googleServerClientId);
      final account = await GoogleSignIn.instance.authenticate();
      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null) {
        _snack('No se pudo obtener el token de Google.');
        setState(() => _loading = false);
        return;
      }

      final err = await AuthService.loginGoogle(idToken);
      if (!mounted) return;
      setState(() => _loading = false);
      if (err == null) {
        _goHome();
      } else {
        _snack(err);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Error Google Sign-In: $e');
    }
  }

  // ─── Facebook (abre el navegador con el OAuth del backend) ────────────────
  //
  // El backend hace el intercambio código→token con Facebook (misma app y
  // credenciales que usa la web) y al terminar tiene que entregarle el JWT a
  // quien empezó el flujo. Para la web eso es fácil: redirige a su propia
  // URL. Para el celular no hay "su propia URL" a la que redirigir —son
  // procesos separados—, así que en vez de eso el backend abre el enlace
  // `huellitas://oauth-callback`, que Android le entrega de vuelta a esta
  // misma app. `?platform=app` es lo que le dice al backend cuál de los dos
  // casos es este (ver AuthController.facebookLogin/facebookCallback).
  Future<void> _loginFacebook() async {
    final base = AuthService.baseUrl.replaceAll('/api', '');
    final uri = Uri.parse('$base/api/huellitas/auth/facebook/login?platform=app');

    if (!await canLaunchUrl(uri)) {
      _snack('No se pudo abrir el navegador.');
      return;
    }

    setState(() => _loading = true);

    // Se suscribe ANTES de abrir el navegador: si se hiciera después, un
    // regreso muy rápido podría llegar antes de que el listener exista.
    final enlaces = AppLinks();
    final futuroEnlace = enlaces.uriLinkStream
        .firstWhere((u) => u.scheme == 'huellitas' && u.host == 'oauth-callback')
        .timeout(const Duration(minutes: 3));

    await launchUrl(uri, mode: LaunchMode.externalApplication);

    try {
      final resultado = await futuroEnlace;
      final token = resultado.queryParameters['token'];
      final error = resultado.queryParameters['error'];

      if (!mounted) return;

      if (token != null) {
        final ok = await AuthService.completarLoginPorEnlace(token);
        if (!mounted) return;
        setState(() => _loading = false);
        if (ok) {
          _goHome();
        } else {
          _snack('No se pudo validar la sesión de Facebook. Inténtalo de nuevo.');
        }
      } else {
        setState(() => _loading = false);
        _snack(error == 'facebook_denied'
            ? 'Inicio de sesión con Facebook cancelado.'
            : 'No se pudo completar el inicio de sesión con Facebook.');
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Se agotó el tiempo de espera. Inténtalo de nuevo.');
    }
  }

  /// Entra a la app, salvo que el usuario siga con la contraseña provisional
  /// del correo (primero tiene que elegir una propia) o no tenga vivienda
  /// (un miembro recién dado de baja, o una cuenta nueva de Google/Facebook)
  /// — ver `destinoTrasAutenticar()`.
  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destinoTrasAutenticar()),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: const Color(0xFF1B3022),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B3022).withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.pets, size: 52, color: Color(0xFF1B3022)),
                ),
              ),
              const SizedBox(height: 28),
              Text('Bienvenido a', style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade600)),
              Text('Huellitas Pro',
                  style: GoogleFonts.outfit(fontSize: 34, fontWeight: FontWeight.bold, color: const Color(0xFF1B3022))),
              const SizedBox(height: 6),
              Text('El ecosistema inteligente para tu mascota.',
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade500)),
              const SizedBox(height: 40),
              _field(_emailCtrl, 'Correo Electrónico', Icons.mail_outline, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 14),
              _field(_passCtrl, 'Contraseña', Icons.lock_outline, obscure: true),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                  ),
                  child: Text('¿Olvidaste tu contraseña?',
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1B3022), fontWeight: FontWeight.w500)),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF9A826),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: _loading ? null : _loginEmail,
                  child: _loading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Ingresar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1B3022),
                    side: const BorderSide(color: Color(0xFF1B3022)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _loading ? null : _scanQR,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Ingresa con QR (Miembro)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 32),
              Row(children: [
                Expanded(child: Divider(color: Colors.grey.shade300)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('o continúa con', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
                ),
                Expanded(child: Divider(color: Colors.grey.shade300)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _socialBtn('Google', Icons.g_mobiledata, const Color(0xFFDB4437), _loginGoogle)),
                const SizedBox(width: 12),
                Expanded(child: _socialBtn('Facebook', Icons.facebook, const Color(0xFF1877F2), _loginFacebook)),
              ]),
              const SizedBox(height: 32),
              Center(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('¿No tienes cuenta? ', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600)),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RegisterScreen()),
                      );
                    },
                    child: Text('Regístrate',
                        style: GoogleFonts.inter(
                            fontSize: 14, fontWeight: FontWeight.bold,
                            color: const Color(0xFF1B3022), decoration: TextDecoration.underline)),
                  ),
                ]),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => VerifyEmailScreen(email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim())),
                  ),
                  child: Text('¿No verificaste tu correo? Verificar ahora',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                ),
              ),
              // Marcador de build: sirve para confirmar de un vistazo que el
              // teléfono está corriendo la versión recién instalada y no una
              // copia antigua en memoria u otro perfil de Android.
              Center(
                child: Text('build $kBuildTag',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {bool obscure = false, TextInputType? keyboardType}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: StatefulBuilder(builder: (ctx, setSt) {
        return TextField(
          controller: ctrl,
          obscureText: obscure ? _obscure : false,
          keyboardType: keyboardType,
          // Color explícito: el campo tiene fondo blanco y el tema global de la
          // app es oscuro, así que sin esto el texto salía blanco sobre blanco.
          style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF191C1B)),
          cursorColor: const Color(0xFF1B3022),
          decoration: InputDecoration(
            hintText: label,
            hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
            prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
            suffixIcon: obscure
                ? IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey.shade400, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            filled: true, fillColor: Colors.transparent,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        );
      }),
    );
  }

  Widget _socialBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: _loading ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF1B3022))),
        ]),
      ),
    );
  }
}
