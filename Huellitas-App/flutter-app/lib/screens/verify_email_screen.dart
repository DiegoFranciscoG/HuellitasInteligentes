import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../utils/nav_after_auth.dart';

/// Verificación de correo con un código de 6 dígitos: confirma el código
/// recibido (dejando la sesión iniciada) o reenvía uno nuevo.
class VerifyEmailScreen extends StatefulWidget {
  /// Correo a verificar, precargado si se conoce (por ejemplo, desde login).
  final String? email;
  const VerifyEmailScreen({super.key, this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  late final TextEditingController _emailCtrl;
  final _codigoCtrl = TextEditingController();
  bool _verificando = false;
  bool _reenviando = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.email ?? '');
  }

  Future<void> _verificar() async {
    final email = _emailCtrl.text.trim();
    final codigo = _codigoCtrl.text.trim();
    if (email.isEmpty || codigo.length != 6) {
      _snack('Ingresa tu correo y el código de 6 dígitos.');
      return;
    }
    setState(() => _verificando = true);
    final err = await AuthService.verificarCodigo(email, codigo);
    if (!mounted) return;
    setState(() => _verificando = false);
    if (err == null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => destinoTrasAutenticar()),
        (route) => false,
      );
    } else {
      _snack(err);
    }
  }

  Future<void> _reenviar() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _snack('Ingresa tu correo primero.');
      return;
    }
    setState(() => _reenviando = true);
    final err = await AuthService.reenviarCodigo(email);
    if (!mounted) return;
    setState(() => _reenviando = false);
    _snack(err ?? 'Código reenviado a tu correo.');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Verificar correo'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.mark_email_unread_outlined, size: 56, color: const Color(0xFF1B3022).withOpacity(0.8)),
              const SizedBox(height: 16),
              Text('Verifica tu correo', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1B3022))),
              const SizedBox(height: 8),
              Text(
                'Te enviamos un código de 6 dígitos a tu correo. Ingrésalo para activar tu cuenta.',
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
              const SizedBox(height: 12),
              TextField(
                controller: _codigoCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, letterSpacing: 8),
                decoration: InputDecoration(
                  hintText: '000000',
                  filled: true,
                  fillColor: Colors.white,
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B3022),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _verificando ? null : _verificar,
                  child: _verificando
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Verificar'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _reenviando ? null : _reenviar,
                  child: Text(_reenviando ? 'Reenviando...' : 'Reenviar código'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
