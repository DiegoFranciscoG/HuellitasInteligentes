import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Gestión de planes de suscripción: crear, editar, activar/desactivar y
/// descontinuar planes, notificando automáticamente a los propietarios
/// suscritos cuando cambia un plan.
class AdminPlansScreen extends StatefulWidget {
  const AdminPlansScreen({super.key});

  @override
  State<AdminPlansScreen> createState() => _AdminPlansScreenState();
}

class _AdminPlansScreenState extends State<AdminPlansScreen> {
  bool _isLoading = true;
  List<dynamic> _planes = [];

  Map<String, String> get _jsonHeaders => {
        'Authorization': 'Bearer ${AuthService.token}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _fetchPlanes();
  }

  Future<void> _fetchPlanes() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/planes'),
        headers: _jsonHeaders,
      );
      if (response.statusCode == 200) {
        setState(() => _planes = jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? plan}) async {
    final nombreCtrl = TextEditingController(text: plan?['nombre'] ?? '');
    final precioCtrl = TextEditingController(text: plan?['precio_mensual']?.toString() ?? '');
    final ofertaCtrl = TextEditingController(text: plan?['precio_oferta']?.toString() ?? '');
    final descuentoCtrl = TextEditingController(text: plan?['descuento_porcentaje']?.toString() ?? '0');
    final dispositivosCtrl = TextEditingController(text: plan?['limite_dispositivos']?.toString() ?? '5');
    final almacenamientoCtrl = TextEditingController(text: plan?['limite_almacenamiento_mb']?.toString() ?? '1000');
    final descripcionCtrl = TextEditingController(text: plan?['descripcion'] ?? '');
    final esEdicion = plan != null;

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esEdicion ? 'Editar plan' : 'Nuevo plan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
              TextField(controller: precioCtrl, decoration: const InputDecoration(labelText: 'Precio mensual'), keyboardType: TextInputType.number),
              TextField(controller: ofertaCtrl, decoration: const InputDecoration(labelText: 'Precio oferta (opcional)'), keyboardType: TextInputType.number),
              TextField(controller: descuentoCtrl, decoration: const InputDecoration(labelText: '% Descuento'), keyboardType: TextInputType.number),
              if (!esEdicion) ...[
                TextField(controller: dispositivosCtrl, decoration: const InputDecoration(labelText: 'Límite de dispositivos'), keyboardType: TextInputType.number),
                TextField(controller: almacenamientoCtrl, decoration: const InputDecoration(labelText: 'Almacenamiento (MB)'), keyboardType: TextInputType.number),
              ],
              TextField(controller: descripcionCtrl, decoration: const InputDecoration(labelText: 'Descripción'), maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (guardar != true || nombreCtrl.text.trim().isEmpty) return;

    final payload = {
      if (!esEdicion) 'adminId': AuthService.userData?['id'],
      'nombre': nombreCtrl.text.trim(),
      'precioMensual': double.tryParse(precioCtrl.text.trim()) ?? 0,
      'precioOferta': ofertaCtrl.text.trim().isEmpty ? null : double.tryParse(ofertaCtrl.text.trim()),
      'descuentoPorcentaje': double.tryParse(descuentoCtrl.text.trim()) ?? 0,
      if (!esEdicion) 'limiteDispositivos': int.tryParse(dispositivosCtrl.text.trim()) ?? 5,
      if (!esEdicion) 'limiteAlmacenamientoMb': int.tryParse(almacenamientoCtrl.text.trim()) ?? 1000,
      'descripcion': descripcionCtrl.text.trim(),
    };

    try {
      final uri = esEdicion
          ? Uri.parse('${ApiService.baseUrl}/huellitas/admin/planes/${plan['id']}')
          : Uri.parse('${ApiService.baseUrl}/huellitas/admin/planes');
      final res = esEdicion
          ? await http.put(uri, headers: _jsonHeaders, body: jsonEncode(payload))
          : await http.post(uri, headers: _jsonHeaders, body: jsonEncode(payload));

      if (res.statusCode == 200) {
        _snack(esEdicion ? 'Plan actualizado y usuarios notificados.' : 'Plan creado exitosamente.');
        _fetchPlanes();
      } else {
        _snack('Error: ${res.body}');
      }
    } catch (e) {
      _snack('Error de red: $e');
    }
  }

  Future<void> _alternarEstado(Map<String, dynamic> plan) async {
    final activo = plan['activo'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(activo ? 'Desactivar plan' : 'Activar plan'),
        content: Text('¿Seguro que quieres ${activo ? 'desactivar' : 'activar'} el plan "${plan['nombre']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, continuar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final res = await http.put(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/planes/${plan['id']}/toggle'),
        headers: _jsonHeaders,
      );
      if (res.statusCode == 200) {
        _snack('Plan "${plan['nombre']}" ${activo ? 'desactivado' : 'activado'} correctamente.');
        _fetchPlanes();
      } else {
        _snack('Error al cambiar el estado del plan.');
      }
    } catch (e) {
      _snack('Error de red: $e');
    }
  }

  Future<void> _eliminarPlan(Map<String, dynamic> plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descontinuar plan'),
        content: Text('¿Deseas descontinuar el plan "${plan['nombre']}"? Se enviará un aviso automático a todos los propietarios suscritos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descontinuar plan'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final res = await http.delete(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/planes/${plan['id']}'),
        headers: _jsonHeaders,
      );
      if (res.statusCode == 200) {
        _snack('Plan "${plan['nombre']}" descontinuado y usuarios notificados.');
        _fetchPlanes();
      } else {
        _snack('Error al descontinuar el plan.');
      }
    } catch (e) {
      _snack('Error de red: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Planes de Suscripción'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: const Color(0xFFF9FBF9),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFFC107),
        foregroundColor: const Color(0xFF1B3022),
        onPressed: () => _abrirFormulario(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _planes.isEmpty
              ? const Center(child: Text('No hay planes registrados', style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _fetchPlanes,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _planes.length,
                    itemBuilder: (context, index) {
                      final item = Map<String, dynamic>.from(_planes[index]);
                      final activo = item['activo'] == true;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const CircleAvatar(
                                    backgroundColor: Color(0xFFFFC107),
                                    child: Icon(Icons.star, color: Color(0xFF1B3022)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item['nombre'] ?? 'Plan', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        Text('\$${item['precio_mensual'] ?? '0.00'}/mes', style: const TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: activo ? Colors.green.shade100 : Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      activo ? 'Activo' : 'Inactivo',
                                      style: TextStyle(fontSize: 10, color: activo ? Colors.green.shade900 : Colors.grey.shade700, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              if (item['descripcion'] != null) ...[
                                const SizedBox(height: 8),
                                Text(item['descripcion'], style: const TextStyle(fontSize: 13)),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _abrirFormulario(plan: item)),
                                  IconButton(
                                    icon: Icon(activo ? Icons.toggle_on : Icons.toggle_off, color: activo ? Colors.green : Colors.grey),
                                    onPressed: () => _alternarEstado(item),
                                  ),
                                  IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _eliminarPlan(item)),
                                ],
                              ),
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
