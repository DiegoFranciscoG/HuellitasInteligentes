import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// "Momentos de tu mascota": lo que una cámara IoT detectó hace poco (comiendo,
/// bebiendo, durmiendo, jugando), con una cuenta regresiva de 3 minutos para
/// guardarlo antes de que el fragmento se borre solo, y la galería de lo que
/// ya se guardó. Misma lógica y mismos endpoints que la versión web.
class PetMomentsScreen extends StatefulWidget {
  const PetMomentsScreen({super.key});

  @override
  State<PetMomentsScreen> createState() => _PetMomentsScreenState();
}

class _PetMomentsScreenState extends State<PetMomentsScreen> {
  List<dynamic> _activos = [];
  List<dynamic> _galeria = [];
  bool _cargandoActivos = true;
  bool _cargandoGaleria = true;
  int? _guardando;

  Timer? _pollActivos;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _cargarActivos();
    _cargarGaleria();
    _pollActivos = Timer.periodic(const Duration(seconds: 15), (_) => _cargarActivos());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        for (final m in _activos) {
          final restantes = (m['segundos_restantes'] as num?)?.toInt() ?? 0;
          m['segundos_restantes'] = restantes > 0 ? restantes - 1 : 0;
        }
        _activos.removeWhere((m) => ((m['segundos_restantes'] as num?)?.toInt() ?? 0) <= 0);
      });
    });
  }

  @override
  void dispose() {
    _pollActivos?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _cargarActivos() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/momentos/activo'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (response.statusCode == 200 && mounted) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _activos = body['momentos'] ?? [];
          _cargandoActivos = false;
        });
      } else if (mounted) {
        setState(() => _cargandoActivos = false);
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoActivos = false);
    }
  }

  Future<void> _cargarGaleria() async {
    if (mounted) setState(() => _cargandoGaleria = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/momentos'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (response.statusCode == 200 && mounted) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _galeria = body['momentos'] ?? [];
          _cargandoGaleria = false;
        });
      } else if (mounted) {
        setState(() => _cargandoGaleria = false);
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoGaleria = false);
    }
  }

  Future<void> _guardar(dynamic momento) async {
    setState(() => _guardando = momento['id']);
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/momentos/${momento['id']}/guardar'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _activos.removeWhere((m) => m['id'] == momento['id']);
          _guardando = null;
        });
        _cargarGaleria();
      } else if (mounted) {
        setState(() => _guardando = null);
        _cargarActivos();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _guardando = null);
      }
    }
  }

  String _textoActividad(String? actividad) {
    switch (actividad) {
      case 'COMIENDO': return 'comiendo';
      case 'BEBIENDO': return 'bebiendo agua';
      case 'DURMIENDO': return 'durmiendo';
      case 'JUGANDO': return 'jugando';
      default: return 'frente a la cámara';
    }
  }

  IconData _iconoActividad(String? actividad) {
    switch (actividad) {
      case 'COMIENDO': return Icons.restaurant;
      case 'BEBIENDO': return Icons.water_drop;
      case 'DURMIENDO': return Icons.bedtime;
      case 'JUGANDO': return Icons.sports_baseball;
      default: return Icons.help_outline;
    }
  }

  String _formatoCuenta(int segundos) {
    final m = segundos ~/ 60;
    final s = segundos % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Momentos de tu Mascota'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: const Color(0xFFF9FBF9),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _cargarActivos();
          await _cargarGaleria();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Pendientes',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B3022), letterSpacing: 0.5),
            ),
            const SizedBox(height: 10),
            if (_cargandoActivos)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (_activos.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: const Row(
                  children: [
                    Icon(Icons.pets, color: Color(0xFF1B3022)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Nada pendiente ahora mismo. En cuanto tu cámara IoT detecte a tu mascota, aparecerá aquí.',
                        style: TextStyle(fontSize: 12.5, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._activos.map((m) => _tarjetaActivo(m)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Guardados', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B3022), letterSpacing: 0.5)),
                IconButton(
                  icon: Icon(Icons.refresh, size: 18, color: _cargandoGaleria ? Colors.grey : const Color(0xFF1B3022)),
                  onPressed: _cargarGaleria,
                ),
              ],
            ),
            if (!_cargandoGaleria && _galeria.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Todavía no has guardado ningún momento.', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
              )
            else
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.85,
                children: _galeria.map<Widget>((m) => _tarjetaGaleria(m)).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaActivo(dynamic m) {
    final urls = (m['urlsFragmento'] as List?)?.cast<String>() ?? [];
    final segundos = (m['segundos_restantes'] as num?)?.toInt() ?? 0;
    final nombre = m['perro_nombre'] ?? 'Tu mascota';
    final actividad = m['actividad'] as String?;
    final confianza = ((m['confianza'] as num?)?.toDouble() ?? 0) * 100;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDC003).withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: urls.isNotEmpty
                    ? Image.network(urls.first, fit: BoxFit.cover)
                    : Container(color: const Color(0xFF1B3022).withValues(alpha: 0.05), child: const Icon(Icons.image_not_supported, color: Colors.black26)),
              ),
              if (urls.length > 1)
                Positioned(
                  left: 8, bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    child: Text('${urls.length} fotos', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              Positioned(
                right: 8, top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFFFDC003), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF4A3800)),
                      const SizedBox(width: 4),
                      Text(_formatoCuenta(segundos), style: const TextStyle(color: Color(0xFF4A3800), fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_iconoActividad(actividad), size: 16, color: const Color(0xFF1B3022)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('$nombre · ${_textoActividad(actividad)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B3022))),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('confianza ${confianza.round()}%', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _guardando == m['id'] ? null : () => _guardar(m),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B3022),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _guardando == m['id']
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_alt, size: 18),
                    label: Text(_guardando == m['id'] ? 'Guardando...' : 'Guardar antes de que se borre'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaGaleria(dynamic m) {
    final urls = (m['urlsFragmento'] as List?)?.cast<String>() ?? [];
    final nombre = m['perro_nombre'] ?? 'Tu mascota';
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: urls.isNotEmpty
                ? Image.network(urls.first, fit: BoxFit.cover, width: double.infinity)
                : Container(color: const Color(0xFF1B3022).withValues(alpha: 0.05)),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('$nombre · ${_textoActividad(m['actividad'])}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1B3022))),
          ),
        ],
      ),
    );
  }
}
