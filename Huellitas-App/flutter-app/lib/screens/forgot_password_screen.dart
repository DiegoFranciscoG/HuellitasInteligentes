import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';

/// Formulario de recuperación de contraseña: pide el correo del usuario y
/// solicita al backend el envío del enlace de restablecimiento.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _enviado = false;

  Future<void> _enviar() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Ingresa un correo válido.');
      return;
    }
    setState(() => _loading = true);
    final err = await AuthService.solicitarReset(email);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (err == null) _enviado = true;
    });
    if (err != null) _snack(err);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Recuperar contraseña'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _enviado ? _buildConfirmacion() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_reset, size: 56, color: const Color(0xFF1B3022).withOpacity(0.8)),
        const SizedBox(height: 16),
        Text('¿Olvidaste tu contraseña?', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1B3022))),
        const SizedBox(height: 8),
        Text(
          'Ingresa tu correo y te enviaremos un enlace para restablecer tu contraseña.',
          style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'Correo electrónico',
            prefixIcon: const Icon(Icons.mail_outline),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B3022),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _loading ? null : _enviar,
            child: _loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Enviar enlace de recuperación'),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmacion() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 64, color: Colors.green),
        const SizedBox(height: 16),
        Text('¡Revisa tu correo!', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1B3022))),
        const SizedBox(height: 8),
        Text(
          'Te enviamos un enlace a ${_emailCtrl.text.trim()} para restablecer tu contraseña. Ábrelo desde tu navegador para continuar.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver al inicio de sesión')),
      ],
    );
  }
}
