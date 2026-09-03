import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Panel de administración con métricas de actividad de la plataforma:
/// usuarios conectados en las últimas 24h/7 días, inactivos y desactivados.
class AdminActivityScreen extends StatefulWidget {
  const AdminActivityScreen({super.key});

  @override
  State<AdminActivityScreen> createState() => _AdminActivityScreenState();
}

class _AdminActivityScreenState extends State<AdminActivityScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _actividad = {
    'conectados_24h': 0,
    'conectados_7d': 0,
    'inactivos_30d': 0,
    'desactivados': 0,
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/graficas-actividad'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map) setState(() => _actividad = Map<String, dynamic>.from(data));
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  int get _totalUsuarios =>
      ((_actividad['conectados_7d'] ?? 0) as num).toInt() +
      ((_actividad['inactivos_30d'] ?? 0) as num).toInt() +
      ((_actividad['desactivados'] ?? 0) as num).toInt();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Actividad de la Plataforma'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: GridView.count(
                padding: const EdgeInsets.all(20),
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.3,
                children: [
                  _statCard('Conectados 24h', _actividad['conectados_24h'], Icons.bolt, Colors.green),
                  _statCard('Conectados 7 días', _actividad['conectados_7d'], Icons.people, Colors.blue),
                  _statCard('Inactivos 30 días', _actividad['inactivos_30d'], Icons.hourglass_bottom, Colors.orange),
                  _statCard('Desactivados', _actividad['desactivados'], Icons.person_off, Colors.red),
                  _statCard('Total de usuarios', _totalUsuarios, Icons.groups, const Color(0xFF1B3022)),
                ],
              ),
            ),
    );
  }

  Widget _statCard(String label, dynamic value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text('${value ?? 0}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1B3022))),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
