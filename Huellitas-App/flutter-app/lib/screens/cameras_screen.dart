import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/webrtc_viewer.dart';
import 'webrtc_camera_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'qr_scanner_screen.dart';

/// Lista de cámaras IoT de la casa: muestra su video en vivo (vía WebRTC),
/// permite asignarles la mascota que vigilan, agregar una cámara nueva por
/// código QR y eliminar cámaras existentes.
class CamerasScreen extends StatefulWidget {
  const CamerasScreen({super.key});

  @override
  State<CamerasScreen> createState() => _CamerasScreenState();
}

class _CamerasScreenState extends State<CamerasScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCameras();
  }

  /// El `casa_id` no siempre llega con el mismo nombre según el rol y el
  /// origen de la sesión (login normal, QR de miembro, token de Google), así
  /// que lo buscamos en todas sus variantes. Antes, un miembro cuyo id venía
  /// como `casaId` o anidado en `casa` no cargaba ninguna cámara.
  int? _resolveCasaId() {
    final u = AuthService.userData;
    final raw = u?['casa_id'] ?? u?['casaId'] ?? u?['casa']?['id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  Future<void> _fetchCameras() async {
    final api = Provider.of<ApiService>(context, listen: false);

    final casaId = _resolveCasaId();
    if (casaId != null && AuthService.token != null) {
      await api.fetchCamaras(casaId, AuthService.token!);
      // Las mascotas vienen en el dashboard de la casa; se necesitan para
      // poder elegir cuál vigila cada cámara.
      if (api.dashboardData == null) {
        await api.fetchDashboard(casaId, AuthService.token!);
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = Provider.of<ApiService>(context);
    final isPropietario = AuthService.userData?['rol'] == 'PROPIETARIO';

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: _buildAppBar(),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : _buildCamerasGrid(api.camarasData),
      floatingActionButton: isPropietario ? FloatingActionButton.extended(
        onPressed: () => _showAddCameraDialog(context, api),
        backgroundColor: const Color(0xFF1B3022),
        icon: const Icon(Icons.add_a_photo, color: Color(0xFFFFC107)),
        label: const Text('Emitir desde este dispositivo', style: TextStyle(color: Color(0xFFFFC107))),
      ) : null,
    );
  }

  void _showAddCameraDialog(BuildContext context, ApiService api) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emitir Cámara WebRTC'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Esta acción convertirá este dispositivo en una cámara de seguridad en vivo.'),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre de Ubicación (ej: Sala)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          TextButton.icon(
            icon: const Icon(Icons.wifi_find, size: 18),
            label: const Text('Buscar en mi red'),
            onPressed: () {
              Navigator.pop(ctx);
              _mostrarBusquedaEnRed(nameCtrl.text.trim());
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B3022), foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await Navigator.push<String>(
                context,
                MaterialPageRoute(builder: (_) => const QrScannerScreen()),
              );
              
              if (result != null && result.isNotEmpty) {
                try {
                  final data = jsonDecode(result);
                  if (data is Map && data['action'] == 'link_camera') {
                    setState(() => _isLoading = true);
                    try {
                      await _postCameraVincular(
                        data['nombre'], 
                        data['urlStream'], 
                        data['casaId'], 
                        AuthService.token!
                      );
                      await _fetchCameras();
                      if (mounted) {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => WebRtcCameraScreen(urlStream: data['urlStream'])
                        ));
                      }
                    } catch (e) {
                      setState(() => _isLoading = false);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                } catch (_) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR no válido')));
                }
              }
            },
            child: const Text('Escanear QR Web'),
          ),
        ],
      ),
    );
  }

  /// Consulta al backend qué dispositivos del hogar reportaron su latido hace
  /// poco. El celular no rastrea la red por su cuenta: la lista sale de los
  /// aparatos que se anunciaron solos, igual que en la web.
  Future<Map<String, dynamic>?> _buscarDispositivos() async {
    try {
      final r = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/dispositivo/descubrir?soloLibres=true'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {
      // Sin conexión o respuesta inesperada: se trata como "no encontrado".
    }
    return null;
  }

  /// Adopta para esta vivienda un aparato que está latiendo y no tiene dueño,
  /// y devuelve el identificador con el que quedó registrado.
  ///
  /// Es el paso previo a vincularlo como cámara: un aparato nunca adoptado no
  /// existe todavía en la tabla de dispositivos, así que no hay nada que
  /// vincular hasta que esta llamada lo cree.
  Future<int?> _reclamarDispositivo(String mac, String nombre) async {
    try {
      final r = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/dispositivo/reclamar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'mac': mac, 'nombre': nombre, 'categoria': 'CAMARA'}),
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final cuerpo = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        return (cuerpo['dispositivo']?['id'] as num?)?.toInt();
      }
    } catch (_) {
      // Sin conexión o respuesta inesperada: se trata como fallo de alta.
    }
    return null;
  }

  /// Da de alta como cámara un dispositivo encontrado en la red, reclamándolo
  /// antes si todavía no pertenecía a esta vivienda.
  Future<bool> _vincularDispositivo(Map<String, dynamic> disp, String nombre) async {
    var dispositivoId = (disp['id'] as num?)?.toInt();

    if (dispositivoId == null) {
      final mac = disp['mac_address']?.toString();
      if (mac == null || mac.isEmpty) return false;
      dispositivoId = await _reclamarDispositivo(mac, nombre);
      if (dispositivoId == null) return false;
    }

    try {
      final r = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/camaras/vincular-dispositivo'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'dispositivoId': dispositivoId, 'nombre': nombre}),
      ).timeout(const Duration(seconds: 12));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Hoja inferior con los dispositivos del hogar detectados, para vincular
  /// uno como cámara sin pasar por el código QR.
  void _mostrarBusquedaEnRed(String nombreSugerido) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BuscarEnRedSheet(
        nombreSugerido: nombreSugerido,
        buscar: _buscarDispositivos,
        vincular: _vincularDispositivo,
        alVincular: () async {
          await _fetchCameras();
        },
      ),
    );
  }

  Future<void> _postCameraVincular(String name, String url, int casaId, String token) async {
    final response = await http.post(
      Uri.parse('${ApiService.baseUrl}/huellitas/camaras/vincular'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: '{"casaId": $casaId, "nombre": "$name", "urlStream": "$url"}',
    );
    if (response.statusCode != 200) {
      throw Exception('Error al vincular cámara');
    }
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        '📷 Cámaras en Vivo',
        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 22),
      ),
      backgroundColor: const Color(0xFFF9FBF9),
      foregroundColor: const Color(0xFF1B3022),
      elevation: 0,
      centerTitle: false,
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF1B3022)),
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchCameras();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCamerasGrid(List<dynamic>? camaras) {
    if (camaras == null || camaras.isEmpty) {
      return _buildEmptyState();
    }

    final isPropietario = AuthService.userData?['rol'] == 'PROPIETARIO';

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: camaras.length,
      itemBuilder: (context, index) {
        final camara = camaras[index];
        return _buildCameraCard(
          camaraId: camara['id'],
          title: camara['nombre'] ?? 'Cámara',
          streamUrl: camara['urlStream'] ?? '',
          conectada: camara['conectada'] == true,
          isPropietario: isPropietario,
          camara: camara,
        ).animate().fadeIn(delay: (index * 60).ms, duration: 250.ms).slideY(begin: 0.05, end: 0);
      },
    );
  }

  Widget _buildCameraCard({
    required int? camaraId,
    required String title,
    required String streamUrl,
    required bool conectada,
    required bool isPropietario,
    required Map<String, dynamic> camara,
  }) {
    String? targetStream;
    if (streamUrl.startsWith('webrtc:')) {
      targetStream = streamUrl;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardHeader(camaraId, title, conectada, streamUrl, isPropietario),
          if (camaraId != null) _buildMascotaRow(camaraId, camara, isPropietario),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: targetStream != null
                  ? (conectada 
                      ? WebRtcViewer(key: ValueKey(streamUrl), targetStream: targetStream)
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 16),
                              Text('Conectando a Cámara...', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ))
                  : const Center(child: Text('Formato no soportado', style: TextStyle(color: Colors.white))),
            ),
          ),
          _buildCardFooter(isWebRtc: targetStream != null, conectada: conectada),
        ],
      ),
    );
  }

  Widget _buildCardHeader(int? camaraId, String title, bool conectada, String streamUrl, bool isPropietario) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1B3022).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.videocam, size: 20, color: Color(0xFF1B3022)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.outfit(
                color: const Color(0xFF1B3022),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFC107).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 8, color: Color(0xFFFFC107)),
                const SizedBox(width: 4),
                Text(
                  conectada ? 'CONECTADA' : 'DESCONECTADA',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: conectada ? const Color(0xFFB38600) : Colors.red,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // El visor se abre siempre, igual que en la web: si nadie está
          // transmitiendo todavía, dentro se ve el estado de la conexión. Antes
          // el botón desaparecía cuando la cámara no estaba conectada, así que
          // no había forma de abrirlo ni de saber qué pasaba.
          IconButton(
            icon: const Icon(Icons.picture_in_picture_alt),
            tooltip: conectada ? 'Ver en flotante' : 'Ver estado de la cámara',
            onPressed: () {
              _showPiPViewer(context, streamUrl);
            },
          ),
          if (isPropietario && camaraId != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmarEliminacion(camaraId, title),
            ),
        ],
      ),
    );
  }

  /// Fila que muestra —y deja cambiar— la mascota que vigila la cámara.
  /// Solo el propietario puede reasignarla; el miembro la ve pero no la edita.
  Widget _buildMascotaRow(int camaraId, Map<String, dynamic> camara, bool isPropietario) {
    final api = Provider.of<ApiService>(context);
    final perros = (api.dashboardData?['perros'] as List<dynamic>?) ?? const [];
    final perroId = camara['perroId'] as int?;
    final fotoUrl = ApiService.resolveMediaUrl(camara['perroFotoUrl'] as String?);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
      color: Colors.white,
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF1B3022).withOpacity(0.08),
            backgroundImage: fotoUrl != null ? NetworkImage(fotoUrl) : null,
            child: fotoUrl == null
                ? const Icon(Icons.pets, size: 14, color: Color(0xFF1B3022))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: isPropietario
                ? DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      isExpanded: true,
                      value: perros.any((p) => p['id'] == perroId) ? perroId : null,
                      hint: Text('Sin mascota asignada',
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
                      items: <DropdownMenuItem<int?>>[
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Sin mascota asignada',
                              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
                        ),
                        ...perros.map((p) => DropdownMenuItem<int?>(
                              value: p['id'] as int?,
                              child: Text(p['nombre']?.toString() ?? 'Mascota',
                                  style: GoogleFonts.inter(fontSize: 13)),
                            )),
                      ],
                      onChanged: (nuevo) => _asignarMascota(camaraId, nuevo),
                    ),
                  )
                : Text(
                    camara['perroNombre']?.toString() ?? 'Sin mascota asignada',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _asignarMascota(int camaraId, int? perroId) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.asignarMascotaCamara(camaraId, perroId, AuthService.token!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo asignar la mascota: $e')),
        );
      }
    }
  }

  void _confirmarEliminacion(int camaraId, String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cámara'),
        content: Text('¿Estás seguro que deseas eliminar la cámara "$title"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                final api = Provider.of<ApiService>(context, listen: false);
                await api.deleteCamara(camaraId, AuthService.token!);
                await _fetchCameras();
              } catch (e) {
                setState(() => _isLoading = false);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  OverlayEntry? _pipEntry;

  void _showPiPViewer(BuildContext context, String streamUrl) {
    if (_pipEntry != null) return;
    
    _pipEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 80,
        right: 20,
        child: Draggable(
          feedback: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 200,
              height: 150,
              color: Colors.black,
              child: WebRtcViewer(key: ValueKey(streamUrl + "_pip"), targetStream: streamUrl),
            ),
          ),
          childWhenDragging: Container(),
          child: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Container(
              width: 200,
              height: 150,
              color: Colors.black,
              child: Stack(
                children: [
                  WebRtcViewer(key: ValueKey(streamUrl + "_pip"), targetStream: streamUrl),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        _pipEntry?.remove();
                        _pipEntry = null;
                      },
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_pipEntry!);
  }

  Widget _buildCardFooter({bool isWebRtc = false, bool conectada = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: Colors.grey.shade50),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fiber_manual_record, size: 10, color: Colors.greenAccent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    conectada ? 'Transmitiendo' : 'Fuera de línea',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: conectada ? Colors.green : Colors.red
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isWebRtc ? Icons.shield : Icons.wifi, size: 16, color: Colors.indigoAccent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isWebRtc ? 'Conexión Segura P2P' : 'Red Local',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.indigoAccent, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1B3022).withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.videocam_off, size: 64, color: Color(0xFF1B3022)),
          ),
          const SizedBox(height: 24),
          Text(
            'Sin Cámaras',
            style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF1B3022)),
          ),
          const SizedBox(height: 8),
          Text(
            'Tu sistema no tiene cámaras configuradas.\nComunícate con tu administrador.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Hoja de búsqueda de dispositivos del hogar para vincularlos como cámara.
///
/// Vive en su propio widget con estado porque el listado se recarga sin
/// cerrar la hoja, y así el `setState` no repinta toda la pantalla de cámaras.
class _BuscarEnRedSheet extends StatefulWidget {
  final String nombreSugerido;
  final Future<Map<String, dynamic>?> Function() buscar;
  final Future<bool> Function(Map<String, dynamic> disp, String nombre) vincular;
  final Future<void> Function() alVincular;

  const _BuscarEnRedSheet({
    required this.nombreSugerido,
    required this.buscar,
    required this.vincular,
    required this.alVincular,
  });

  @override
  State<_BuscarEnRedSheet> createState() => _BuscarEnRedSheetState();
}

class _BuscarEnRedSheetState extends State<_BuscarEnRedSheet> {
  late final TextEditingController _nombreCtrl;
  bool _buscando = true;
  bool _vinculando = false;
  int _ventanaSegundos = 30;
  List<dynamic> _dispositivos = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.nombreSugerido);
    _buscar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() {
      _buscando = true;
      _error = null;
    });
    final res = await widget.buscar();
    setState(() {
      _buscando = false;
      if (res == null) {
        _error = 'No se pudo consultar los dispositivos del hogar.';
      } else {
        _ventanaSegundos = (res['ventanaSegundos'] as num?)?.toInt() ?? 30;
        _dispositivos = (res['dispositivos'] as List?) ?? [];
      }
    });
  }

  String _codigoVivienda = 'Cargando...';
  bool _cargandoCodigo = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cargandoCodigo && _codigoVivienda == 'Cargando...') {
      _cargarCodigoVivienda();
    }
  }

  Future<void> _cargarCodigoVivienda() async {
    final dash = context.read<ApiService>().dashboardData;
    if (dash == null) return;
    final casaId = (dash['casa'] != null) ? (dash['casa']['id'] as num?)?.toInt() : null;
    if (casaId == null) return;

    final codigo = await context.read<ApiService>().obtenerCodigoVivienda(casaId);
    if (!mounted) return;
    setState(() {
      _codigoVivienda = codigo ?? 'No disponible';
      _cargandoCodigo = false;
    });
  }

  Future<void> _regenerarCodigo() async {
    final dash = context.read<ApiService>().dashboardData;
    if (dash == null) return;
    final casaId = (dash['casa'] != null) ? (dash['casa']['id'] as num?)?.toInt() : null;
    if (casaId == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Regenerar Código?'),
        content: const Text('Si regeneras el código, todas las placas que usan el actual dejarán de funcionar hasta que las actualices con el nuevo. ¿Estás seguro?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Regenerar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() {
      _cargandoCodigo = true;
      _codigoVivienda = 'Regenerando...';
    });

    final nuevoCodigo = await context.read<ApiService>().regenerarCodigoVivienda(casaId);
    if (!mounted) return;
    setState(() {
      _codigoVivienda = nuevoCodigo ?? 'Error';
      _cargandoCodigo = false;
    });
  }

  Future<void> _vincular(Map<String, dynamic> d) async {
    // Un aparato de otra vivienda se muestra para explicar por qué no está
    // disponible, pero no se puede tomar: la MAC solo pertenece a una casa.
    if (d['propiedad'] == 'OCUPADO') {
      setState(() => _error = 'Ese dispositivo pertenece a otra cuenta.');
      return;
    }

    final nombre = _nombreCtrl.text.trim().isNotEmpty
        ? _nombreCtrl.text.trim()
        : (d['modelo'] ?? d['mac_address']).toString();

    setState(() {
      _vinculando = true;
      _error = null;
    });
    final ok = await widget.vincular(d, nombre);
    if (!mounted) return;
    setState(() => _vinculando = false);

    if (ok) {
      await widget.alVincular();
      if (mounted) Navigator.pop(context);
    } else {
      setState(() => _error = 'No se pudo vincular ese dispositivo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    const verde = Color(0xFF1B3022);
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_find, color: verde),
              const SizedBox(width: 10),
              Text('Buscar en mi red',
                  style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold, color: verde)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: verde),
                onPressed: _buscando ? null : _buscar,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Aparecen los dispositivos de tu hogar que se reportaron en los últimos $_ventanaSegundos segundos.',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          
          // Caja del Código de Vivienda
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade200),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Código de Vivienda', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                    InkWell(
                      onTap: _cargandoCodigo ? null : _regenerarCodigo,
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Row(
                          children: [
                            if (_cargandoCodigo) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                            else Icon(Icons.refresh, size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text('Regenerar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Identifica tu casa ante las placas ESP32. Cópialo en el firmware.', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                const SizedBox(height: 8),
                SelectableText(
                  _codigoVivienda,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _nombreCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre para la cámara',
              hintText: 'Ej: Sala principal',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),

          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
            ),

          if (_buscando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_dispositivos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.developer_board_off, size: 34, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  const Text('No encontramos dispositivos',
                      style: TextStyle(fontWeight: FontWeight.bold, color: verde)),
                  const SizedBox(height: 4),
                  const Text(
                    'Enciende el dispositivo y espera unos segundos, o vincula un celular con el código QR.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Colors.black54),
                  ),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _dispositivos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = _dispositivos[i] as Map<String, dynamic>;
                  final ocupado = d['propiedad'] == 'OCUPADO';
                  final color = ocupado ? Colors.grey.shade600 : verde;
                  final ip = d['ip_local'];

                  return ListTile(
                    enabled: !ocupado && !_vinculando,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: ocupado ? Colors.grey.shade200 : const Color(0x141B3022),
                      child: Icon(Icons.memory, color: color, size: 20),
                    ),
                    title: Text('${d['modelo'] ?? d['mac_address']}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
                    subtitle: Text(
                        ocupado
                            ? 'Ya está vinculado a otra cuenta'
                            : '${d['mac_address']} · activo hace ${d['hace_segundos']}s'
                                '${ip != null ? ' · $ip' : ''}',
                        style: const TextStyle(fontSize: 12)),
                    trailing: _vinculando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                            ocupado ? 'Ocupado' : (d['propiedad'] == 'LIBRE' ? 'Añadir' : 'Vincular'),
                            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                    onTap: (_vinculando || ocupado) ? null : () => _vincular(d),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}