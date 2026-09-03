import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/section_header.dart';

/// Gestión de mascotas de la casa: lista las mascotas registradas y permite
/// agregar, editar o eliminar una (nombre, raza, peso, fecha de nacimiento
/// y foto).
class PetsScreen extends StatefulWidget {
  const PetsScreen({super.key});

  @override
  State<PetsScreen> createState() => _PetsScreenState();
}

class _PetsScreenState extends State<PetsScreen> {
  bool _isLoading = true;
  int? _casaId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  int? _resolveCasaId() {
    final userData = AuthService.userData;
    final raw = userData?['casa_id'] ?? userData?['casa']?['id'];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  Future<void> _load() async {
    final token = AuthService.token;
    final casaId = _resolveCasaId();
    _casaId = casaId;
    if (token == null || casaId == null) {
      setState(() => _isLoading = false);
      return;
    }
    await context.read<ApiService>().fetchDashboard(casaId, token);
    if (mounted) setState(() => _isLoading = false);
  }

  void _openForm({Map<String, dynamic>? perro}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PetFormSheet(
        casaId: _casaId,
        perro: perro,
        onSaved: _load,
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> perro) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar mascota'),
        content: Text('¿Seguro que quieres eliminar a "${perro['nombre']}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/huellitas/perro/${perro['id']}'),
        headers: {'Authorization': 'Bearer ${AuthService.token}'},
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${perro['nombre']}" eliminado correctamente.')),
          );
        }
        _load();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al eliminar la mascota.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de red: $e')));
      }
    }
  }

  String _calcularEdad(String? fechaNac) {
    if (fechaNac == null) return 'Edad desconocida';
    final fecha = DateTime.tryParse(fechaNac);
    if (fecha == null) return 'Edad desconocida';
    final meses = (DateTime.now().difference(fecha).inDays / 30).floor();
    if (meses < 24) return '$meses meses';
    return '${(meses / 12).floor()} años';
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light(),
      child: Builder(builder: (context) {
        final api = context.watch<ApiService>();
        final dashboard = api.dashboardData;
        final perros = (dashboard?['perros'] as List?) ?? [];
        final plan = dashboard?['plan'] as Map<String, dynamic>?;
        final planNombre = plan?['nombre'] ?? 'FREE';
        final limite = plan?['limite_mascotas'] ?? 2;
        final limiteAlcanzado = perros.length >= (limite is int ? limite : int.tryParse(limite.toString()) ?? 2);

        return Scaffold(
          backgroundColor: AppColors.surfaceLight,
          appBar: AppBar(title: const Text('Mascotas')),
          floatingActionButton: FloatingActionButton(
            backgroundColor: limiteAlcanzado ? Colors.grey : AppColors.accent,
            foregroundColor: AppColors.primary,
            onPressed: () {
              if (limiteAlcanzado) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Alcanzaste el límite de $limite mascotas de tu plan $planNombre.')),
                );
                return;
              }
              _openForm();
            },
            child: const Icon(Icons.add),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      SectionHeader(
                        title: 'Tus mascotas',
                        subtitle: '${perros.length} de $limite · Plan $planNombre',
                      ),
                      const SizedBox(height: 20),
                      if (perros.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Column(
                            children: [
                              Icon(Icons.pets, size: 56, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'Aún no registras ninguna mascota',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        )
                      else
                        for (var i = 0; i < perros.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: AppCard(
                              onTap: () => _openForm(perro: perros[i]),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: AppColors.primarySurface,
                                    backgroundImage: ApiService.resolveMediaUrl(perros[i]['foto_url']) != null
                                        ? NetworkImage(ApiService.resolveMediaUrl(perros[i]['foto_url'])!)
                                        : null,
                                    child: ApiService.resolveMediaUrl(perros[i]['foto_url']) == null
                                        ? const Icon(Icons.pets, color: AppColors.primary)
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(perros[i]['nombre'] ?? '', style: Theme.of(context).textTheme.titleMedium),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${perros[i]['raza'] ?? 'Raza desconocida'} · ${_calcularEdad(perros[i]['fecha_nacimiento'])}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        if (perros[i]['peso'] != null)
                                          Text('${perros[i]['peso']} kg', style: Theme.of(context).textTheme.bodySmall),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () => _confirmDelete(perros[i]),
                                  ),
                                ],
                              ),
                            ),
                          ).animate().fadeIn(delay: (i * 60).ms, duration: 250.ms).slideY(begin: 0.05, end: 0),
                    ],
                  ),
                ),
        );
      }),
    );
  }
}

class _PetFormSheet extends StatefulWidget {
  final int? casaId;
  final Map<String, dynamic>? perro;
  /// Recarga la lista. Devuelve un Future para poder esperarla antes de
  /// cerrar el formulario, y que la mascota nueva ya esté visible al volver.
  final Future<void> Function() onSaved;

  const _PetFormSheet({required this.casaId, required this.perro, required this.onSaved});

  @override
  State<_PetFormSheet> createState() => _PetFormSheetState();
}

class _PetFormSheetState extends State<_PetFormSheet> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _razaCtrl;
  late final TextEditingController _pesoCtrl;
  DateTime? _fechaNacimiento;
  File? _selectedFile;
  bool _isSaving = false;

  bool get _isEdit => widget.perro != null;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.perro?['nombre'] ?? '');
    _razaCtrl = TextEditingController(text: widget.perro?['raza'] ?? '');
    _pesoCtrl = TextEditingController(text: widget.perro?['peso']?.toString() ?? '');
    final fechaStr = widget.perro?['fecha_nacimiento'];
    if (fechaStr != null) _fechaNacimiento = DateTime.tryParse(fechaStr);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _razaCtrl.dispose();
    _pesoCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    final nombre = _nombreCtrl.text.trim();
    final raza = _razaCtrl.text.trim();
    final soloLetras = RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]+$');
    if (nombre.length < 2 || !soloLetras.hasMatch(nombre)) {
      return 'El nombre debe tener al menos 2 letras (sin números).';
    }
    if (raza.length < 2 || !soloLetras.hasMatch(raza)) {
      return 'La raza debe tener al menos 2 letras (sin números).';
    }
    final peso = double.tryParse(_pesoCtrl.text.trim());
    if (peso == null || peso <= 0 || peso > 150) {
      return 'El peso debe ser un número entre 0 y 150 kg.';
    }
    if (!_isEdit) {
      if (_fechaNacimiento == null) return 'Selecciona la fecha de nacimiento.';
      if (_fechaNacimiento!.isAfter(DateTime.now())) return 'La fecha de nacimiento no puede ser futura.';
      if (DateTime.now().difference(_fechaNacimiento!).inDays > 365 * 25) {
        return 'La fecha de nacimiento no puede exceder los 25 años.';
      }
    }
    return null;
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final sizeBytes = await file.length();
      if (sizeBytes > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La foto debe ser menor a 5MB.')),
          );
        }
        return;
      }
      setState(() => _selectedFile = file);
    }
  }

  Future<void> _pickFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaNacimiento ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _fechaNacimiento = picked);
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (!_isEdit && widget.casaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontró la casa del usuario.')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final uri = _isEdit
          ? Uri.parse('${ApiService.baseUrl}/huellitas/perro/${widget.perro!['id']}')
          : Uri.parse('${ApiService.baseUrl}/huellitas/perro');
      final request = http.MultipartRequest(_isEdit ? 'PUT' : 'POST', uri);
      request.headers['Authorization'] = 'Bearer ${AuthService.token}';
      request.fields['nombre'] = _nombreCtrl.text.trim();
      request.fields['raza'] = _razaCtrl.text.trim();
      request.fields['peso'] = _pesoCtrl.text.trim();
      if (!_isEdit) {
        request.fields['casaId'] = widget.casaId.toString();
        request.fields['fechaNacimiento'] =
            '${_fechaNacimiento!.year.toString().padLeft(4, '0')}-${_fechaNacimiento!.month.toString().padLeft(2, '0')}-${_fechaNacimiento!.day.toString().padLeft(2, '0')}';
      }
      if (_selectedFile != null) {
        // Ver la misma nota en community_screen.dart: se fuerza extensión y
        // content-type válidos para que una foto de cámara no se rechace.
        final path = _selectedFile!.path;
        final rawExt = path.contains('.') ? path.split('.').last.toLowerCase() : '';
        const extAMime = {
          'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
          'webp': 'image/webp', 'gif': 'image/gif',
        };
        final ext = extAMime.containsKey(rawExt) ? rawExt : 'jpg';
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          path,
          filename: 'foto.$ext',
          contentType: MediaType.parse(extAMime[ext]!),
        ));
      }

      final streamed = await request.send();
      if (streamed.statusCode == 200 || streamed.statusCode == 201) {
        // La foto nueva vive en otra URL, pero la anterior sigue en la caché de
        // imágenes de Flutter: sin vaciarla, la tarjeta seguía pintando la vieja
        // hasta que se cerraba la pantalla. Y los datos se recargan ANTES de
        // cerrar el formulario, para que al volver la lista ya esté al día.
        imageCache.clear();
        imageCache.clearLiveImages();
        await widget.onSaved();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isEdit ? 'Mascota actualizada.' : 'Mascota registrada.')),
          );
        }
      } else {
        final body = await streamed.stream.bytesToString();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensajeDeError(body))));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de red: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// El backend manda `{"ok":false,"message":"..."}` con el texto ya listo
  /// para mostrar (por ejemplo, cuando la foto no parece ser de un perro
  /// real). Si el cuerpo no es ese JSON esperado, se muestra tal cual llegó.
  String _mensajeDeError(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data['message'] is String) return data['message'];
      if (data is Map && data['error'] is String) return data['error'];
    } catch (_) {
      // No era JSON: se cae al mensaje crudo de abajo.
    }
    return 'Error: $body';
  }

  @override
  Widget build(BuildContext context) {
    final existingPhoto = ApiService.resolveMediaUrl(widget.perro?['foto_url']);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isEdit ? 'Editar mascota' : 'Registrar mascota',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.primarySurface,
                    backgroundImage: _selectedFile != null
                        ? FileImage(_selectedFile!)
                        : (existingPhoto != null ? NetworkImage(existingPhoto) : null) as ImageProvider?,
                    child: (_selectedFile == null && existingPhoto == null)
                        ? const Icon(Icons.add_a_photo_outlined, color: AppColors.primary)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(controller: _nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
              const SizedBox(height: 12),
              TextField(controller: _razaCtrl, decoration: const InputDecoration(labelText: 'Raza')),
              const SizedBox(height: 12),
              TextField(
                controller: _pesoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Peso (kg)'),
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: AppRadii.lgRadius,
                  onTap: _pickFecha,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Fecha de nacimiento'),
                    child: Text(
                      _fechaNacimiento == null
                          ? 'Selecciona una fecha'
                          : '${_fechaNacimiento!.day}/${_fechaNacimiento!.month}/${_fechaNacimiento!.year}',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              AppButton(
                label: _isSaving ? 'Guardando...' : (_isEdit ? 'Guardar cambios' : 'Registrar mascota'),
                onPressed: _isSaving ? null : _submit,
                expand: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
