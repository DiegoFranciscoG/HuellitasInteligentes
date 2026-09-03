import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Vigila las notificaciones del usuario y, cuando llega una que todavía no
/// ha visto, la muestra en un cuadro emergente que ocupa media pantalla, con
/// un botón para aceptarla. Al aceptar se marca como leída en el servidor, así
/// que no vuelve a salir ni aquí ni en la web.
///
/// Se monta una sola vez, envolviendo la aplicación ya autenticada, para que
/// el aviso aparezca sin importar en qué pantalla esté el usuario.
class VigilanteNotificaciones extends StatefulWidget {
  final Widget child;

  const VigilanteNotificaciones({super.key, required this.child});

  @override
  State<VigilanteNotificaciones> createState() => _VigilanteNotificacionesState();
}

class _VigilanteNotificacionesState extends State<VigilanteNotificaciones> {
  Timer? _sondeo;
  bool _mostrando = false;

  /// Notificaciones ya mostradas en esta sesión. Evita repetir el cuadro si el
  /// servidor todavía no registró el "leída" cuando llega el siguiente sondeo.
  final Set<int> _yaMostradas = {};

  @override
  void initState() {
    super.initState();
    // Un primer vistazo al entrar, y después cada 20 s: es el mismo ritmo con
    // el que la web refresca su campanita.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisar());
    _sondeo = Timer.periodic(const Duration(seconds: 20), (_) => _revisar());
  }

  @override
  void dispose() {
    _sondeo?.cancel();
    super.dispose();
  }

  Future<void> _revisar() async {
    if (!mounted || _mostrando) return;
    final token = AuthService.token;
    final usuarioId = AuthService.userData?['id'];
    if (token == null || usuarioId == null) return;

    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/notificaciones?usuarioId=$usuarioId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200 || !mounted) return;

      final lista = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      // Solo las que el servidor sigue teniendo por entregar.
      final pendientes = lista.where((n) {
        final id = (n['id'] as num?)?.toInt();
        return n['estado'] == 'PENDIENTE' && id != null && !_yaMostradas.contains(id);
      }).toList();

      if (pendientes.isEmpty) return;
      await _mostrar(pendientes.first);
    } catch (_) {
      // Sin conexión: se reintenta en el siguiente sondeo.
    }
  }

  Future<void> _mostrar(dynamic notificacion) async {
    final id = (notificacion['id'] as num?)?.toInt();
    if (id == null || !mounted) return;

    _yaMostradas.add(id);
    _mostrando = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CuadroNotificacion(notificacion: notificacion),
    );

    await _marcarLeidas();
    _mostrando = false;
  }

  Future<void> _marcarLeidas() async {
    final token = AuthService.token;
    final usuarioId = AuthService.userData?['id'];
    if (token == null || usuarioId == null) return;
    try {
      await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/notificaciones/leidas?usuarioId=$usuarioId'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      // Si falla, la notificación ya quedó en _yaMostradas y no se repite en
      // esta sesión; el servidor la volverá a dar por pendiente más adelante.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// El cuadro en sí: ocupa media pantalla, con el color de su categoría.
class _CuadroNotificacion extends StatelessWidget {
  final dynamic notificacion;

  const _CuadroNotificacion({required this.notificacion});

  String get _tipo => (notificacion['tipo'] ?? '').toString().toUpperCase();

  /// Mismas categorías y colores que usa la web en su campanita.
  ({Color color, Color fondo, IconData icono, String titulo}) get _categoria {
    if (_tipo == 'MOMENTO_MASCOTA') {
      return (
        color: const Color(0xFF8A6A00),
        fondo: const Color(0xFFFDC003),
        icono: Icons.pets,
        titulo: 'Momento con tu mascota',
      );
    }
    if (_tipo.startsWith('IOT') || _tipo == 'MANUAL_DIAGNOSTIC') {
      return (
        color: const Color(0xFF1B3022),
        fondo: const Color(0xFFD0E9D4),
        icono: Icons.router,
        titulo: 'Aviso sobre tu IoT',
      );
    }
    if (_tipo == 'ADVERTENCIA' || _tipo.contains('STRIKE') || _tipo.contains('MODERAC')) {
      return (
        color: const Color(0xFFBA1A1A),
        fondo: const Color(0xFFFFDAD6),
        icono: Icons.gavel,
        titulo: 'Aviso de moderación',
      );
    }
    return (
      color: const Color(0xFF8A6A00),
      fondo: const Color(0xFFFDC003),
      icono: Icons.campaign,
      titulo: 'Anuncio oficial',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = _categoria;
    final texto = (notificacion['contenido'] ?? notificacion['mensaje'] ?? '').toString();
    final alto = MediaQuery.of(context).size.height * 0.5;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: alto, maxHeight: alto),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: cat.fondo.withValues(alpha: 0.35),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: cat.fondo,
                    child: Icon(cat.icono, color: cat.color, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    cat.titulo,
                    style: GoogleFonts.outfit(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: cat.color,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Text(
                  texto,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    height: 1.5,
                    color: const Color(0xFF434843),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B3022),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    'Aceptar',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
