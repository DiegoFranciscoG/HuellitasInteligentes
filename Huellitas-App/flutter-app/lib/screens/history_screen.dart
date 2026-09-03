import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Historial de acciones del usuario (altas/cambios de mascotas,
/// dispositivos, cámaras, etc.), ordenado por fecha.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isLoading = true;
  List<dynamic> _historial = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/historial?usuarioId=${AuthService.userData?['id']}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200 && mounted) {
        setState(() => _historial = jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (_) {
      // Sin conexión o respuesta inesperada: se deja el historial como estaba.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Historial'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: const Color(0xFFF9FBF9),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historial.isEmpty
              ? const Center(child: Text('No hay historial disponible', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _historial.length,
                  itemBuilder: (context, index) {
                    final item = _historial[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF1B3022).withOpacity(0.1),
                          child: Icon(_getIcon(item['tipo_entidad']), color: const Color(0xFF1B3022)),
                        ),
                        title: Text(item['accion'] ?? 'Acción', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(item['detalles'] ?? ''),
                        trailing: Text(
                          _formatDate(item['fecha_hora']),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ).animate().fadeIn(delay: (index * 30).ms, duration: 200.ms).slideY(begin: 0.04, end: 0);
                  },
                ),
    );
  }

  IconData _getIcon(String? tipo) {
    if (tipo == null) return Icons.history;
    tipo = tipo.toLowerCase();
    if (tipo.contains('perro') || tipo.contains('mascota')) return Icons.pets;
    if (tipo.contains('dispositivo')) return Icons.memory;
    if (tipo.contains('camara')) return Icons.videocam;
    return Icons.history;
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
