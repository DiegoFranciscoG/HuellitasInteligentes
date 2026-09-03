import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Gestión de usuarios de la plataforma: lista cuentas con su rol, estado y
/// strikes acumulados, y permite consultar el historial de actividad
/// (publicaciones, resoluciones de moderación, suscripciones) de cada uno.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  bool _isLoading = true;
  List<dynamic> _usuarios = [];

  @override
  void initState() {
    super.initState();
    _fetchUsuarios();
  }

  Future<void> _fetchUsuarios() async {
    final token = AuthService.token;
    if (token == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/usuarios'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _usuarios = jsonDecode(utf8.decode(response.bodyBytes));
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _verActividad(int usuarioId) async {
    final token = AuthService.token;
    if (token == null) return;
    
    showDialog(context: context, builder: (_) => const Center(child: CircularProgressIndicator()));
    
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/usuarios/$usuarioId/actividad'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      if (mounted) Navigator.pop(context); // Close dialog
      
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        _mostrarModalActividad(data);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al cargar actividad')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error de conexión')));
      }
    }
  }

  void _mostrarModalActividad(dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final publicaciones = (map['publicaciones'] as List?) ?? [];
    final resoluciones = (map['resoluciones'] as List?) ?? [];
    final suscripciones = (map['suscripciones'] as List?) ?? [];
    final items = [
      for (final p in publicaciones) {'icon': Icons.forum_outlined, 'title': p['contenido'] ?? 'Publicación', 'fecha': p['created_at']},
      for (final r in resoluciones) {'icon': Icons.gavel_outlined, 'title': 'Moderación: ${r['decision'] ?? ''} — ${r['comentario_admin'] ?? ''}', 'fecha': r['fecha_resolucion']},
      for (final s in suscripciones) {'icon': Icons.card_membership_outlined, 'title': 'Plan ${s['plan_nombre'] ?? ''} (${s['estado'] ?? ''})', 'fecha': s['created_at']},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Actividad Reciente', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No hay actividad registrada'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            leading: Icon(item['icon'] as IconData, color: const Color(0xFF1B3022)),
                            title: Text(item['title']?.toString() ?? ''),
                            subtitle: Text(item['fecha']?.toString() ?? ''),
                          );
                        },
                      ),
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Gestión de Usuarios'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: const Color(0xFFF9FBF9),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _usuarios.isEmpty
              ? const Center(child: Text('No hay usuarios registrados', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _usuarios.length,
                  itemBuilder: (context, index) {
                    final item = _usuarios[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFF1B3022).withOpacity(0.1),
                                  child: Text(
                                    (item['nombre'] ?? 'U')[0].toUpperCase(),
                                    style: const TextStyle(color: Color(0xFF1B3022), fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['nombre'] ?? 'Usuario', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      Text(item['email'] ?? '', style: const TextStyle(color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item['rol'] ?? 'USER',
                                    style: TextStyle(fontSize: 10, color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Estado', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    Text(item['estado'] ?? 'ACTIVO', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Strikes', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    Text('${item['strikes'] ?? 0} / 3', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                  ],
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => _verActividad(item['id']),
                                  icon: const Icon(Icons.remove_red_eye, size: 16),
                                  label: const Text('Ver Actividad'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF1B3022),
                                    elevation: 0,
                                    side: const BorderSide(color: Color(0xFF1B3022)),
                                  ),
                                )
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
