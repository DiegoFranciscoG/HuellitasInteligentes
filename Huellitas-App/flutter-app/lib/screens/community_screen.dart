import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'package:google_fonts/google_fonts.dart';

/// Muestra la advertencia de moderación que devuelve el backend (contenido
/// que podría romper las reglas, pero no lo suficientemente grave como para
/// bloquearlo directamente) y deja que el usuario decida si continúa. Se
/// reutiliza tanto al publicar como al comentar, en el feed y en grupos.
Future<bool> mostrarAdvertenciaModeracion(BuildContext context, String mensaje) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Revisa tu contenido'),
      content: Text(mensaje),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Publicar de todas formas'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Feed social de la comunidad de dueños de mascotas: publicar (con foto),
/// buscar por hashtags, reaccionar, comentar y denunciar publicaciones o
/// comentarios inapropiados.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  bool _isLoading = true;
  List<dynamic> _posts = [];
  StompClient? _stompClient;
  bool _isPosting = false;
  final TextEditingController _postCtrl = TextEditingController();
  File? _selectedPostImage;

  final TextEditingController _searchCtrl = TextEditingController();
  String _busquedaActiva = '';
  List<dynamic> _hashtags = [];

  @override
  void initState() {
    super.initState();
    _fetchFeed();
    _fetchHashtags();
    _connectStomp();
  }

  void _connectStomp() {
    final wsUrl = ApiService.baseUrl.replaceFirst('http', 'ws').replaceAll('/api', '') + '/ws/websocket';
    _stompClient = StompClient(
      config: StompConfig(
        url: wsUrl,
        onConnect: (frame) {
          _stompClient?.subscribe(
            destination: '/topic/social/feed',
            callback: (frame) {
              if (mounted) {
                _fetchFeed();
              }
            },
          );
        },
      ),
    );
    _stompClient?.activate();
  }

  @override
  void dispose() {
    _stompClient?.deactivate();
    _postCtrl.dispose();
    super.dispose();
  }

  /// Con búsqueda activa consulta el endpoint filtrado; sin ella, el feed
  /// normal. Ambos devuelven la misma estructura, así que se pintan igual.
  Future<void> _fetchFeed() async {
    try {
      final usuarioId = AuthService.userData?['id'];
      final uri = _busquedaActiva.isEmpty
          ? Uri.parse('${ApiService.baseUrl}/huellitas/social/feed?usuarioId=$usuarioId')
          : Uri.parse('${ApiService.baseUrl}/huellitas/social/buscar').replace(queryParameters: {
              'usuarioId': usuarioId.toString(),
              'q': _busquedaActiva,
            });

      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      });

      if (response.statusCode == 200 && mounted) {
        setState(() => _posts = jsonDecode(utf8.decode(response.bodyBytes)));
      }
    } catch (_) {
      // Sin conexión o respuesta inesperada: se deja el feed como estaba.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchHashtags() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/hashtags?limite=12'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (res.statusCode == 200 && mounted) {
        setState(() => _hashtags = jsonDecode(utf8.decode(res.bodyBytes)));
      }
    } catch (_) {}
  }

  void _buscar(String termino) {
    setState(() {
      _busquedaActiva = termino.trim();
      _isLoading = true;
    });
    _fetchFeed();
  }

  Future<void> _pickPostImage(StateSetter setModalState) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final sizeBytes = await file.length();
      if (sizeBytes > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La imagen debe ser menor a 5MB.')),
          );
        }
        return;
      }
      setModalState(() => _selectedPostImage = file);
    }
  }

  /// Publica el post redactado. Si el backend responde con una advertencia
  /// de moderación (contenido riesgoso pero no grave), se le muestra al
  /// usuario y, si decide continuar, se reenvía la misma petición con
  /// `confirmado=true`. Si el contenido es grave, el backend ya lo bloqueó
  /// con un strike — solo queda mostrar el motivo.
  Future<void> _createPost({bool confirmado = false}) async {
    if (_postCtrl.text.trim().isEmpty) return;
    setState(() => _isPosting = true);
    try {
      final usuarioId = AuthService.userData?['id'];
      http.StreamedResponse streamed;

      if (_selectedPostImage != null) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${ApiService.baseUrl}/huellitas/social/publicacion/upload'),
        );
        request.headers['Authorization'] = 'Bearer ${AuthService.token}';
        request.fields['usuarioId'] = usuarioId.toString();
        request.fields['contenido'] = _postCtrl.text;
        request.fields['confirmado'] = confirmado.toString();
        // El backend exige que la extensión Y el content-type coincidan con
        // un tipo conocido (JPG/PNG/WEBP/GIF/MP4/MOV/WEBM) para aceptar el
        // archivo. Una foto tomada con la cámara del celular a veces llega
        // aquí con una ruta temporal sin extensión reconocible, y
        // MultipartFile.fromPath() adivina el content-type a partir de esa
        // ruta — si no reconoce nada, manda "application/octet-stream" y el
        // backend la rechaza con "Tipo de archivo no permitido", aunque sea
        // una foto normal. Se fuerza un nombre y content-type válidos según
        // la extensión real del archivo (o JPG si no se puede determinar).
        final path = _selectedPostImage!.path;
        final rawExt = path.contains('.') ? path.split('.').last.toLowerCase() : '';
        const extAMime = {
          'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
          'webp': 'image/webp', 'gif': 'image/gif',
          'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm',
        };
        final ext = extAMime.containsKey(rawExt) ? rawExt : 'jpg';
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          path,
          filename: 'archivo.$ext',
          contentType: MediaType.parse(extAMime[ext]!),
        ));
        streamed = await request.send();
      } else {
        // El backend tiene dos endpoints POST /publicacion superpuestos: uno
        // que espera JSON en el body y otro por parámetros de URL. Antes esta
        // llamada mandaba los datos por query string pero con
        // Content-Type: application/json y el body vacío — Spring la
        // enrutaba al que espera JSON, que fallaba al no encontrar nada que
        // parsear, y el post nunca se creaba. Ahora se manda un body JSON de
        // verdad, que es lo que ese Content-Type promete.
        final response = await http.post(
          Uri.parse('${ApiService.baseUrl}/huellitas/social/publicacion'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${AuthService.token}',
          },
          body: jsonEncode({
            'usuarioId': usuarioId,
            'contenido': _postCtrl.text,
            'confirmado': confirmado,
          }),
        );
        streamed = http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode);
      }

      final bodyBytes = await streamed.stream.toBytes();
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}

      if (streamed.statusCode == 200 && body?['advertencia'] == true) {
        setState(() => _isPosting = false);
        if (!mounted) return;
        final seguir = await mostrarAdvertenciaModeracion(context, body?['mensaje'] ?? 'Este contenido podría romper nuestras reglas.');
        if (seguir) await _createPost(confirmado: true);
        return;
      }

      if (streamed.statusCode == 200) {
        _postCtrl.clear();
        _selectedPostImage = null;
        if (mounted) Navigator.pop(context);
        _fetchFeed();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body?['error'] ?? 'Error al publicar.')));
      }
    } catch (_) {}
    if (mounted) setState(() => _isPosting = false);
  }

  Future<void> _reportPost(int postId) async {
    final motivoCtrl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reportar publicación'),
        content: TextField(
          controller: motivoCtrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Cuéntanos por qué reportas esta publicación', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, motivoCtrl.text.trim().isEmpty ? 'Contenido inapropiado' : motivoCtrl.text.trim()),
            child: const Text('Reportar'),
          ),
        ],
      ),
    );
    if (motivo == null) return;

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/publicacion/$postId/reportar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'reportadorId': AuthService.userData?['id'], 'motivo': motivo}),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.statusCode == 200 ? 'Publicación reportada. Gracias por avisarnos.' : 'No se pudo enviar el reporte.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Usa el mismo endpoint que la web (`/reacciones/publicacion/...`).
  /// El anterior (`/social/publicacion/{id}/reaccionar`) ignora el parámetro
  /// `tipo` y solo hace un like simple, por eso cualquier emoji elegido en la
  /// app aparecía como "me gusta" en la web.
  Future<void> _toggleLike(dynamic post, String reaction) async {
    final postId = post['id'];
    final quitar = _miReaccion(post) == reaction;
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/huellitas/reacciones/publicacion/$postId').replace(
        queryParameters: {
          'usuarioId': AuthService.userData?['id'].toString() ?? '',
          'tipo': reaction,
          'quitar': quitar.toString(),
        },
      );
      await http.post(uri, headers: {'Authorization': 'Bearer ${AuthService.token}'});
      _fetchFeed();
    } catch (_) {}
  }

  Future<void> _deletePost(int postId) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Publicación'),
        content: const Text('¿Estás seguro que deseas eliminar esta publicación?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                final response = await http.delete(
                  Uri.parse('${ApiService.baseUrl}/huellitas/social/publicacion/$postId?usuarioId=${AuthService.userData?['id']}'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer ${AuthService.token}',
                  },
                );
                if (response.statusCode == 200) {
                  _fetchFeed();
                } else {
                  if (mounted) {
                    setState(() => _isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al eliminar la publicación')));
                  }
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editPost(Map<String, dynamic> post) async {
    final TextEditingController ctrl = TextEditingController(text: post['contenido']);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar Publicación'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != post['contenido']) {
      try {
        final response = await http.put(
          Uri.parse('${ApiService.baseUrl}/huellitas/social/publicacion/${post['id']}?usuarioId=${AuthService.userData?['id']}&contenido=${Uri.encodeComponent(result)}'),
          headers: {'Authorization': 'Bearer ${AuthService.token}'},
        );
        if (response.statusCode == 200) {
          _fetchFeed();
        } else if (mounted) {
          Map<String, dynamic>? body;
          try {
            body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          } catch (_) {}
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body?['error'] ?? 'No se pudo editar la publicación.')));
        }
      } catch (_) {}
    }
  }

  void _showCommentsModal(int postId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CommentsWidget(postId: postId),
    );
  }

  void _showPostModal() {
    _selectedPostImage = null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Crear Publicación', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1B3022))),
              const SizedBox(height: 16),
              TextField(
                controller: _postCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '¿Qué estás pensando?',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
              ),
              const SizedBox(height: 12),
              if (_selectedPostImage != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_selectedPostImage!, height: 160, width: double.infinity, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => setModalState(() => _selectedPostImage = null),
                        child: const CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                )
              else
                OutlinedButton.icon(
                  onPressed: () => _pickPostImage(setModalState),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Agregar imagen'),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF9A826), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _isPosting ? null : _createPost,
                  child: _isPosting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Publicar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  bool _isAuthor(dynamic authorId) {
    if (authorId == null || AuthService.userData?['id'] == null) return false;
    return authorId.toString() == AuthService.userData?['id'].toString();
  }

  /// Solo el autor puede borrar lo suyo. El rol PROPIETARIO es un usuario
  /// normal dentro de la comunidad: no debe poder borrar publicaciones ajenas.
  /// El ADMINISTRADOR sí, porque es quien modera la plataforma.
  bool _canDelete(dynamic authorId) {
    final rol = AuthService.rol ?? AuthService.userData?['rol'];
    return _isAuthor(authorId) || rol == 'ADMINISTRADOR';
  }

  /// Solo se puede editar lo propio, y solo dentro de los primeros 5
  /// minutos — el backend ya lo exige, esto es para no mostrar el botón
  /// cuando de todas formas va a fallar.
  bool _canEdit(Map<String, dynamic> post) {
    if (!_isAuthor(post['autor_id'])) return false;
    final creado = DateTime.tryParse(post['created_at']?.toString() ?? '');
    if (creado == null) return false;
    return DateTime.now().difference(creado).inMinutes < 5;
  }

  /// Oculta la publicación solo para el usuario en sesión ("eliminar para
  /// mí") — sigue visible para todos los demás.
  Future<void> _hidePostForMe(int postId) async {
    final usuarioId = AuthService.userData?['id'];
    if (usuarioId == null) return;
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/ocultar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'usuarioId': usuarioId, 'tipo': 'PUBLICACION', 'contenidoId': postId}),
      );
      if (response.statusCode == 200) {
        _fetchFeed();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo ocultar la publicación.')));
      }
    } catch (_) {}
  }

  ImageProvider? _safeImage(String? url) {
    final resolved = ApiService.resolveMediaUrl(url);
    if (resolved == null) return null;
    return NetworkImage(resolved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Comunidad Huellitas'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: const Color(0xFFF9FBF9),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildBuscador(),
          Expanded(
            child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _fetchFeed,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _posts.length,
                    itemBuilder: (context, index) {
                      final post = _posts[index];
                      return _buildPostCard(post).animate().fadeIn(delay: (index * 40).ms, duration: 220.ms).slideY(begin: 0.04, end: 0);
                    },
                  ),
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showPostModal,
        backgroundColor: const Color(0xFFF9A826),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }

  /// Buscador por texto, autor o hashtag, con los temas más usados debajo.
  Widget _buildBuscador() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _buscar,
                  style: const TextStyle(color: Color(0xFF191C1B)),
                  decoration: InputDecoration(
                    hintText: 'Buscar publicaciones, autores o #temas',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _busquedaActiva.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () {
                              _searchCtrl.clear();
                              _buscar('');
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _buscar(_searchCtrl.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B3022),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: const Text('Buscar'),
              ),
            ],
          ),
          if (_hashtags.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _hashtags.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final tag = _hashtags[i]['tag']?.toString() ?? '';
                  return ActionChip(
                    label: Text('#$tag  ${_hashtags[i]['total']}', style: const TextStyle(fontSize: 11)),
                    backgroundColor: const Color(0xFF1B3022).withOpacity(0.06),
                    side: BorderSide(color: const Color(0xFF1B3022).withOpacity(0.2)),
                    onPressed: () {
                      _searchCtrl.text = '#$tag';
                      _buscar('#$tag');
                    },
                  );
                },
              ),
            ),
          ],
          if (_busquedaActiva.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Resultados para "$_busquedaActiva" — ${_posts.length} publicación(es)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPostCard(dynamic post) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF1B3022),
                  backgroundImage: _safeImage(post['autor_foto_url']),
                  child: _safeImage(post['autor_foto_url']) == null ? Text(
                    (post['autor_nombre'] ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ) : null,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post['autor_nombre'] ?? 'Usuario Anónimo', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(_formatDate(post['created_at']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(post['contenido'] ?? '', style: GoogleFonts.inter(fontSize: 14)),
            const SizedBox(height: 12),
            if (ApiService.resolveMediaUrl(post['imagen_url']) != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  ApiService.resolveMediaUrl(post['imagen_url'])!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 180,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 120,
                    alignment: Alignment.center,
                    color: Colors.black12,
                    child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
                  ),
                ),
              ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: PopupMenuButton<String>(
                    onSelected: (String reaction) {
                      _toggleLike(post, reaction);
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: '👍',
                        child: Text('👍 Me gusta'),
                      ),
                      const PopupMenuItem<String>(
                        value: '❤️',
                        child: Text('❤️ Me encanta'),
                      ),
                      const PopupMenuItem<String>(
                        value: '😂',
                        child: Text('😂 Me divierte'),
                      ),
                      const PopupMenuItem<String>(
                        value: '😮',
                        child: Text('😮 Me asombra'),
                      ),
                      const PopupMenuItem<String>(
                        value: '😢',
                        child: Text('😢 Me entristece'),
                      ),
                      const PopupMenuItem<String>(
                        value: '🙏',
                        child: Text('🙏 Gracias'),
                      ),
                    ],
                    child: _buildReactionBtn(post),
                  ),
                ),
                Expanded(
                  child: _buildInteractionBtn(
                    Icons.comment_outlined,
                    '${post['total_comentarios'] ?? 0} Comentarios',
                    onPressed: () => _showCommentsModal(post['id']),
                    color: Colors.grey.shade600
                  ),
                ),
                if (_canDelete(post['autor_id'])) ...[
                  if (_canEdit(post))
                    Expanded(
                      child: _buildInteractionBtn(
                        Icons.edit_outlined,
                        'Editar',
                        onPressed: () => _editPost(post),
                        color: Colors.blue,
                      ),
                    ),
                  Expanded(
                    child: _buildInteractionBtn(
                      Icons.delete_outline,
                      'Eliminar',
                      onPressed: () => _deletePost(post['id']),
                      color: Colors.red,
                    ),
                  ),
                ] else
                  Expanded(
                    child: _buildInteractionBtn(
                      Icons.flag_outlined,
                      'Reportar',
                      onPressed: () => _reportPost(post['id']),
                      color: Colors.orange,
                    ),
                  ),
                Expanded(
                  child: _buildInteractionBtn(
                    Icons.visibility_off_outlined,
                    'Ocultar',
                    onPressed: () => _hidePostForMe(post['id']),
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  String? _miReaccion(dynamic post) {
    final reacciones = post['reacciones'];
    if (reacciones is! List) return null;
    final myId = AuthService.userData?['id']?.toString();
    for (final r in reacciones) {
      if (r is Map && r['usuario_id']?.toString() == myId) return r['tipo']?.toString();
    }
    return null;
  }

  Widget _buildReactionBtn(dynamic post) {
    final miReaccion = _miReaccion(post);
    final label = '${post['likes_count'] ?? 0}${miReaccion != null ? ' $miReaccion' : ' Reacciones'}';
    return _buildInteractionBtn(
      Icons.thumb_up_alt_outlined,
      label,
      onPressed: () {},
      interactive: false,
      color: miReaccion != null ? Colors.blue : Colors.grey.shade600,
    );
  }

  /// [interactive]=false renderiza solo el contenido visual (sin `TextButton`
  /// propio) para poder usarse como `child` de un `PopupMenuButton` — un
  /// `TextButton` anidado ahí le roba el tap al menú y este nunca se abre.
  Widget _buildInteractionBtn(IconData icon, String label, {required VoidCallback onPressed, required Color color, bool interactive = true}) {
    if (!interactive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: TextStyle(color: color, fontSize: 12), overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
        ],
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, color: color, size: 18),
      label: Flexible(
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 12),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('Sé el primero en publicar', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1B3022))),
          const SizedBox(height: 8),
          const Text('La comunidad está esperando escuchar de ti.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }
}

class _CommentsWidget extends StatefulWidget {
  final int postId;
  const _CommentsWidget({required this.postId});

  @override
  State<_CommentsWidget> createState() => _CommentsWidgetState();
}

class _CommentsWidgetState extends State<_CommentsWidget> {
  List<dynamic> _comments = [];
  bool _isLoading = true;
  final TextEditingController _commentCtrl = TextEditingController();
  // El backend aún no devuelve el estado de reacción por comentario al
  // listar, así que lo llevamos de forma optimista en el cliente.
  final Set<dynamic> _likedCommentIds = {};

  ImageProvider? _safeImage(String? url) {
    final resolved = ApiService.resolveMediaUrl(url);
    if (resolved == null) return null;
    return NetworkImage(resolved);
  }

  @override
  void initState() {
    super.initState();
    _fetchComments();
  }

  Future<void> _fetchComments() async {
    try {
      final usuarioId = AuthService.userData?['id'];
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/publicacion/${widget.postId}/comentarios?usuarioId=$usuarioId'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (response.statusCode == 200) {
        if (mounted) setState(() {
          _comments = jsonDecode(response.body);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Envía el comentario redactado. Igual que al publicar: si el backend
  /// advierte que el contenido podría romper las reglas, se le pregunta al
  /// usuario si quiere comentar de todas formas antes de reenviar con
  /// `confirmado=true`; si es grave, el backend ya lo bloqueó con un strike.
  Future<void> _addComment({String? textoAConfirmar, bool confirmado = false}) async {
    final text = textoAConfirmar ?? _commentCtrl.text;
    if (text.trim().isEmpty) return;
    if (textoAConfirmar == null) _commentCtrl.clear();
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/publicacion/${widget.postId}/comentar?usuarioId=${AuthService.userData?['id']}&contenido=${Uri.encodeComponent(text)}&confirmado=$confirmado'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}

      if (response.statusCode == 200 && body?['advertencia'] == true) {
        if (!mounted) return;
        final seguir = await mostrarAdvertenciaModeracion(context, body?['mensaje'] ?? 'Este contenido podría romper nuestras reglas.');
        if (seguir) await _addComment(textoAConfirmar: text, confirmado: true);
        return;
      }

      if (response.statusCode == 200) {
        _fetchComments();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body?['error'] ?? 'No se pudo comentar.')));
      }
    } catch (_) {}
  }

  Future<void> _deleteComment(int id) async {
    try {
      await http.delete(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/comentario/$id?usuarioId=${AuthService.userData?['id']}'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      _fetchComments();
    } catch (_) {}
  }

  Future<void> _editComment(Map<String, dynamic> comment) async {
    final TextEditingController ctrl = TextEditingController(text: comment['contenido']);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar Comentario'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != comment['contenido']) {
      try {
        await http.put(
          Uri.parse('${ApiService.baseUrl}/huellitas/social/comentario/${comment['id']}?usuarioId=${AuthService.userData?['id']}&contenido=${Uri.encodeComponent(result)}'),
          headers: {'Authorization': 'Bearer ${AuthService.token}'},
        );
        _fetchComments();
      } catch (_) {}
    }
  }

  /// Denuncia el comentario de otra persona. Reutiliza el endpoint general de
  /// reportes del backend, indicando de qué comentario se trata.
  Future<void> _reportComment(Map<String, dynamic> comentario) async {
    final motivoCtrl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Denunciar comentario'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${comentario['contenido'] ?? ''}"',
                style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '¿Por qué denuncias este comentario?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(
              ctx,
              motivoCtrl.text.trim().isEmpty ? 'Comentario inapropiado' : motivoCtrl.text.trim(),
            ),
            child: const Text('Denunciar'),
          ),
        ],
      ),
    );
    if (motivo == null) return;

    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/reportar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({
          'reportadorId': AuthService.userData?['id'],
          'reportadoId': comentario['usuario_id'],
          'motivo': '[Comentario] $motivo',
          'contenido': comentario['contenido'],
        }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.statusCode == 200
              ? 'Comentario denunciado. Gracias por avisarnos.'
              : 'No se pudo enviar la denuncia.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggleLikeComment(dynamic commentId) async {
    final yaReaccione = _likedCommentIds.contains(commentId);
    setState(() {
      if (yaReaccione) {
        _likedCommentIds.remove(commentId);
      } else {
        _likedCommentIds.add(commentId);
      }
    });
    try {
      await http.post(
        Uri.parse(
          '${ApiService.baseUrl}/huellitas/reacciones/comentario/$commentId?usuarioId=${AuthService.userData?['id']}&tipo=LIKE&quitar=$yaReaccione',
        ),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
    } catch (_) {
      // revertir si falló la llamada
      if (mounted) {
        setState(() {
          if (yaReaccione) {
            _likedCommentIds.add(commentId);
          } else {
            _likedCommentIds.remove(commentId);
          }
        });
      }
    }
  }

  bool _isAuthor(dynamic authorId) {
    if (authorId == null || AuthService.userData?['id'] == null) return false;
    return authorId.toString() == AuthService.userData?['id'].toString();
  }

  /// Solo el autor puede borrar lo suyo. El rol PROPIETARIO es un usuario
  /// normal dentro de la comunidad: no debe poder borrar publicaciones ajenas.
  /// El ADMINISTRADOR sí, porque es quien modera la plataforma.
  bool _canDelete(dynamic authorId) {
    final rol = AuthService.rol ?? AuthService.userData?['rol'];
    return _isAuthor(authorId) || rol == 'ADMINISTRADOR';
  }

  /// Solo se puede editar un comentario propio dentro de los primeros 5
  /// minutos — pasado ese tiempo el backend ya no lo permite.
  bool _canEditComment(Map<String, dynamic> comment) {
    if (!_isAuthor(comment['usuario_id'])) return false;
    final creado = DateTime.tryParse(comment['created_at']?.toString() ?? '');
    if (creado == null) return false;
    return DateTime.now().difference(creado).inMinutes < 5;
  }

  /// Oculta el comentario solo para el usuario en sesión ("eliminar para
  /// mí") — sigue visible para todos los demás.
  Future<void> _hideCommentForMe(int commentId) async {
    final usuarioId = AuthService.userData?['id'];
    if (usuarioId == null) return;
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/social/ocultar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({'usuarioId': usuarioId, 'tipo': 'COMENTARIO', 'contenidoId': commentId}),
      );
      if (response.statusCode == 200) {
        _fetchComments();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo ocultar el comentario.')));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 16),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Text('Comentarios', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                      ? const Center(child: Text('No hay comentarios aún.'))
                      : ListView.builder(
                          itemCount: _comments.length,
                              itemBuilder: (ctx, i) {
                            final c = _comments[i];
                            final isAuthor = _isAuthor(c['usuario_id']);
                            final canEdit = _canEditComment(c);
                            final canDelete = _canDelete(c['usuario_id']);
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: _safeImage(c['foto_url']),
                                child: _safeImage(c['foto_url']) == null ? Text((c['autor'] ?? 'U')[0].toUpperCase()) : null,
                              ),
                              title: Text(c['autor'] ?? 'Usuario', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text(c['contenido'] ?? ''),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      _likedCommentIds.contains(c['id']) ? Icons.favorite : Icons.favorite_border,
                                      size: 20,
                                      color: _likedCommentIds.contains(c['id']) ? Colors.red : Colors.grey.shade400,
                                    ),
                                    onPressed: () => _toggleLikeComment(c['id']),
                                  ),
                                  // Editar: solo lo propio y dentro de los primeros 5 minutos. Denunciar: solo lo ajeno.
                                  if (canEdit)
                                    IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.blue), onPressed: () => _editComment(c)),
                                  if (!isAuthor)
                                    IconButton(
                                      icon: const Icon(Icons.flag_outlined, size: 20, color: Colors.orange),
                                      tooltip: 'Denunciar comentario',
                                      onPressed: () => _reportComment(c),
                                    ),
                                  if (canDelete)
                                    IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => _deleteComment(c['id'])),
                                  IconButton(
                                    icon: const Icon(Icons.visibility_off_outlined, size: 20, color: Colors.grey),
                                    tooltip: 'Ocultar solo para mí',
                                    onPressed: () => _hideCommentForMe(c['id']),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      decoration: InputDecoration(
                        hintText: 'Escribe un comentario...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onSubmitted: (_) => _addComment(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF1B3022)),
                    onPressed: _addComment,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
