import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Pantalla de administración para redactar y enviar avisos masivos (tipo
/// información, advertencia o urgente) a la campanita de notificaciones de
/// todos los usuarios, y ver el historial de avisos enviados.
class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  State<AdminAnnouncementsScreen> createState() => _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  final _tituloCtrl = TextEditingController();
  final _mensajeCtrl = TextEditingController();
  String _tipo = 'INFO';
  bool _enviando = false;
  List<dynamic> _previos = [];

  @override
  void initState() {
    super.initState();
    _cargarPrevios();
  }

  Future<void> _cargarPrevios() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/anuncios'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200 && mounted) {
        setState(() => _previos = jsonDecode(utf8.decode(res.bodyBytes)));
      }
    } catch (_) {}
  }

  Future<void> _enviar() async {
    if (_tituloCtrl.text.trim().isEmpty || _mensajeCtrl.text.trim().isEmpty) return;
    setState(() => _enviando = true);
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/admin/anuncios').replace(queryParameters: {
        'adminId': AuthService.userData?['id']?.toString() ?? '1',
        'titulo': _tituloCtrl.text.trim(),
        'mensaje': _mensajeCtrl.text.trim(),
        'tipo': _tipo,
      });
      final res = await http.post(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.statusCode == 200 ? '¡Aviso enviado a la campanita de todos los usuarios!' : 'Error al enviar el aviso.')),
        );
      }
      if (res.statusCode == 200) {
        _tituloCtrl.clear();
        _mensajeCtrl.clear();
        _cargarPrevios();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Avisos Masivos'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(controller: _tituloCtrl, decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
            controller: _mensajeCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Mensaje', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _tipo,
            decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'INFO', child: Text('Información')),
              DropdownMenuItem(value: 'WARNING', child: Text('Advertencia')),
              DropdownMenuItem(value: 'URGENTE', child: Text('Urgente')),
            ],
            onChanged: (v) => setState(() => _tipo = v ?? 'INFO'),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B3022), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _enviando ? null : _enviar,
            icon: _enviando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.campaign),
            label: Text(_enviando ? 'Enviando...' : 'Enviar aviso a todos los usuarios'),
          ),
          const SizedBox(height: 28),
          Text('Avisos enviados anteriormente', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_previos.isEmpty) const Text('No hay avisos previos.', style: TextStyle(color: Colors.grey)),
          for (final a in _previos)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const Icon(Icons.campaign_outlined, color: Color(0xFF1B3022)),
                title: Text(a['titulo'] ?? ''),
                subtitle: Text(a['mensaje'] ?? ''),
                trailing: Text(a['tipo'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ),
        ],
      ),
    );
  }
}
