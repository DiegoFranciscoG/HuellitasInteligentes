import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Bandeja de moderación de denuncias de la comunidad: filtra por estado,
/// permite resolver una denuncia (strike, eliminar contenido o descartar) y
/// revertir decisiones tomadas automáticamente por la IA.
class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  bool _isLoading = true;
  List<dynamic> _reportes = [];
  String _filtro = 'PENDIENTE';

  Map<String, String> get _jsonHeaders => {
        'Authorization': 'Bearer ${AuthService.token}',
        'Content-Type': 'application/json',
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
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/reportes'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200) {
        setState(() => _reportes = jsonDecode(utf8.decode(res.bodyBytes)));
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  List<dynamic> get _filtrados {
    if (_filtro == 'TODOS') return _reportes;
    return _reportes.where((r) => (r['estado'] ?? 'PENDIENTE') == _filtro).toList();
  }

  Future<void> _revertirIa(dynamic reporteId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revertir decisión de la IA'),
        content: const Text('¿Deseas revertir esta decisión automática y devolverla a revisión manual?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revertir')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/reportes/$reporteId/revertir'),
        headers: _jsonHeaders,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.statusCode == 200 ? 'Decisión de la IA revertida. Vuelve a la cola manual.' : 'Error al revertir.')),
        );
      }
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _resolver(Map<String, dynamic> reporte, String decision) async {
    final comentarioCtrl = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_labelDecision(decision)),
        content: TextField(
          controller: comentarioCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Comentario del admin', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmado != true || comentarioCtrl.text.trim().isEmpty) return;

    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/reportes/${reporte['id']}/resolver'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'adminId': AuthService.userData?['id'],
          'decision': decision,
          'comentarioAdmin': comentarioCtrl.text.trim(),
        }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.statusCode == 200 ? 'Denuncia resuelta ($decision). Usuario notificado.' : 'Error al resolver la denuncia.')),
        );
      }
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _labelDecision(String decision) {
    switch (decision) {
      case 'STRIKE':
        return 'Aplicar strike al usuario';
      case 'ELIMINAR_SIN_STRIKE':
        return 'Eliminar contenido sin strike';
      default:
        return 'Descartar denuncia';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Moderación'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in ['PENDIENTE', 'RESUELTO', 'DESCARTADO', 'TODOS'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f),
                        selected: _filtro == f,
                        onSelected: (_) => setState(() => _filtro = f),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtrados.isEmpty
                    ? const Center(child: Text('No hay denuncias en este filtro.', style: TextStyle(color: Colors.grey)))
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtrados.length,
                          itemBuilder: (context, index) {
                            final r = Map<String, dynamic>.from(_filtrados[index]);
                            final decididoPor = r['decidido_por']?.toString().toUpperCase();
                            final esIa = decididoPor == 'IA' || decididoPor == 'SIGHTENGINE' || (r['confianza_ia'] != null && r['decidido_por'] == null);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.shield_outlined, size: 18, color: Colors.orange.shade700),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text('Reportado: ${r['reportado_nombre'] ?? 'Usuario'}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                                          child: Text(r['estado'] ?? 'PENDIENTE', style: const TextStyle(fontSize: 10)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('Denunciado por: ${r['denunciante_nombre'] ?? 'Anónimo'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    const SizedBox(height: 6),
                                    Text('Motivo: ${r['motivo'] ?? ''}'),
                                    if (r['contenido_denunciado'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text('"${r['contenido_denunciado']}"', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
                                    ],
                                    if (esIa) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.smart_toy_outlined, size: 14, color: Colors.blueGrey),
                                          const SizedBox(width: 4),
                                          Text(
                                            decididoPor == 'SIGHTENGINE' ? 'Decisión automática (Sightengine)' : 'Decisión automática de la IA',
                                            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                          ),
                                          const Spacer(),
                                          TextButton.icon(
                                            onPressed: () => _revertirIa(r['id']),
                                            icon: const Icon(Icons.undo, size: 14),
                                            label: const Text('Revertir', style: TextStyle(fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if ((r['estado'] ?? 'PENDIENTE') == 'PENDIENTE') ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          OutlinedButton(onPressed: () => _resolver(r, 'STRIKE'), child: const Text('Strike', style: TextStyle(fontSize: 12))),
                                          OutlinedButton(onPressed: () => _resolver(r, 'ELIMINAR_SIN_STRIKE'), child: const Text('Eliminar', style: TextStyle(fontSize: 12))),
                                          OutlinedButton(onPressed: () => _resolver(r, 'DESCARTADO'), child: const Text('Descartar', style: TextStyle(fontSize: 12))),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
