import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Configuración compartida de servidores ICE (STUN/TURN) para WebRTC.
///
/// Si hay una API key de Metered configurada en `.env`
/// (`TURN_METERED_API_KEY` + `TURN_METERED_DOMAIN`), las credenciales TURN
/// se piden en tiempo real a la API de Metered en vez de quedar fijas en el
/// código — así nunca quedan desactualizadas si el usuario/contraseña rota
/// desde el panel de Metered.
///
///   TURN_METERED_DOMAIN=huellitas-inteligentes.metered.live
///   TURN_METERED_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
///
/// Sin esa key, cae de vuelta a solo STUN público de Google (funciona en la
/// mayoría de redes domésticas, puede fallar en redes corporativas/algunos
/// operadores).
class WebRtcConfig {
  static Map<String, dynamic>? _cachedIceServers;

  static const _stunOnly = {
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
    ],
  };

  static Future<Map<String, dynamic>> get iceServers async {
    if (_cachedIceServers != null) return _cachedIceServers!;

    final apiKey = dotenv.env['TURN_METERED_API_KEY'];
    final domain = dotenv.env['TURN_METERED_DOMAIN'];

    if (apiKey == null || apiKey.isEmpty || domain == null || domain.isEmpty) {
      return _stunOnly;
    }

    try {
      final uri = Uri.https(domain, '/api/v1/turn/credentials', {'apiKey': apiKey});
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final servers = jsonDecode(response.body) as List<dynamic>;
        _cachedIceServers = {'iceServers': servers};
        return _cachedIceServers!;
      }
      debugPrint('Metered TURN: respuesta ${response.statusCode}, usando solo STUN');
    } catch (e) {
      debugPrint('No se pudo obtener credenciales TURN de Metered: $e');
    }

    return _stunOnly;
  }
}
