import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Lista de suscripciones de todas las casas, con el plan contratado y el
/// estado del pago (activa, cancelada, vencida) de cada una.
class AdminSubscriptionsScreen extends StatefulWidget {
  const AdminSubscriptionsScreen({super.key});

  @override
  State<AdminSubscriptionsScreen> createState() => _AdminSubscriptionsScreenState();
}

class _AdminSubscriptionsScreenState extends State<AdminSubscriptionsScreen> {
  bool _isLoading = true;
  List<dynamic> _suscripciones = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/suscripciones'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200) {
        setState(() => _suscripciones = jsonDecode(utf8.decode(res.bodyBytes)));
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Color _colorEstado(String estado) {
    switch (estado.toUpperCase()) {
      case 'ACTIVA':
      case 'ACTIVO':
        return Colors.green;
      case 'CANCELADA':
      case 'VENCIDA':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Suscripciones'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _suscripciones.isEmpty
              ? const Center(child: Text('No hay suscripciones registradas', style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _suscripciones.length,
                    itemBuilder: (context, index) {
                      final s = _suscripciones[index];
                      final estado = (s['estado'] ?? '').toString();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Color(0xFF1B3022), child: Icon(Icons.credit_card, color: Colors.white, size: 18)),
                          title: Text(s['usuario_nombre'] ?? 'Usuario'),
                          subtitle: Text('${s['plan_nombre'] ?? 'Plan'} · ${s['usuario_email'] ?? ''}'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: _colorEstado(estado).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                            child: Text(estado, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _colorEstado(estado))),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
