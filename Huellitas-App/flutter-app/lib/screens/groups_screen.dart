import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'community_screen.dart' show mostrarAdvertenciaModeracion;

/// Grupos temáticos de la comunidad: crear/unirse a un grupo y chatear con
/// sus miembros, con reacciones y borrado de mensajes propios.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  bool _isLoading = true;
  List<dynamic> _grupos = [];
  Map<String, dynamic>? _grupoActivo;
  List<dynamic> _mensajes = [];
  bool _isLoadingMensajes = false;
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  Map<String, String> get _jsonHeaders => {
        'Authorization': 'Bearer ${AuthService.token}',
        'Content-Type': 'application/json',
      };

  int? get _usuarioId {
    final id = AuthService.userData?['id'];
    return id is int ? id : int.tryParse(id?.toString() ?? '');
  }

  @override
  void initState() {
    super.initState();
    _cargarGrupos();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarGrupos() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos?usuarioId=$_usuarioId'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() => _grupos = data is List ? data : []);
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _crearGrupo() async {
    final nombreCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo grupo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 8),
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Descripción (opcional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
        ],
      ),
    );
    if (ok != true || nombreCtrl.text.trim().length < 2) return;

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos').replace(queryParameters: {
        'nombre': nombreCtrl.text.trim(),
        'descripcion': descCtrl.text.trim(),
        'creadoPor': _usuarioId.toString(),
      });
      final res = await http.post(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      if (res.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grupo creado exitosamente.')));
        _cargarGrupos();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al crear el grupo.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _unirseYAbrir(Map<String, dynamic> grupo) async {
    if (grupo['es_miembro'] != true) {
      try {
        final uri = Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/${grupo['id']}/unirse')
            .replace(queryParameters: {'usuarioId': _usuarioId.toString()});
        await http.post(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      } catch (_) {}
    }
    _abrirChat(grupo);
  }

  Future<void> _abrirChat(Map<String, dynamic> grupo) async {
    setState(() {
      _grupoActivo = grupo;
      _mensajes = [];
    });
    await _cargarMensajes(grupo['id']);
  }

  Future<void> _cargarMensajes(dynamic grupoId) async {
    setState(() => _isLoadingMensajes = true);
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/$grupoId/mensajes')
          .replace(queryParameters: {'usuarioId': _usuarioId.toString()});
      final res = await http.get(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() => _mensajes = data is List ? data : []);
        _scrollToEnd();
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingMensajes = false);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  /// Envía el mensaje redactado en el chat del grupo. Si el backend
  /// responde con una advertencia de moderación, se le pregunta al usuario
  /// si quiere enviarlo de todas formas antes de reenviar con
  /// `confirmado=true`; si es grave, ya quedó bloqueado con un strike.
  Future<void> _enviarMensaje({String? textoAConfirmar, bool confirmado = false}) async {
    final texto = textoAConfirmar ?? _msgCtrl.text.trim();
    final grupo = _grupoActivo;
    if (texto.isEmpty || grupo == null) return;
    if (textoAConfirmar == null) _msgCtrl.clear();
    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/${grupo['id']}/mensajes'),
        headers: _jsonHeaders,
        body: jsonEncode({'usuarioId': _usuarioId, 'contenido': texto, 'confirmado': confirmado}),
      );
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}

      if (res.statusCode == 200 && body?['advertencia'] == true) {
        if (!mounted) return;
        final seguir = await mostrarAdvertenciaModeracion(context, body?['mensaje'] ?? 'Este contenido podría romper nuestras reglas.');
        if (seguir) await _enviarMensaje(textoAConfirmar: texto, confirmado: true);
        return;
      }

      if (res.statusCode == 200) {
        _cargarMensajes(grupo['id']);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body?['error'] ?? 'Error al enviar el mensaje.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _enviarImagen([File? archivo, bool confirmado = false]) async {
    final grupo = _grupoActivo;
    if (grupo == null) return;

    File file;
    if (archivo != null) {
      file = archivo;
    } else {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.single.path == null) return;
      file = File(result.files.single.path!);
      final sizeBytes = await file.length();
      if (sizeBytes > 5 * 1024 * 1024) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La imagen debe ser menor a 5MB.')));
        return;
      }
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/${grupo['id']}/mensajes'),
      );
      request.headers['Authorization'] = 'Bearer ${AuthService.token}';
      request.fields['usuarioId'] = _usuarioId.toString();
      request.fields['contenido'] = '';
      request.fields['confirmado'] = confirmado.toString();
      // Ver la misma nota en community_screen.dart: se fuerza extensión y
      // content-type válidos para que una foto de cámara no se rechace.
      final rawExt = file.path.contains('.') ? file.path.split('.').last.toLowerCase() : '';
      const extAMime = {
        'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
        'webp': 'image/webp', 'gif': 'image/gif',
        'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm',
      };
      final ext = extAMime.containsKey(rawExt) ? rawExt : 'jpg';
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: 'archivo.$ext',
        contentType: MediaType.parse(extAMime[ext]!),
      ));
      final streamed = await request.send();
      final bodyBytes = await streamed.stream.toBytes();
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}

      if (streamed.statusCode == 200 && body?['advertencia'] == true) {
        if (!mounted) return;
        final seguir = await mostrarAdvertenciaModeracion(context, body?['mensaje'] ?? 'Este contenido podría romper nuestras reglas.');
        if (seguir) await _enviarImagen(file, true);
        return;
      }

      if (streamed.statusCode == 200) {
        _cargarMensajes(grupo['id']);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body?['error'] ?? 'Error al enviar la imagen.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _reaccionar(Map<String, dynamic> msg) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/mensaje/${msg['id']}/reaccionar')
          .replace(queryParameters: {'usuarioId': _usuarioId.toString()});
      final res = await http.post(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() {
          final added = data['action'] == 'added';
          msg['liked_by_me'] = added;
          msg['likes_count'] = ((msg['likes_count'] ?? 0) as num) + (added ? 1 : -1);
          if ((msg['likes_count'] as num) < 0) msg['likes_count'] = 0;
        });
      }
    } catch (_) {}
  }

  /// Solo se puede editar un mensaje propio dentro de los primeros 5
  /// minutos — pasado ese tiempo el backend ya no lo permite, solo queda
  /// eliminarlo (para todos o solo para uno mismo).
  bool _puedeEditarMensaje(Map<String, dynamic> msg) {
    if (msg['usuario_id'].toString() != _usuarioId.toString()) return false;
    final creado = DateTime.tryParse(msg['created_at']?.toString() ?? '');
    if (creado == null) return false;
    return DateTime.now().difference(creado).inMinutes < 5;
  }

  Future<void> _editarMensaje(Map<String, dynamic> msg) async {
    final ctrl = TextEditingController(text: msg['contenido']);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar mensaje'),
        content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    if (nuevo == null || nuevo.isEmpty || nuevo == msg['contenido']) return;

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/mensaje/${msg['id']}')
          .replace(queryParameters: {'usuarioId': _usuarioId.toString(), 'contenido': nuevo});
      final res = await http.put(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      if (res.statusCode == 200) {
        setState(() => msg['contenido'] = nuevo);
      } else if (mounted) {
        Map<String, dynamic>? body;
        try {
          body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body?['error'] ?? 'No se pudo editar el mensaje.')));
      }
    } catch (_) {}
  }

  Future<void> _eliminarMensaje(Map<String, dynamic> msg) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/mensaje/${msg['id']}')
          .replace(queryParameters: {'usuarioId': _usuarioId.toString()});
      final res = await http.delete(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      if (res.statusCode == 200) {
        _cargarMensajes(_grupoActivo!['id']);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo eliminar el mensaje.')));
      }
    } catch (_) {}
  }

  /// Oculta el mensaje solo para el usuario en sesión ("eliminar para mí")
  /// — sigue visible para los demás miembros del grupo.
  Future<void> _ocultarMensajeParaMi(Map<String, dynamic> msg) async {
    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/ocultar'),
        headers: _jsonHeaders,
        body: jsonEncode({'usuarioId': _usuarioId, 'tipo': 'PUBLICACION_GRUPO', 'contenidoId': msg['id']}),
      );
      if (res.statusCode == 200) {
        _cargarMensajes(_grupoActivo!['id']);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo ocultar el mensaje.')));
      }
    } catch (_) {}
  }

  /// Denuncia un mensaje ajeno del grupo ante moderación.
  Future<void> _denunciarMensaje(Map<String, dynamic> msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Denunciar mensaje'),
        content: Text('¿Quieres denunciar este mensaje de ${msg['autor_nombre'] ?? 'este usuario'} ante moderación?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Denunciar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/mensaje/${msg['id']}/reportar'),
        headers: _jsonHeaders,
        body: jsonEncode({'reportadorId': _usuarioId, 'motivo': 'Contenido ofensivo reportado desde el chat del grupo'}),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.statusCode == 200 ? 'Denuncia enviada a moderación.' : 'No se pudo enviar la denuncia.')));
      }
    } catch (_) {}
  }

  void _cerrarChat() {
    setState(() {
      _grupoActivo = null;
      _mensajes = [];
    });
    _cargarGrupos();
  }

  /// Muestra la lista de miembros del grupo activo (solo visible para el
  /// ADMIN del grupo) con opciones para expulsar o transferir la
  /// administración a cada uno, y un botón para eliminar el grupo entero.
  Future<void> _abrirGestionMiembros() async {
    final grupo = _grupoActivo;
    if (grupo == null) return;
    List<dynamic> miembros = [];
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/${grupo['id']}/miembros'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        miembros = data is List ? data : [];
      }
    } catch (_) {}
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gestionar "${grupo['nombre']}"', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: miembros.isEmpty
                  ? const Center(child: Text('Cargando miembros...', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: miembros.length,
                      itemBuilder: (context, index) {
                        final miembro = Map<String, dynamic>.from(miembros[index]);
                        final esAdmin = miembro['rol_en_grupo'] == 'ADMIN';
                        return ListTile(
                          leading: CircleAvatar(backgroundColor: const Color(0xFF1B3022), child: Text((miembro['nombre'] ?? '?')[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
                          title: Text(miembro['nombre'] ?? 'Usuario'),
                          subtitle: esAdmin ? const Text('Administrador', style: TextStyle(color: Color(0xFFB98900), fontWeight: FontWeight.bold, fontSize: 12)) : null,
                          trailing: esAdmin
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.workspace_premium_outlined, color: Colors.amber),
                                      tooltip: 'Transferir administración',
                                      onPressed: () async {
                                        Navigator.pop(ctx);
                                        await _transferirAdmin(miembro);
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.person_remove_outlined, color: Colors.red),
                                      tooltip: 'Expulsar del grupo',
                                      onPressed: () async {
                                        Navigator.pop(ctx);
                                        await _expulsarMiembro(miembro);
                                      },
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Eliminar grupo por completo'),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _eliminarGrupoActivo();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _expulsarMiembro(Map<String, dynamic> miembro) async {
    final grupo = _grupoActivo;
    if (grupo == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Expulsar miembro'),
        content: Text('¿Expulsar a ${miembro['nombre']} del grupo "${grupo['nombre']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Expulsar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/${grupo['id']}/expulsar')
          .replace(queryParameters: {'adminId': _usuarioId.toString(), 'usuarioId': miembro['id'].toString()});
      final res = await http.post(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.statusCode == 200 ? '${miembro['nombre']} fue expulsado.' : 'No se pudo expulsar al miembro.')));
      }
    } catch (_) {}
  }

  Future<void> _transferirAdmin(Map<String, dynamic> miembro) async {
    final grupo = _grupoActivo;
    if (grupo == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transferir administración'),
        content: Text('¿Hacer a ${miembro['nombre']} el nuevo administrador de "${grupo['nombre']}"? Perderás los permisos de administrador.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Transferir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/${grupo['id']}/transferir-admin')
          .replace(queryParameters: {'adminId': _usuarioId.toString(), 'nuevoAdminId': miembro['id'].toString()});
      final res = await http.post(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      if (res.statusCode == 200) {
        _cerrarChat();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo transferir la administración.')));
      }
    } catch (_) {}
  }

  Future<void> _eliminarGrupoActivo() async {
    final grupo = _grupoActivo;
    if (grupo == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar grupo'),
        content: Text('¿Eliminar el grupo "${grupo['nombre']}" por completo? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar grupo')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/social/grupos/${grupo['id']}')
          .replace(queryParameters: {'adminId': _usuarioId.toString()});
      final res = await http.delete(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      if (res.statusCode == 200) {
        _cerrarChat();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo eliminar el grupo.')));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: Text(_grupoActivo != null ? _grupoActivo!['nombre'] ?? 'Grupo' : 'Grupos'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: Colors.white,
        leading: _grupoActivo != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _cerrarChat) : null,
        actions: _grupoActivo != null && _grupoActivo!['rol_en_grupo'] == 'ADMIN'
            ? [IconButton(icon: const Icon(Icons.admin_panel_settings_outlined), tooltip: 'Gestionar grupo', onPressed: _abrirGestionMiembros)]
            : null,
      ),
      floatingActionButton: _grupoActivo == null
          ? FloatingActionButton(backgroundColor: const Color(0xFFFFC107), onPressed: _crearGrupo, child: const Icon(Icons.add))
          : null,
      body: _grupoActivo != null ? _buildChat() : _buildGruposList(),
    );
  }

  Widget _buildGruposList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_grupos.isEmpty) {
      return const Center(child: Text('No hay grupos todavía. Crea uno con el botón +.', style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _cargarGrupos,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _grupos.length,
        itemBuilder: (context, index) {
          final grupo = Map<String, dynamic>.from(_grupos[index]);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF1B3022), child: Icon(Icons.groups, color: Colors.white)),
              title: Text(grupo['nombre'] ?? 'Grupo', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${grupo['descripcion'] ?? ''} · ${grupo['total_miembros'] ?? 0} miembros'),
              trailing: grupo['es_miembro'] == true
                  ? const Icon(Icons.chevron_right)
                  : const Chip(label: Text('Unirse', style: TextStyle(fontSize: 11))),
              onTap: () => _unirseYAbrir(grupo),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChat() {
    return Column(
      children: [
        Expanded(
          child: _isLoadingMensajes
              ? const Center(child: CircularProgressIndicator())
              : _mensajes.isEmpty
                  ? const Center(child: Text('Sé el primero en escribir en este grupo.', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: _mensajes.length,
                      itemBuilder: (context, index) {
                        final msg = Map<String, dynamic>.from(_mensajes[index]);
                        final esMio = msg['usuario_id'].toString() == _usuarioId.toString();
                        return _buildMensajeBubble(msg, esMio);
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.image_outlined, color: Color(0xFF1B3022)),
                  onPressed: _enviarImagen,
                ),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _enviarMensaje(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFF1B3022),
                  child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 18), onPressed: _enviarMensaje),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// `true` si [texto] es una URL "pelada" que apunta directo a una imagen
  /// (ej. un GIF compartido cuyo contenido es solo el link). Sin esto, ese
  /// tipo de mensaje se veía como texto plano en vez de la imagen.
  bool _esUrlDeImagen(String? texto) {
    if (texto == null) return false;
    final t = texto.trim();
    if (!t.startsWith('http://') && !t.startsWith('https://')) return false;
    final sinQuery = t.split('?').first.toLowerCase();
    return sinQuery.endsWith('.jpg') || sinQuery.endsWith('.jpeg') ||
        sinQuery.endsWith('.png') || sinQuery.endsWith('.gif') ||
        sinQuery.endsWith('.webp');
  }

  Widget _buildMensajeBubble(Map<String, dynamic> msg, bool esMio) {
    return Align(
      alignment: esMio ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => showModalBottomSheet(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (esMio && _puedeEditarMensaje(msg))
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Editar mensaje'),
                    subtitle: const Text('Disponible los primeros 5 minutos', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _editarMensaje(msg);
                    },
                  ),
                if (esMio || (_grupoActivo?['rol_en_grupo'] == 'ADMIN'))
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text('Eliminar para todos'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _eliminarMensaje(msg);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Eliminar solo para mí'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _ocultarMensajeParaMi(msg);
                  },
                ),
                if (!esMio)
                  ListTile(
                    leading: const Icon(Icons.flag_outlined, color: Colors.orange),
                    title: const Text('Denunciar'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _denunciarMensaje(msg);
                    },
                  ),
              ],
            ),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: esMio ? const Color(0xFF1B3022) : Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!esMio)
                Text(msg['autor_nombre'] ?? 'Usuario', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
              if (ApiService.resolveMediaUrl(msg['imagen_url']) != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      ApiService.resolveMediaUrl(msg['imagen_url'])!,
                      width: 180,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              if ((msg['contenido'] as String?)?.isNotEmpty == true)
                _esUrlDeImagen(msg['contenido'])
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          msg['contenido'],
                          width: 180,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Text(msg['contenido'], style: TextStyle(color: esMio ? Colors.white : Colors.black87)),
                        ),
                      )
                    : Text(msg['contenido'], style: TextStyle(color: esMio ? Colors.white : Colors.black87)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _reaccionar(msg),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      msg['liked_by_me'] == true ? Icons.favorite : Icons.favorite_border,
                      size: 14,
                      color: msg['liked_by_me'] == true ? Colors.redAccent : (esMio ? Colors.white70 : Colors.grey),
                    ),
                    if ((msg['likes_count'] ?? 0) > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${msg['likes_count']}',
                        style: TextStyle(fontSize: 11, color: esMio ? Colors.white70 : Colors.grey.shade600),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
