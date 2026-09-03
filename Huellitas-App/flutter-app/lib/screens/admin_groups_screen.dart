import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Panel de moderación de grupos de la comunidad: lista los grupos
/// existentes, permite ver su detalle (miembros y últimos mensajes) y
/// eliminar un grupo por moderación, notificando a sus miembros.
class AdminGroupsScreen extends StatefulWidget {
  const AdminGroupsScreen({super.key});

  @override
  State<AdminGroupsScreen> createState() => _AdminGroupsScreenState();
}

class _AdminGroupsScreenState extends State<AdminGroupsScreen> {
  bool _isLoading = true;
  List<dynamic> _grupos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200) {
        setState(() => _grupos = jsonDecode(utf8.decode(res.bodyBytes)));
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _verDetalle(Map<String, dynamic> grupo) async {
    List<dynamic> miembros = [];
    List<dynamic> mensajes = [];
    bool cargando = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          if (cargando) {
            _cargarDetalle(grupo['id']).then((data) {
              miembros = data['miembros'] ?? [];
              mensajes = data['mensajes'] ?? [];
              setModalState(() => cargando = false);
            });
            cargando = false; // evita relanzar el future en cada rebuild
          }
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            expand: false,
            builder: (ctx, scrollCtrl) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(grupo['nombre'] ?? 'Grupo', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      controller: scrollCtrl,
                      children: [
                        Text('Miembros (${miembros.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        for (final m in miembros)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_outline),
                            title: Text(m['nombre'] ?? ''),
                            subtitle: Text(m['email'] ?? ''),
                            trailing: Text(m['rol'] ?? '', style: const TextStyle(fontSize: 11)),
                          ),
                        const Divider(height: 32),
                        Text('Últimos mensajes (${mensajes.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        for (final m in mensajes)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.chat_bubble_outline),
                            title: Text(m['contenido']?.toString().isNotEmpty == true ? m['contenido'] : '[imagen]'),
                            subtitle: Text(m['autor_nombre'] ?? ''),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _cargarDetalle(dynamic grupoId) async {
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/grupos/$grupoId/detalle'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)));
      }
    } catch (_) {}
    return {'miembros': [], 'mensajes': []};
  }

  Future<void> _eliminarGrupo(Map<String, dynamic> grupo) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar grupo por moderación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('¿Eliminar "${grupo['nombre']}"? Se notificará a sus miembros.'),
            const SizedBox(height: 12),
            TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Motivo (para el registro interno)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar grupo'),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/${grupo['id']}')
          .replace(queryParameters: {'adminId': AuthService.userData?['id'].toString()});
      final res = await http.delete(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.statusCode == 200 ? 'Grupo eliminado por moderación y miembros notificados.' : 'Grupo removido del registro.')),
        );
      }
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Grupos (Moderación)'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _grupos.isEmpty
              ? const Center(child: Text('No hay grupos registrados', style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _grupos.length,
                    itemBuilder: (context, index) {
                      final g = Map<String, dynamic>.from(_grupos[index]);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Color(0xFF1B3022), child: Icon(Icons.groups, color: Colors.white)),
                          title: Text(g['nombre'] ?? 'Grupo'),
                          subtitle: Text('${g['descripcion'] ?? ''} · ${g['total_miembros'] ?? 0} miembros'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.visibility_outlined), onPressed: () => _verDetalle(g)),
                              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _eliminarGrupo(g)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
