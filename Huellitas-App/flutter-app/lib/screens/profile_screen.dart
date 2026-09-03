import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' show imageCache;
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// Perfil del usuario: edita nombre y foto, gestiona miembros de la casa
/// (invitar/eliminar) y códigos QR de acceso rápido para propietarios, y
/// permite cerrar sesión.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = false;
  bool _tienePassword = true;
  List<dynamic> _miembros = [];

  final _nombreCtrl = TextEditingController();
  File? _selectedPhoto;

  // Para cambio de password
  final _passCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nombreCtrl.text = AuthService.userData?['nombre'] ?? '';
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Datos frescos del servidor: si la foto o el nombre cambiaron desde la
    // web, aquí se ven sin tener que cerrar sesión.
    await AuthService.refrescarUsuario();
    if (mounted) _nombreCtrl.text = AuthService.userData?['nombre'] ?? _nombreCtrl.text;

    final tienePass = await AuthService.tienePassword();
    List<dynamic> miembros = [];
    final casaId = AuthService.userData?['casa_id'] ?? AuthService.userData?['casa']?['id'];
    
    if (casaId != null) {
      miembros = await AuthService.listarMiembros();
      try {
        final yo = miembros.firstWhere((m) => m['id'].toString() == AuthService.userData?['id']?.toString());
        if (yo != null) {
           final updatedUser = Map<String, dynamic>.from(AuthService.userData!);
           updatedUser['nombre'] = yo['nombre'] ?? updatedUser['nombre'];
           updatedUser['fotoUrl'] = yo['foto_url'] ?? yo['fotoUrl'] ?? updatedUser['fotoUrl'];
           AuthService.updateUserData(updatedUser);
        }
      } catch (_) {}
    }
    
    if (mounted) {
      setState(() {
        _tienePassword = tienePass;
        _miembros = miembros;
        _isLoading = false;
      });
    }
  }

  Future<void> _guardarPerfil() async {
    if (_nombreCtrl.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    final err = await AuthService.actualizarPerfil(_nombreCtrl.text.trim(), foto: _selectedPhoto);

    if (err == null) {
      // Flutter cachea las imágenes por URL; si el servidor reutiliza la misma
      // ruta, seguía mostrando la foto vieja hasta reiniciar la app.
      imageCache.clear();
      imageCache.clearLiveImages();
      await AuthService.refrescarUsuario();
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (err == null) _selectedPhoto = null;
    });
    _snack(err ?? 'Perfil actualizado');
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final sizeBytes = await file.length();
      if (sizeBytes > 5 * 1024 * 1024) {
        _snack('La foto debe ser menor a 5MB.');
        return;
      }
      setState(() => _selectedPhoto = file);
    }
  }

  Future<void> _establecerPassword() async {
    if (_passCtrl.text.length < 6) {
      _snack('Mínimo 6 caracteres');
      return;
    }
    setState(() => _isLoading = true);
    final err = await AuthService.establecerPassword(_passCtrl.text);
    if (err == null) {
      setState(() {
        _tienePassword = true;
        _isLoading = false;
      });
      _snack('Contraseña establecida con éxito');
      Navigator.pop(context); // close dialog
    } else {
      setState(() => _isLoading = false);
      _snack(err);
    }
  }

  Future<void> _eliminarMiembro(int id) async {
    setState(() => _isLoading = true);
    final err = await AuthService.eliminarMiembro(id);
    if (err == null) {
      await _loadData();
      _snack('Miembro eliminado');
    } else {
      setState(() => _isLoading = false);
      _snack(err);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: const Color(0xFF1B3022),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSetPasswordDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Crear Contraseña', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _passCtrl,
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'Nueva contraseña',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B3022), foregroundColor: Colors.white),
            onPressed: _establecerPassword,
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showInvitarDialog() {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Invitar Miembro', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
              const SizedBox(height: 8),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 8),
              TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña provisional')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B3022), foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              final err = await AuthService.invitarMiembro(emailCtrl.text.trim(), nameCtrl.text.trim(), passCtrl.text);
              if (err == null) {
                await _loadData();
                _snack('Miembro invitado con éxito');
              } else {
                setState(() => _isLoading = false);
                _snack(err);
              }
            },
            child: const Text('Invitar'),
          ),
        ],
      ),
    );
  }

  void _showQrDialog() async {
    setState(() => _isLoading = true);
    final res = await AuthService.generarQrToken(tipo: 'BIENVENIDA');
    setState(() => _isLoading = false);
    // El backend devuelve la clave `raw_token`; leer solo `token` hacía que
    // siempre pareciera un fallo aunque la petición saliera bien.
    final qrToken = res?['raw_token'] ?? res?['token'];
    if (qrToken != null) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('QR de Bienvenida', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 250,
            height: 250,
            child: QrImageView(
              data: qrToken.toString(),
              version: QrVersions.auto,
              size: 250.0,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          ],
        ),
      );
    } else {
      _snack('Error al generar QR');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.userData;
    final String rol = (AuthService.rol ?? '').trim().toUpperCase();
    
    return Theme(
      data: AppTheme.light(),
      child: Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: SafeArea(
        child: _isLoading && user == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // El rol va en una etiqueta aparte: metido en el título,
                    // "Mi Perfil (ADMINISTRADOR)" se partía en dos líneas y
                    // quedaba desalineado en pantallas angostas.
                    Text(
                      'Mi Perfil',
                      style: GoogleFonts.outfit(fontSize: 30, fontWeight: FontWeight.bold, color: const Color(0xFF1B3022)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B3022).withOpacity(0.07),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFF1B3022).withOpacity(0.15)),
                      ),
                      child: Text(
                        rol,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: const Color(0xFF1B3022),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    if (!_tienePassword)
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Crea una contraseña', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                                  Text('Iniciaste sesión con Google, por seguridad añade una contraseña.', style: GoogleFonts.inter(fontSize: 12, color: Colors.orange.shade800)),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _showSetPasswordDialog,
                              child: Text('Crear', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                            )
                          ],
                        ),
                      ),
                      
                    // Datos de perfil
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: _selectedPhoto != null
                                ? FileImage(_selectedPhoto!) as ImageProvider
                                : (ApiService.resolveMediaUrl(user?['fotoUrl']) != null
                                    ? NetworkImage(ApiService.resolveMediaUrl(user?['fotoUrl'])!)
                                    : null),
                            child: (_selectedPhoto == null && ApiService.resolveMediaUrl(user?['fotoUrl']) == null)
                                ? const Icon(Icons.person, size: 50, color: Colors.grey)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickPhoto,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1B3022),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedPhoto != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Center(
                          child: Text(
                            'Foto nueva seleccionada — pulsa "Guardar" para aplicarla',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text('Nombre', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nombreCtrl,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Email (Solo lectura)', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(text: user?['email'] ?? ''),
                      readOnly: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B3022),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isLoading ? null : _guardarPerfil,
                        child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Guardar Cambios'),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    if (rol == 'PROPIETARIO') ...[
                      Text('Miembros de la Casa', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF1B3022))),
                      const SizedBox(height: 8),
                      Text('Solo puedes tener 1 miembro adicional por casa.', style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600)),
                      const SizedBox(height: 16),
                      
                      if (_miembros.isEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.people_outline, size: 48, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text('No hay miembros en tu casa', style: GoogleFonts.inter(color: Colors.grey.shade600)),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.qr_code),
                                    label: const Text('QR'),
                                    onPressed: _showQrDialog,
                                  ),
                                  const SizedBox(width: 16),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B3022), foregroundColor: Colors.white),
                                    icon: const Icon(Icons.person_add),
                                    label: const Text('Invitar'),
                                    onPressed: _showInvitarDialog,
                                  ),
                                ],
                              )
                            ],
                          ),
                        )
                      ] else ...[
                        for (var m in _miembros)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              leading: const CircleAvatar(backgroundColor: Color(0xFF1B3022), child: Icon(Icons.person, color: Colors.white)),
                              title: Text(m['nombre'] ?? 'Miembro', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                              subtitle: Text(m['email'] ?? ''),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _eliminarMiembro(m['id']),
                              ),
                            ),
                          )
                      ],
                      const SizedBox(height: 40),
                    ],
                    
                    const Divider(),
                    const SizedBox(height: 24),
                    
                    if (rol == 'PROPIETARIO' || rol == 'MIEMBRO') ...[
                      // "Cámaras" moved to dedicated tab
                      const SizedBox(height: 16),
                    ],
                    
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: Text('Cerrar Sesión', style: GoogleFonts.inter(color: Colors.red, fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.red.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          // Este servicio vive durante toda la app: si no se
                          // limpia aquí, la próxima cuenta que inicie sesión
                          // puede ver por un instante (o si la próxima
                          // petición falla) las mascotas/cámaras de esta.
                          context.read<ApiService>().clearAll();
                          AuthService.logout();
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (context) => const LoginScreen()),
                            (Route<dynamic> route) => false,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
      ),
    );
  }
}
