import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Explorador de Datos Avanzado (versión móvil del panel que ya existe en
/// la web de administración): busca usuarios, dispositivos IoT,
/// suscripciones y grupos reales con los mismos filtros, y exporta el
/// resultado a CSV/PDF o lo envía por correo. Los botones de exportación
/// permanecen bloqueados hasta que el admin presiona "Buscar", igual que en
/// la web — así lo que se exporta es siempre lo que se filtró a propósito.
class AdminExportarDatosScreen extends StatefulWidget {
  const AdminExportarDatosScreen({super.key});

  @override
  State<AdminExportarDatosScreen> createState() => _AdminExportarDatosScreenState();
}

class _AdminExportarDatosScreenState extends State<AdminExportarDatosScreen> {
  static const _clay = Color(0xFF1B3022);
  static const _cream = Color(0xFFF8FAF8);
  static const _gold = Color(0xFFF9A826);

  static const _categorias = ['Todos', 'Usuario', 'Dispositivo IoT', 'Suscripción', 'Grupo'];
  static const _estados = ['Todos', 'Activa', 'Sancionado', 'Bloqueado'];

  final _buscarCtrl = TextEditingController();
  String _categoria = 'Todos';
  String _estado = 'Todos';
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  bool _isLoading = false;
  bool _busquedaRealizada = false;
  String? _errorBusqueda;
  List<dynamic> _registros = [];

  int? _totalRegistros;
  double? _tasaCrecimiento;

  String? _exportando;
  String? _errorExportar;

  @override
  void initState() {
    super.initState();
    _cargarMetricas();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Map<String, String> get _authHeaders => {'Authorization': 'Bearer ${AuthService.token}'};

  Future<void> _cargarMetricas() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/explorador/metricas'),
        headers: _authHeaders,
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() {
          _totalRegistros = (data['total_registros'] as num?)?.toInt();
          _tasaCrecimiento = (data['tasa_crecimiento_pct'] as num?)?.toDouble();
        });
      }
    } catch (_) {}
  }

  String _fmtFecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, String> _paramsFiltro() {
    final params = <String, String>{};
    if (_categoria != 'Todos') params['categoria'] = _categoria;
    if (_estado != 'Todos') params['estado'] = _estado;
    if (_buscarCtrl.text.trim().isNotEmpty) params['q'] = _buscarCtrl.text.trim();
    if (_fechaDesde != null) params['fechaDesde'] = _fmtFecha(_fechaDesde!);
    if (_fechaHasta != null) params['fechaHasta'] = _fmtFecha(_fechaHasta!);
    return params;
  }

  Future<void> _buscar() async {
    setState(() {
      _isLoading = true;
      _errorBusqueda = null;
    });
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/admin/explorador')
          .replace(queryParameters: _paramsFiltro());
      final res = await http.get(uri, headers: _authHeaders);
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
        if (mounted) {
          setState(() {
            _registros = data;
            _busquedaRealizada = true;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorBusqueda = 'No se pudo cargar (código ${res.statusCode}).';
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorBusqueda = 'No se pudo conectar con el servidor.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _exportar(String formato) async {
    setState(() {
      _exportando = formato;
      _errorExportar = null;
    });
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/admin/explorador/$formato')
          .replace(queryParameters: _paramsFiltro());
      final res = await http.get(uri, headers: _authHeaders);
      if (res.statusCode == 200) {
        final mime = formato == 'csv' ? 'text/csv' : 'application/pdf';
        final file = XFile.fromData(res.bodyBytes, name: 'explorador-datos.$formato', mimeType: mime);
        await SharePlus.instance.share(
          ShareParams(files: [file], subject: 'Explorador de Datos — Huellitas'),
        );
      } else {
        setState(() => _errorExportar = 'No se pudo generar el ${formato.toUpperCase()} (código ${res.statusCode}).');
      }
    } catch (_) {
      setState(() => _errorExportar = 'No se pudo generar el ${formato.toUpperCase()}.');
    } finally {
      if (mounted) setState(() => _exportando = null);
    }
  }

  Future<void> _enviarReportePorCorreo() async {
    final emailCtrl = TextEditingController(text: AuthService.userData?['email'] ?? '');
    String formato = 'csv';
    final resultado = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: EdgeInsets.only(
                left: 24, right: 24, top: 24,
                bottom: 24 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enviar Reporte', style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.bold, color: _clay)),
                  const SizedBox(height: 4),
                  Text('${_registros.length} registros del filtro actual', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Correo destino',
                      filled: true,
                      fillColor: _cream,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _formatoChip('CSV', formato == 'csv', () => setModalState(() => formato = 'csv')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _formatoChip('PDF', formato == 'pdf', () => setModalState(() => formato = 'pdf')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, {'email': emailCtrl.text.trim(), 'formato': formato}),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _clay,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Enviar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (resultado == null || !resultado['email']!.contains('@')) return;
    if (!mounted) return;

    try {
      final body = jsonEncode({
        'email': resultado['email'],
        'formato': resultado['formato'],
        'categoria': _categoria != 'Todos' ? _categoria : null,
        'estado': _estado != 'Todos' ? _estado : null,
        'q': _buscarCtrl.text.trim().isNotEmpty ? _buscarCtrl.text.trim() : null,
        'fechaDesde': _fechaDesde != null ? _fmtFecha(_fechaDesde!) : null,
        'fechaHasta': _fechaHasta != null ? _fmtFecha(_fechaHasta!) : null,
      });
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/explorador/enviar-reporte'),
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: body,
      );
      final ok = res.statusCode == 200 && (jsonDecode(utf8.decode(res.bodyBytes))['ok'] == true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? 'Reporte enviado correctamente.' : 'No se pudo enviar el reporte.'),
          backgroundColor: ok ? _clay : Colors.red.shade700,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('No se pudo enviar el reporte.'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  Widget _formatoChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _clay : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _clay : Colors.grey.shade300),
        ),
        alignment: Alignment.center,
        child: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: selected ? Colors.white : Colors.grey.shade700)),
      ),
    );
  }

  Future<void> _elegirFecha(bool esDesde) async {
    final ahora = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: (esDesde ? _fechaDesde : _fechaHasta) ?? ahora,
      firstDate: DateTime(2020),
      lastDate: ahora,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _clay)),
        child: child!,
      ),
    );
    if (elegida != null) {
      setState(() {
        if (esDesde) {
          _fechaDesde = elegida;
        } else {
          _fechaHasta = elegida;
        }
      });
    }
  }

  Color _estadoColor(String estado) {
    switch (estado) {
      case 'Activa':
        return const Color(0xFF15803D);
      case 'Sancionado':
        return const Color(0xFF92400E);
      case 'Bloqueado':
        return const Color(0xFFBA1A1A);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        title: Text('Explorador de Datos', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
        backgroundColor: _clay,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFiltros(),
            const SizedBox(height: 20),
            _buildMetricas(),
            const SizedBox(height: 20),
            _buildAcciones(),
            const SizedBox(height: 24),
            _buildResultados(),
          ],
        ),
      ),
    );
  }

  Widget _clayCard({required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(color: _clay.withOpacity(0.06), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: child,
      );

  Widget _buildFiltros() {
    return _clayCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Buscar', style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.bold, color: _clay)),
          const SizedBox(height: 4),
          Text('Filtra por categoría, estado y fecha de registro real.', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          TextField(
            controller: _buscarCtrl,
            decoration: InputDecoration(
              hintText: 'Nombre, correo o ID...',
              prefixIcon: const Icon(Icons.search_outlined),
              filled: true,
              fillColor: _cream,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
            onSubmitted: (_) => _buscar(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _dropdown(_categoria, _categorias, (v) => setState(() => _categoria = v!))),
              const SizedBox(width: 8),
              Expanded(child: _dropdown(_estado, _estados, (v) => setState(() => _estado = v!))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _fechaBoton('Desde', _fechaDesde, () => _elegirFecha(true))),
              const SizedBox(width: 8),
              Expanded(child: _fechaBoton('Hasta', _fechaHasta, () => _elegirFecha(false))),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _buscar,
              icon: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search_outlined),
              label: Text(_isLoading ? 'Buscando...' : 'Buscar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _clay,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(String value, List<String> opciones, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: _cream, borderRadius: BorderRadius.circular(16)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: [for (final o in opciones) DropdownMenuItem(value: o, child: Text(o, style: GoogleFonts.inter(fontSize: 13)))],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _fechaBoton(String label, DateTime? fecha, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: _cream, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                fecha == null ? label : _fmtFecha(fecha),
                style: GoogleFonts.inter(fontSize: 12, color: fecha == null ? Colors.grey.shade600 : _clay, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricas() {
    return Row(
      children: [
        Expanded(
          child: _clayCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.trending_up, color: _gold, size: 20),
                const SizedBox(height: 8),
                Text(
                  _tasaCrecimiento != null ? '${_tasaCrecimiento! >= 0 ? '+' : ''}${_tasaCrecimiento!.toStringAsFixed(1)}%' : 'N/D',
                  style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.bold, color: _clay),
                ),
                Text('Crecimiento mensual', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _clayCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.storage_outlined, color: _gold, size: 20),
                const SizedBox(height: 8),
                Text('${_totalRegistros ?? '—'}', style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.bold, color: _clay)),
                Text('Registros totales', style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAcciones() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _clay,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: _clay.withOpacity(0.3), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Acciones de Exportación', style: GoogleFonts.playfairDisplay(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(
            _busquedaRealizada ? '${_registros.length} registros listos para exportar' : 'Busca primero para desbloquear',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 14),
          _accionBoton(
            icon: _exportando == 'csv' ? Icons.hourglass_top : Icons.file_download_outlined,
            label: _exportando == 'csv' ? 'Generando...' : 'Exportar a CSV',
            onTap: _busquedaRealizada && _exportando == null ? () => _exportar('csv') : null,
          ),
          const SizedBox(height: 10),
          _accionBoton(
            icon: _exportando == 'pdf' ? Icons.hourglass_top : Icons.picture_as_pdf_outlined,
            label: _exportando == 'pdf' ? 'Generando...' : 'Exportar a PDF',
            onTap: _busquedaRealizada && _exportando == null ? () => _exportar('pdf') : null,
          ),
          const SizedBox(height: 10),
          _accionBoton(
            icon: Icons.mail_outline,
            label: 'Enviar Reporte por Correo',
            onTap: _busquedaRealizada ? _enviarReportePorCorreo : null,
          ),
          if (_errorExportar != null) ...[
            const SizedBox(height: 10),
            Text(_errorExportar!, style: GoogleFonts.inter(fontSize: 11, color: Colors.red.shade200)),
          ],
        ],
      ),
    );
  }

  Widget _accionBoton({required IconData icon, required String label, required VoidCallback? onTap}) {
    final habilitado = onTap != null;
    return Material(
      color: Colors.white.withOpacity(habilitado ? 0.12 : 0.05),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: habilitado ? _gold : Colors.white30),
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: habilitado ? Colors.white : Colors.white30),
              ),
              if (!habilitado) ...[
                const Spacer(),
                const Icon(Icons.lock_outline, size: 14, color: Colors.white24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultados() {
    if (!_busquedaRealizada && !_isLoading) {
      return _clayCard(
        child: Column(
          children: [
            Icon(Icons.search_outlined, size: 32, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Ajusta los filtros y presiona Buscar para ver resultados reales.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    if (_isLoading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()));
    }
    if (_errorBusqueda != null) {
      return _clayCard(child: Text(_errorBusqueda!, style: GoogleFonts.inter(color: Colors.red.shade700)));
    }
    if (_registros.isEmpty) {
      return _clayCard(
        child: Text('Sin registros que coincidan con el filtro.', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_registros.length} registros encontrados', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _clay)),
        const SizedBox(height: 12),
        for (final r in _registros) _buildRegistroCard(r as Map),
      ],
    );
  }

  Widget _buildRegistroCard(Map r) {
    final estado = (r['estado'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: _clay.withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r['nombre']?.toString() ?? '—',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: _clay),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _estadoColor(estado).withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
                child: Text(estado, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: _estadoColor(estado))),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${r['categoria'] ?? ''} · ID ${r['id'] ?? ''}${r['correo'] != null ? ' · ${r['correo']}' : ''}',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if ([r['camaras_conectadas'], r['iot_implementado'], r['mascotas'], r['plan']].any((v) => v != null)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (r['camaras_conectadas'] != null) _statChip(Icons.videocam_outlined, '${r['camaras_conectadas']} cám.'),
                if (r['iot_implementado'] != null) _statChip(Icons.memory_outlined, 'IoT: ${r['iot_implementado']}'),
                if (r['mascotas'] != null) _statChip(Icons.pets_outlined, '${r['mascotas']} mascotas'),
                if (r['plan'] != null) _statChip(Icons.card_membership_outlined, r['plan'].toString()),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: _cream, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: _clay),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: _clay)),
        ],
      ),
    );
  }
}
