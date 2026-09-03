import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Panel de administración con los dispositivos IoT de todas las viviendas,
/// agrupados por usuario: la vivienda cuyos aparatos están todos conformes se
/// muestra colapsada, y solo se abre sola la que tiene algo real que revisar
/// (nunca dio señal, lleva más de 24 h sin darla, o quedó en estado de error).
/// Misma lógica y mismo endpoint que el panel equivalente de la web.
class AdminDevicesScreen extends StatefulWidget {
  const AdminDevicesScreen({super.key});

  @override
  State<AdminDevicesScreen> createState() => _AdminDevicesScreenState();
}

/// Los dispositivos de una vivienda, agrupados para no repetir la casa en cada fila.
class _CasaAgrupada {
  final int casaId;
  final String casaNombre;
  final String propietario;
  final List<Map<String, dynamic>> dispositivos = [];
  bool conforme = true;

  _CasaAgrupada(this.casaId, this.casaNombre, this.propietario);
}

class _AdminDevicesScreenState extends State<AdminDevicesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final token = AuthService.token;
    if (token != null) {
      final api = context.read<ApiService>();
      await api.fetchAdminDevices(token);
    }
  }

  /// Agrupa la respuesta plana del backend (una fila por dispositivo, con su
  /// casa y propietario) en una entrada por vivienda.
  List<_CasaAgrupada> _agrupar(List<dynamic> devices) {
    final porCasa = <int, _CasaAgrupada>{};
    for (final raw in devices) {
      final d = Map<String, dynamic>.from(raw as Map);
      final casaId = (d['casa_id'] as num?)?.toInt() ?? 0;
      final grupo = porCasa.putIfAbsent(
        casaId,
        () => _CasaAgrupada(
          casaId,
          d['casa_nombre'] as String? ?? 'Sin nombre',
          d['propietario_nombre'] as String? ??
              d['propietario_email'] as String? ??
              'Sin propietario',
        ),
      );
      grupo.dispositivos.add(d);
      if (d['problema'] != null) grupo.conforme = false;
    }
    // Primero las viviendas con algo que revisar, para no tener que buscar
    // cuál falló entre las que están bien.
    final lista = porCasa.values.toList();
    lista.sort((a, b) {
      if (a.conforme == b.conforme) return 0;
      return a.conforme ? 1 : -1;
    });
    return lista;
  }

  /// Precarga un mensaje razonable según el problema real detectado y deja que
  /// el administrador lo edite antes de enviarlo al dueño del dispositivo.
  Future<void> _abrirAviso(Map<String, dynamic> d) async {
    final problema = d['problema'] as String?;
    final nombre = d['modelo'] as String? ?? d['categoria'] as String? ?? 'dispositivo';
    final controlador = TextEditingController(
      text: problema != null
          ? 'Notamos que tu dispositivo "$nombre" tiene un problema: '
              '${problema.toLowerCase()}. Revisa que esté encendido y conectado a tu red WiFi.'
          : 'Sobre tu dispositivo "$nombre": ',
    );
    bool enviando = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Avisar a ${d['propietario_nombre'] ?? 'este usuario'}',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'El mensaje llega a su bandeja de notificaciones.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controlador,
                maxLines: 4,
                style: GoogleFonts.inter(fontSize: 13),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: enviando ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B3022),
                foregroundColor: Colors.white,
              ),
              onPressed: enviando
                  ? null
                  : () async {
                      final mensaje = controlador.text.trim();
                      if (mensaje.isEmpty) return;
                      setDialogState(() => enviando = true);
                      final ok = await _enviarAviso(d['id'], mensaje);
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok
                              ? 'Aviso enviado al propietario.'
                              : 'No se pudo enviar el aviso.'),
                        ),
                      );
                    },
              child: Text(enviando ? 'Enviando...' : 'Enviar'),
            ),
          ],
        ),
      ),
    );
    controlador.dispose();
  }

  Future<bool> _enviarAviso(dynamic dispositivoId, String mensaje) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/iot/dispositivos/$dispositivoId/avisar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'mensaje': mensaje}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiService>();
    final devices = api.adminDevicesData;
    final isLoading = api.isLoading;
    final casas = devices == null ? <_CasaAgrupada>[] : _agrupar(devices);
    final conProblema = casas.where((c) => !c.conforme).length;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.memory, color: Color(0xFF1B3022)),
                      const SizedBox(width: 8),
                      Text(
                        'Monitoreo IoT',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1B3022),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Text(
                      'SOLO LECTURA',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                casas.isEmpty
                    ? 'Dispositivos IoT de todas las viviendas.'
                    : conProblema == 0
                        ? '${casas.length} ${casas.length == 1 ? "vivienda" : "viviendas"} · todo conforme'
                        : '$conProblema de ${casas.length} ${casas.length == 1 ? "vivienda necesita" : "viviendas necesitan"} revisión',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              if (isLoading && devices == null)
                const Center(child: CircularProgressIndicator())
              else if (casas.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      'No hay dispositivos IoT registrados en la plataforma.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: Colors.grey.shade500),
                    ),
                  ),
                )
              else
                ...casas.map(_buildCasa),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCasa(_CasaAgrupada casa) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: casa.conforme ? Colors.grey.shade200 : const Color(0xFFBA1A1A).withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // La vivienda con algo que revisar se abre sola; la conforme se queda
          // cerrada para no llenar la pantalla de aparatos que están bien.
          initiallyExpanded: !casa.conforme,
          leading: Icon(
            casa.conforme ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: casa.conforme ? Colors.green.shade600 : const Color(0xFFBA1A1A),
          ),
          title: Text(
            casa.casaNombre,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: const Color(0xFF1B3022),
            ),
          ),
          subtitle: Text(
            '${casa.propietario} · ${casa.dispositivos.length} ${casa.dispositivos.length == 1 ? "dispositivo" : "dispositivos"}',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
          ),
          children: casa.dispositivos.map(_buildDeviceItem).toList(),
        ),
      ),
    );
  }

  Widget _buildDeviceItem(Map<String, dynamic> device) {
    // `en_linea` y `problema` los calcula el backend con los datos reales de
    // ultima_conexion y estado. Antes esta tarjeta pintaba "EN LÍNEA" fijo,
    // sin mirar ningún campo, y leía device['nombre'], que no existe.
    final enLinea = device['en_linea'] == true;
    final problema = device['problema'] as String?;
    final nombre = device['modelo'] as String? ?? device['categoria'] as String? ?? 'Dispositivo IoT';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.developer_board, color: Color(0xFF1B3022), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nombre,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: const Color(0xFF1B3022),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: enLinea ? Colors.green.shade50 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      enLinea ? Icons.wifi : Icons.wifi_off,
                      size: 12,
                      color: enLinea ? Colors.green.shade700 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      enLinea ? 'EN LÍNEA' : 'SIN SEÑAL',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: enLinea ? Colors.green.shade700 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildInfoRow('MAC:', device['mac_address'] as String? ?? 'Desconocida'),
          if (device['zona_nombre'] != null) ...[
            const SizedBox(height: 2),
            _buildInfoRow('Zona:', device['zona_nombre'] as String),
          ],
          if (problema != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFDAD6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 15, color: Color(0xFFBA1A1A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      problema,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFBA1A1A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _abrirAviso(device),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1B3022),
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.send_outlined, size: 15),
              label: Text(
                'Avisar a este usuario',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade800,
            ),
          ),
        ),
      ],
    );
  }
}
