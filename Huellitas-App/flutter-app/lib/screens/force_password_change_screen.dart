import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../utils/nav_after_auth.dart';

/// Pantalla obligatoria para quien entra con la contraseña provisional que se
/// le envió por correo al ser invitado como miembro. No se puede saltar ni con
/// el botón atrás: hasta que no elija una contraseña propia no accede a la app.
/// Si ya la cambió antes (por ejemplo desde la web), esta pantalla no aparece.
class ForcePasswordChangeScreen extends StatefulWidget {
  const ForcePasswordChangeScreen({super.key});

  @override
  State<ForcePasswordChangeScreen> createState() => _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<ForcePasswordChangeScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nueva = _passCtrl.text.trim();

    if (nueva.length < 6) {
      setState(() => _error = 'La contraseña debe tener al menos 6 caracteres.');
      return;
    }
    if (nueva != _confirmCtrl.text.trim()) {
      setState(() => _error = 'Las dos contraseñas no coinciden.');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    final err = await AuthService.cambiarPasswordObligatorio(nueva);
    if (!mounted) return;

    if (err == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => destinoTrasAutenticar()),
      );
    } else {
      setState(() {
        _guardando = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombre = AuthService.userData?['nombre']?.toString() ?? '';

    // canPop en false: la contraseña provisional viajó por correo, así que no
    // debe quedar en uso si el usuario simplemente retrocede.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FBF9),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_reset, size: 64, color: Color(0xFF1B3022)),
                  const SizedBox(height: 20),
                  Text(
                    'Crea tu contraseña',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1B3022),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    nombre.isEmpty
                        ? 'Entraste con la contraseña provisional del correo. Elige una propia para continuar.'
                        : 'Hola $nombre, entraste con la contraseña provisional del correo. Elige una propia para continuar.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Nueva contraseña',
                      helperText: 'Mínimo 6 caracteres',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: _obscure,
                    onSubmitted: (_) => _guardando ? null : _guardar(),
                    decoration: const InputDecoration(
                      labelText: 'Repite la contraseña',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: GoogleFonts.inter(fontSize: 13, color: Colors.red.shade700),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _guardando ? null : _guardar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B3022),
                      foregroundColor: const Color(0xFFFFC107),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _guardando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFC107)),
                          )
                        : Text('Guardar y entrar',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
