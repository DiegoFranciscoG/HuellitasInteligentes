import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'devices_screen.dart';
import 'pet_moments_screen.dart';

/// Bandeja de avisos del usuario, con dos fuentes reales y distintas —igual
/// que en la web—: los anuncios que manda un administrador (`/notificaciones`,
/// incluye el diagnóstico manual sobre un dispositivo concreto) y las
/// alertas automáticas de la propia vivienda (`/alerta`, generadas por
/// [IotAlertaJob] en el backend cuando un dispositivo deja de dar señal).
/// Antes esta pantalla solo mostraba lo segundo, y encima con tres nombres de
/// campo equivocados (`created_at`, `tipo_alerta`, severidades `ALTA`/`MEDIA`
/// que el backend nunca manda) — la fecha, el color y el ícono nunca
/// coincidían con el dato real.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  bool _cargandoAlertas = true;
  bool _cargandoNotificaciones = true;
  List<dynamic> _alertas = [];
  List<dynamic> _notificaciones = [];

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
    _fetchNotificaciones();
  }

  Future<void> _fetchAlerts() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/alerta?casaId=${AuthService.userData?['casa_id']}&soloNoLeidas=false'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200 && mounted) {
        setState(() => _alertas = jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (_) {
      // Sin conexión o respuesta inesperada: se deja la lista como estaba.
    } finally {
      if (mounted) setState(() => _cargandoAlertas = false);
    }
  }

  Future<void> _fetchNotificaciones() async {
    final userId = AuthService.userData?['id'];
    if (userId == null) {
      if (mounted) setState(() => _cargandoNotificaciones = false);
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/notificaciones?usuarioId=$userId'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (response.statusCode == 200 && mounted) {
        setState(() => _notificaciones = jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (_) {
      // Igual que arriba: si falla, se queda con lo que ya tenía.
    } finally {
      if (mounted) setState(() => _cargandoNotificaciones = false);
    }
  }

  Future<void> _marcarLeida(int alertaId) async {
    try {
      await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/alerta/$alertaId/marcar-leida'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      _fetchAlerts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo marcar la alerta como leída.')),
        );
      }
    }
  }

  /// Si la alerta trae `dispositivo_id`, lleva al panel de dispositivos —no
  /// hay una pantalla de detalle por aparato en la app todavía, así que este
  /// es el destino real más cercano a "ver qué pasa con ese dispositivo".
  void _abrirDispositivoDeAlerta(dynamic item) {
    if (item['dispositivo_id'] == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DevicesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cargando = _cargandoAlertas && _cargandoNotificaciones;
    final sinNada = !cargando && _alertas.isEmpty && _notificaciones.isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Alertas'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: const Color(0xFFF9FBF9),
        elevation: 0,
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : sinNada
              ? const Center(child: Text('No hay alertas recientes', style: TextStyle(color: Colors.grey)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_notificaciones.isNotEmpty) ...[
                      const _SeccionTitulo('Notificaciones'),
                      ..._notificaciones.asMap().entries.map((e) => _NotificacionCard(item: e.value)
                          .animate().fadeIn(delay: (e.key * 30).ms, duration: 200.ms).slideY(begin: 0.04, end: 0)),
                      const SizedBox(height: 20),
                    ],
                    if (_alertas.isNotEmpty) const _SeccionTitulo('Alertas de tu IoT'),
                    ..._alertas.asMap().entries.map((e) {
                      final item = e.value;
                      final esLeida = item['leida'] == true;
                      final tieneDispositivo = item['dispositivo_id'] != null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: esLeida ? 1 : 4,
                        color: esLeida ? Colors.white : const Color(0xFFFFF9E6),
                        child: ListTile(
                          onTap: tieneDispositivo ? () => _abrirDispositivoDeAlerta(item) : null,
                          leading: CircleAvatar(
                            backgroundColor: _colorSeveridad(item['severidad']).withValues(alpha: 0.2),
                            child: Icon(_iconoTipo(item['tipo']), color: _colorSeveridad(item['severidad'])),
                          ),
                          title: Text(item['mensaje'] ?? 'Alerta', style: TextStyle(fontWeight: esLeida ? FontWeight.normal : FontWeight.bold)),
                          subtitle: Text(
                            _formatDate(item['ts']),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          trailing: esLeida
                              ? const Icon(Icons.check, color: Colors.green)
                              : IconButton(
                                  icon: const Icon(Icons.done_all, color: Colors.grey),
                                  onPressed: () => _marcarLeida(item['id']),
                                ),
                        ),
                      ).animate().fadeIn(delay: (e.key * 30).ms, duration: 200.ms).slideY(begin: 0.04, end: 0);
                    }),
                  ],
                ),
    );
  }

  /// Colores reales del enum `severidad_alerta` del backend
  /// (CRITICA/ADVERTENCIA/INFO) — antes se comparaba contra "ALTA"/"MEDIA",
  /// que el backend nunca manda, así que toda alerta caía siempre en el azul
  /// por defecto sin importar su severidad real.
  Color _colorSeveridad(String? severidad) {
    if (severidad == 'CRITICA') return Colors.red;
    if (severidad == 'ADVERTENCIA') return Colors.orange;
    return Colors.blue;
  }

  /// Ídem con el ícono: el campo real es `tipo`, no `tipo_alerta`, y ahora
  /// incluye los tipos que genera el trabajo automático de dispositivos IoT.
  IconData _iconoTipo(String? tipo) {
    if (tipo == 'IOT_OFFLINE' || tipo == 'IOT_NUNCA_CONECTO') return Icons.wifi_off;
    if (tipo == 'IOT_CRITICO') return Icons.error_outline;
    if (tipo == 'TEMPERATURA') return Icons.thermostat;
    if (tipo == 'MOVIMIENTO') return Icons.directions_run;
    if (tipo == 'SISTEMA') return Icons.warning;
    return Icons.notifications;
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }
}

class _SeccionTitulo extends StatelessWidget {
  final String texto;
  const _SeccionTitulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        texto,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B3022), letterSpacing: 0.5),
      ),
    );
  }
}

/// Tarjeta de un anuncio o diagnóstico manual del administrador, con las
/// URLs dentro del texto convertidas en enlaces tocables — la misma técnica
/// de la web (partir el texto por regex en vez de RichText+innerHTML, para
/// no arriesgar nada al interpretar contenido escrito por otra persona).
class _NotificacionCard extends StatelessWidget {
  final dynamic item;
  const _NotificacionCard({required this.item});

  static final _urlRegex = RegExp(r'https?://[^\s]+');

  bool get _esMomentoMascota => (item['tipo'] ?? '').toString().toUpperCase() == 'MOMENTO_MASCOTA';

  Color _color() {
    final tipo = (item['tipo'] ?? '').toString().toUpperCase();
    if (tipo == 'MOMENTO_MASCOTA') return const Color(0xFF8A6A00);
    if (tipo.startsWith('IOT') || tipo == 'MANUAL_DIAGNOSTIC') return const Color(0xFF1B3022);
    if (tipo == 'ADVERTENCIA' || tipo.contains('STRIKE') || tipo.contains('MODERAC')) return const Color(0xFFBA1A1A);
    return const Color(0xFF8A6A00);
  }

  Color _fondo() {
    final tipo = (item['tipo'] ?? '').toString().toUpperCase();
    if (tipo == 'MOMENTO_MASCOTA') return const Color(0xFFFDC003).withValues(alpha: 0.22);
    if (tipo.startsWith('IOT') || tipo == 'MANUAL_DIAGNOSTIC') return const Color(0xFFD0E9D4);
    if (tipo == 'ADVERTENCIA' || tipo.contains('STRIKE') || tipo.contains('MODERAC')) return const Color(0xFFFFDAD6);
    return const Color(0xFFFDC003).withValues(alpha: 0.18);
  }

  @override
  Widget build(BuildContext context) {
    final texto = (item['mensaje'] ?? item['contenido'] ?? '').toString();
    final matches = _urlRegex.allMatches(texto).toList();

    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) spans.add(TextSpan(text: texto.substring(cursor, m.start)));
      final url = texto.substring(m.start, m.end);
      spans.add(TextSpan(
        text: url,
        style: TextStyle(color: _color(), fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
        // Un enlace de anuncio (por ejemplo, la página de descarga del APK)
        // es un destino externo: no hay pantalla dentro de la app que lo
        // reciba, así que se abre con el navegador del sistema.
        recognizer: TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ));
      cursor = m.end;
    }
    if (cursor < texto.length) spans.add(TextSpan(text: texto.substring(cursor)));

    return GestureDetector(
      onTap: _esMomentoMascota
          ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PetMomentsScreen()))
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _fondo(),
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: _color(), width: 4)),
        ),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 13, color: Color(0xFF434843), height: 1.4),
            children: spans,
          ),
        ),
      ),
    );
  }
}
