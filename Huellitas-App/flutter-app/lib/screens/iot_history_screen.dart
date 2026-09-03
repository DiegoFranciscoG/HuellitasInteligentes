import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Historial de lecturas y activaciones de un dispositivo IoT de la casa:
/// permite elegir el dispositivo y ver, según el filtro, sus lecturas de
/// sensores o el registro de activaciones de actuadores.
class IotHistoryScreen extends StatefulWidget {
  const IotHistoryScreen({super.key});

  @override
  State<IotHistoryScreen> createState() => _IotHistoryScreenState();
}

class _IotHistoryScreenState extends State<IotHistoryScreen> {
  bool _isLoadingDevices = true;
  bool _isLoadingHistory = false;
  List<dynamic> _dispositivos = [];
  List<dynamic> _historial = [];
  List<dynamic> _actuadores = [];
  int? _selectedDeviceId;
  bool _mostrandoActuadores = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetchDispositivos();
    // Antes el historial solo se pedía al elegir un dispositivo, así que una
    // acción hecha en otra pantalla (o por otro miembro de la casa) no se
    // veía aquí hasta salir y volver a entrar. Se refresca cada 10s.
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final id = _selectedDeviceId;
      if (id != null) {
        _fetchHistorial(id);
        _fetchActuadores(id);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDispositivos() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/dispositivo/casa'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _dispositivos = _etiquetar(jsonDecode(utf8.decode(response.bodyBytes)));
            _isLoadingDevices = false;
            if (_dispositivos.isNotEmpty) {
              _selectedDeviceId = _dispositivos[0]['id'];
              _fetchHistorial(_selectedDeviceId!);
              _fetchActuadores(_selectedDeviceId!);
            }
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingDevices = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDevices = false);
    }
  }

  /// Reduce el `modelo` real de cada dispositivo ("Ventana Cocina", "Luz
  /// Comedor") a su primera palabra ("Ventana", "Luz"), y numera los que
  /// comparten esa palabra clave (dos luces -> "Luz 1"/"Luz 2"). El nombre
  /// de la habitación no aporta nada para elegir un dispositivo en una lista
  /// tan corta, y alarga las pestañas del selector sin necesidad.
  List<dynamic> _etiquetar(List<dynamic> dispositivos) {
    String palabraDe(dynamic d) {
      final modelo = (d['modelo'] as String? ?? '').trim();
      if (modelo.isEmpty) return 'Dispositivo #${d['id']}';
      return modelo.split(RegExp(r'\s+')).first;
    }

    final total = <String, int>{};
    for (final d in dispositivos) {
      final palabra = palabraDe(d);
      total[palabra] = (total[palabra] ?? 0) + 1;
    }
    final vistos = <String, int>{};
    return dispositivos.map((d) {
      final palabra = palabraDe(d);
      if ((total[palabra] ?? 1) <= 1) {
        return {...d, 'etiqueta': palabra};
      }
      final n = (vistos[palabra] ?? 0) + 1;
      vistos[palabra] = n;
      return {...d, 'etiqueta': '$palabra $n'};
    }).toList();
  }

  Future<void> _fetchHistorial(int deviceId) async {
    setState(() {
      _isLoadingHistory = true;
      _historial = [];
    });

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/dispositivo/$deviceId/historial'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _historial = jsonDecode(utf8.decode(response.bodyBytes));
            _isLoadingHistory = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingHistory = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _fetchActuadores(int deviceId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/dispositivo/$deviceId/actuadores'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );
      if (response.statusCode == 200 && mounted) {
        setState(() => _actuadores = jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (_) {}
  }

  String _formatFecha(String? raw) {
    final date = DateTime.tryParse(raw ?? '')?.toLocal();
    if (date == null) return raw ?? '';
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Historial IoT'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: const Color(0xFFF9FBF9),
        elevation: 0,
      ),
      body: _isLoadingDevices
          ? const Center(child: CircularProgressIndicator())
          : _dispositivos.isEmpty
              ? const Center(child: Text('No hay dispositivos IoT en tu casa', style: TextStyle(color: Colors.grey)))
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: DropdownButtonFormField<int>(
                        value: _selectedDeviceId,
                        decoration: InputDecoration(
                          labelText: 'Seleccionar Dispositivo',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: _dispositivos.map((d) {
                          return DropdownMenuItem<int>(
                            value: d['id'],
                            child: Text(d['etiqueta'] ?? 'Dispositivo ${d['id']}'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedDeviceId = val);
                            _fetchHistorial(val);
                            _fetchActuadores(val);
                          }
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Sensores'), icon: Icon(Icons.sensors)),
                          ButtonSegment(value: true, label: Text('Comandos'), icon: Icon(Icons.settings_remote)),
                        ],
                        selected: {_mostrandoActuadores},
                        onSelectionChanged: (sel) => setState(() => _mostrandoActuadores = sel.first),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _mostrandoActuadores ? _buildActuadoresList() : _buildSensorList(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSensorList() {
    if (_isLoadingHistory) return const Center(child: CircularProgressIndicator());
    if (_historial.isEmpty) {
      return const Center(child: Text('No hay historial de sensores para este dispositivo', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _historial.length,
      itemBuilder: (context, index) {
        final item = _historial[index];
        // fn_historial_sensor devuelve valor, unidad, ts — no
        // valor_registrado/evento/fecha_hora, que nunca existieron y por
        // eso esta tarjeta siempre mostraba "N/A" y "Registro".
        final unidad = item['unidad'] as String?;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF1B3022),
              child: Icon(Icons.data_usage, color: Colors.white, size: 18),
            ),
            title: Text('Valor: ${item['valor'] ?? 'N/A'}${unidad != null ? ' $unidad' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: Text(_formatFecha(item['ts']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        );
      },
    );
  }

  Widget _buildActuadoresList() {
    if (_actuadores.isEmpty) {
      return const Center(child: Text('No hay comandos registrados para este dispositivo', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _actuadores.length,
      itemBuilder: (context, index) {
        final item = _actuadores[index];
        // El backend (fn_historial_actuador) nunca devolvió `estado` ni
        // `parametro` — esos dos siempre venían vacíos. Lo real que sí
        // manda es `origen` (APP/REGLA) y, si lo hizo una persona,
        // `ejecutado_por_nombre`.
        final esApp = item['origen'] == 'APP';
        final color = esApp ? const Color(0xFF1B3022) : const Color(0xFF8A6A00);
        final ejecutor = item['ejecutado_por_nombre'] as String?;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(Icons.settings_remote, color: color, size: 18),
            ),
            title: Text('${item['comando'] ?? 'Comando'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(esApp && ejecutor != null ? 'App · por $ejecutor' : (esApp ? 'App' : 'Automático')),
            trailing: Text(_formatFecha(item['created_at']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        );
      },
    );
  }
}
