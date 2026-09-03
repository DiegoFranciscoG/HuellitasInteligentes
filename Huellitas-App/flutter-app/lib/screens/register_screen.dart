import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../utils/nav_after_auth.dart';

/// Formulario de registro de un nuevo propietario: crea su cuenta y la
/// casa inicial (nombre y dirección opcional) que va a administrar.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _nombreCasaCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  bool _buscandoUbicacion = false;

  Future<void> _usarMiUbicacion() async {
    setState(() => _buscandoUbicacion = true);
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        _snack('Activa el permiso de ubicación para usar esta opción.');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Activa el GPS de tu dispositivo.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 10));

      // Nominatim (OpenStreetMap) no requiere API key, solo un User-Agent
      // identificable.
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}');
      final resp = await http.get(uri, headers: {'User-Agent': 'HuellitasInteligentesApp/1.0'});

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final direccion = data['display_name'] as String?;
        if (direccion != null && mounted) {
          setState(() => _direccionCtrl.text = direccion);
        } else {
          _snack('No se pudo determinar tu dirección.');
        }
      } else {
        _snack('No se pudo obtener la dirección. Intenta de nuevo.');
      }
    } catch (e) {
      _snack('No se pudo obtener tu ubicación.');
    } finally {
      if (mounted) setState(() => _buscandoUbicacion = false);
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final err = await AuthService.registerOwner(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
      nombre: _nombreCtrl.text.trim(),
      nombreCasa: _nombreCasaCtrl.text.trim(),
      direccion: _direccionCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (err == null) {
      if (AuthService.isLoggedIn) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => destinoTrasAutenticar()),
          (r) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro exitoso. Inicia sesión.')));
        Navigator.pop(context);
      }
    } else {
      _snack(err);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: const Color(0xFF1B3022),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1B3022)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Crea tu cuenta',
                    style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: const Color(0xFF1B3022))),
                const SizedBox(height: 8),
                Text('Únete como Propietario para conectar tus dispositivos.',
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600)),
                const SizedBox(height: 32),
                _buildField(
                  ctrl: _nombreCtrl,
                  label: 'Nombre completo',
                  icon: Icons.person_outline,
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 14),
                _buildField(
                  ctrl: _emailCtrl,
                  label: 'Correo Electrónico',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v!.contains('@') ? null : 'Correo inválido',
                ),
                const SizedBox(height: 14),
                _buildField(
                  ctrl: _passCtrl,
                  label: 'Contraseña (mín 6 chars)',
                  icon: Icons.lock_outline,
                  obscure: true,
                  validator: (v) => v!.length < 6 ? 'Mínimo 6 caracteres' : null,
                ),
                const SizedBox(height: 14),
                _buildField(
                  ctrl: _nombreCasaCtrl,
                  label: 'Nombre de tu Casa',
                  icon: Icons.home_outlined,
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 14),
                _buildField(
                  ctrl: _direccionCtrl,
                  label: 'Dirección (Opcional)',
                  icon: Icons.location_on_outlined,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _buscandoUbicacion ? null : _usarMiUbicacion,
                    icon: _buscandoUbicacion
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B3022)),
                          )
                        : const Icon(Icons.my_location, size: 18, color: Color(0xFF1B3022)),
                    label: Text(
                      _buscandoUbicacion ? 'Buscando...' : 'Usar mi ubicación actual',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1B3022)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B3022),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(width: 24, height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : Text('Registrarse', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: StatefulBuilder(builder: (ctx, setSt) {
        return TextFormField(
          controller: ctrl,
          obscureText: obscure ? _obscure : false,
          keyboardType: keyboardType,
          // Fondo del campo es blanco y el tema global es oscuro: sin color
          // explícito el texto quedaba blanco sobre blanco (invisible).
          style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF191C1B)),
          cursorColor: const Color(0xFF1B3022),
          validator: validator,
          decoration: InputDecoration(
            hintText: label,
            hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
            prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
            suffixIcon: obscure
                ? IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey.shade400, size: 20),
                    onPressed: () => setSt(() => _obscure = !_obscure),
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
}
