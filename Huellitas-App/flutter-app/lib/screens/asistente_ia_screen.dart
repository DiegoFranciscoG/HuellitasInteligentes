import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class _ChatMsg {
  final bool isUser;
  final String texto;
  _ChatMsg({required this.isUser, required this.texto});
}

/// Chat con el asistente de IA especializado en nutrición canina: responde
/// preguntas usando los datos de la mascota activa del usuario (raza, edad,
/// peso) y, si detecta que se busca un negocio o veterinaria cercana, ubica
/// al usuario y muestra los resultados con enlace a Google Maps.
class AsistenteIaScreen extends StatefulWidget {
  const AsistenteIaScreen({super.key});

  @override
  State<AsistenteIaScreen> createState() => _AsistenteIaScreenState();
}

class _AsistenteIaScreenState extends State<AsistenteIaScreen> {
  final List<_ChatMsg> _mensajes = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _isTyping = false;
  Map<String, dynamic>? _mascotaActiva;

  static const _sugerencias = [
    '¿Cuántas veces debe comer mi perro al día?',
    '¿Qué alimentos son tóxicos para los perros?',
    '¿Dónde hay tiendas de mascotas cercanas?',
    '¿Cuánta agua necesita mi mascota?',
  ];

  static const _kwNegocio = ['negocio', 'tienda', 'petshop', 'comprar', 'veterinaria', 'donde', 'dónde'];
  static const _fallbackLat = -0.1807;
  static const _fallbackLng = -78.4678;

  @override
  void initState() {
    super.initState();
    final nombre = (AuthService.userData?['nombre'] as String?)?.split(' ').first;
    _mensajes.add(_ChatMsg(
      isUser: false,
      texto: '¡Hola${nombre != null ? ', $nombre' : ''}! Soy tu asistente de nutrición canina. ¿En qué te puedo ayudar hoy?',
    ));
    _cargarMascota();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarMascota() async {
    final userData = AuthService.userData;
    final rawCasaId = userData?['casa_id'] ?? userData?['casa']?['id'];
    final casaId = rawCasaId is int ? rawCasaId : int.tryParse(rawCasaId?.toString() ?? '');
    if (casaId == null) return;
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/casa/dashboard?casaId=$casaId'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final perros = data?['perros'];
        if (perros is List && perros.isNotEmpty) {
          setState(() => _mascotaActiva = Map<String, dynamic>.from(perros.first));
        }
      }
    } catch (_) {}
  }

  String _calcularEdad(String? fechaNac) {
    if (fechaNac == null) return 'desconocida';
    final d = DateTime.tryParse(fechaNac);
    if (d == null) return 'desconocida';
    final meses = (DateTime.now().difference(d).inDays / 30).floor();
    return meses < 24 ? '$meses meses' : '${(meses / 12).floor()} años';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _enviar([String? textoSugerido]) async {
    final texto = (textoSugerido ?? _inputCtrl.text).trim();
    if (texto.isEmpty || _isTyping) return;

    setState(() {
      _mensajes.add(_ChatMsg(isUser: true, texto: texto));
      _inputCtrl.clear();
      _isTyping = true;
    });
    _scrollToEnd();

    final lower = texto.toLowerCase();
    if (_kwNegocio.any(lower.contains)) {
      await _buscarNegocios();
      return;
    }

    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/ia/nutricion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({
          'pregunta': texto,
          'raza': _mascotaActiva?['raza'],
          'edad': _calcularEdad(_mascotaActiva?['fecha_nacimiento']),
          'peso': _mascotaActiva?['peso'],
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        _agregarBotMsg(data['respuesta']?.toString() ?? data.toString());
      } else {
        _agregarBotMsg('No pude conectar con el servidor de IA. Intenta de nuevo.');
      }
    } catch (e) {
      _agregarBotMsg('No pude conectar con el servidor de IA. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  Future<void> _buscarNegocios() async {
    double lat = _fallbackLat;
    double lng = _fallbackLng;
    try {
      final permiso = await Geolocator.checkPermission();
      var permisoFinal = permiso;
      if (permiso == LocationPermission.denied) {
        permisoFinal = await Geolocator.requestPermission();
      }
      if (permisoFinal == LocationPermission.always || permisoFinal == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 6));
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {
      // usa el fallback si no hay GPS/permiso
    }

    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/ia/negocios-cercanos?lat=$lat&lng=$lng&tipo=pet_store'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final places = data is List ? data : (data['places'] as List? ?? []);
        if (places.isEmpty) {
          _agregarBotMsg('No encontré negocios cercanos en esta ubicación.');
        } else {
          setState(() => _mensajes.add(_ChatMsg(isUser: false, texto: '__NEGOCIOS__')));
          _negociosEncontrados = List<Map<String, dynamic>>.from(places.map((p) => Map<String, dynamic>.from(p)));
        }
      } else {
        _agregarBotMsg('Lo siento, no pude buscar negocios en este momento.');
      }
    } catch (_) {
      _agregarBotMsg('Lo siento, no pude buscar negocios en este momento.');
    } finally {
      if (mounted) setState(() => _isTyping = false);
      _scrollToEnd();
    }
  }

  List<Map<String, dynamic>> _negociosEncontrados = [];

  void _agregarBotMsg(String texto) {
    if (!mounted) return;
    setState(() => _mensajes.add(_ChatMsg(isUser: false, texto: texto)));
    _scrollToEnd();
  }

  Future<void> _abrirMaps(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.smart_toy_outlined),
            SizedBox(width: 8),
            Text('Asistente IA'),
          ],
        ),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: _mensajes.length,
              itemBuilder: (context, index) {
                final msg = _mensajes[index];
                if (msg.texto == '__NEGOCIOS__') return _buildNegociosList();
                return _buildBubble(msg);
              },
            ),
          ),
          if (_isTyping)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Escribiendo...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _sugerencias.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ActionChip(
                label: Text(_sugerencias[i], style: const TextStyle(fontSize: 12)),
                onPressed: _isTyping ? null : () => _enviar(_sugerencias[i]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      decoration: InputDecoration(
                        hintText: 'Escribe tu pregunta...',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _enviar(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: const Color(0xFF1B3022),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _isTyping ? null : () => _enviar(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatMsg msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: msg.isUser ? const Color(0xFF1B3022) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Text(
          msg.texto,
          style: GoogleFonts.inter(color: msg.isUser ? Colors.white : Colors.black87, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildNegociosList() {
    if (_negociosEncontrados.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('Negocios y veterinarias cercanas:', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final n in _negociosEncontrados) _buildNegocioCard(n),
      ],
    );
  }

  Widget _buildNegocioCard(Map<String, dynamic> n) {
    final nombre = n['displayName']?['text'] ?? n['nombre'] ?? 'Tienda de mascotas';
    final addr = n['formattedAddress'] ?? n['direccion'] ?? '';
    final rating = n['rating'];
    final openNow = n['currentOpeningHours']?['openNow'] ?? n['regularOpeningHours']?['openNow'] ?? n['opening_hours']?['open_now'];
    final placeId = n['id'] ?? n['place_id'];
    final mapsUrl = n['googleMapsUri'] ??
        (placeId != null
            ? 'https://www.google.com/maps/place/?q=place_id:$placeId'
            : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('$nombre $addr')}');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.storefront_outlined, color: Color(0xFF1B3022)),
        title: Text('$nombre${rating != null ? ' ⭐ $rating' : ''}'),
        subtitle: Text(
          '$addr\n${openNow == true ? '🟢 Abierto ahora' : (openNow == false ? '🔴 Cerrado' : '⚪ Horario no disponible')}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.map_outlined),
        onTap: () => _abrirMaps(mapsUrl),
      ),
    );
  }
}
