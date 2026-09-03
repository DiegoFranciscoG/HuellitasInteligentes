import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Gestor de entrenamiento del asistente IA (RAG): permite subir documentos
/// PDF y registrar URLs de fuentes confiables para alimentar la base de
/// conocimiento, y lista lo ya cargado.
class AdminIaTrainingScreen extends StatefulWidget {
  const AdminIaTrainingScreen({super.key});

  @override
  State<AdminIaTrainingScreen> createState() => _AdminIaTrainingScreenState();
}

class _AdminIaTrainingScreenState extends State<AdminIaTrainingScreen> {
  final _urlController = TextEditingController();
  final _descController = TextEditingController();

  List<dynamic> _fuentes = [];
  List<dynamic> _documentos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${AuthService.token}',
      };

      final resFuentes = await http.get(Uri.parse('${ApiService.baseUrl}/huellitas/admin/rag/fuentes'), headers: headers);
      final resDocs = await http.get(Uri.parse('${ApiService.baseUrl}/huellitas/admin/rag/documentos'), headers: headers);

      if (mounted) {
        setState(() {
          if (resFuentes.statusCode == 200) _fuentes = jsonDecode(utf8.decode(resFuentes.bodyBytes));
          if (resDocs.statusCode == 200) _documentos = jsonDecode(utf8.decode(resDocs.bodyBytes));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registrarFuente() async {
    if (_urlController.text.isEmpty) return;

    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/admin/rag/fuentes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: jsonEncode({
          'url': _urlController.text,
          'descripcion': _descController.text,
        }),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        _urlController.clear();
        _descController.clear();
        _fetchData();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fuente registrada')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al registrar fuente')));
    }
  }

  Future<void> _subirPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      
      try {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subiendo PDF...')));

        var request = http.MultipartRequest('POST', Uri.parse('${ApiService.baseUrl}/huellitas/admin/rag/subir-pdf'));
        request.headers['Authorization'] = 'Bearer ${AuthService.token}';
        request.files.add(await http.MultipartFile.fromPath('file', file.path));

        var response = await request.send();

        if (response.statusCode == 200 || response.statusCode == 201) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF subido exitosamente')));
          _fetchData();
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al subir PDF')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error de red al subir')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      appBar: AppBar(
        title: const Text('Entrenamiento IA'),
        backgroundColor: const Color(0xFF1B3022),
        foregroundColor: const Color(0xFFF9FBF9),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Gestor de Entrenamiento RAG', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Carga PDFs y enlaces para alimentar la IA.', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),

                  // Sección PDF
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.picture_as_pdf, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Subir Documento PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _subirPdf,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Seleccionar PDF'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade50,
                              foregroundColor: Colors.blue.shade900,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sección URL
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.link, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Agregar Fuente Confiable (URL)', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _urlController,
                            decoration: const InputDecoration(labelText: 'URL de la fuente', border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descController,
                            decoration: const InputDecoration(labelText: 'Descripción breve', border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _registrarFuente,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1B3022),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: const Text('Registrar Fuente Confiable'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Listas
                  const Text('Documentos PDF Subidos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  if (_documentos.isEmpty)
                    const Text('Sin documentos', style: TextStyle(color: Colors.grey))
                  else
                    ..._documentos.map((d) => ListTile(
                      leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                      title: Text(d['nombre_archivo'] ?? 'Documento'),
                      subtitle: Text(d['estado'] ?? 'Procesado'),
                    )),
                    
                  const SizedBox(height: 24),
                  
                  const Text('Fuentes Registradas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  if (_fuentes.isEmpty)
                    const Text('Sin fuentes', style: TextStyle(color: Colors.grey))
                  else
                    ..._fuentes.map((f) => ListTile(
                      leading: const Icon(Icons.link, color: Colors.blue),
                      title: Text(f['url'] ?? 'URL'),
                      subtitle: Text(f['descripcion'] ?? ''),
                    )),
                ],
              ),
            ),
    );
  }
}
