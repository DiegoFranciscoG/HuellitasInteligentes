import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';

/// Pantalla de suscripción del propietario: muestra los planes disponibles,
/// cuál está activo y permite cambiar de plan.
class MyPlanScreen extends StatefulWidget {
  const MyPlanScreen({super.key});

  @override
  State<MyPlanScreen> createState() => _MyPlanScreenState();
}

class _MyPlanScreenState extends State<MyPlanScreen> {
  bool _isLoading = true;
  bool _isChanging = false;
  List<dynamic> _planes = [];
  int? _planActualId;
  String? _mensaje;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${AuthService.token}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _isLoading = true);
    try {
      // `/planes/activos` también exige sesión: sin la cabecera devuelve 401 y
      // la lista de planes quedaba vacía, así que la pantalla no mostraba nada.
      final planesRes = await http.get(
        Uri.parse('${ApiService.baseUrl}/huellitas/planes/activos'),
        headers: _headers,
      );
      final miPlanRes = await http.get(Uri.parse('${ApiService.baseUrl}/huellitas/planes/mi-plan'), headers: _headers);

      if (planesRes.statusCode == 200) {
        _planes = jsonDecode(utf8.decode(planesRes.bodyBytes));
      }
      if (miPlanRes.statusCode == 200) {
        final data = jsonDecode(utf8.decode(miPlanRes.bodyBytes));
        final rawId = data['plan_id'];
        _planActualId = rawId is int ? rawId : int.tryParse(rawId.toString());
      }
    } catch (_) {
      // se muestra el estado vacío si falla
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Los planes de pago abren la pasarela segura de Stripe en el navegador.
  /// Los gratuitos se cambian directamente. El precio siempre lo decide el
  /// servidor con lo que tenga configurado el administrador.
  Future<void> _seleccionarPlan(int id) async {
    if (_planActualId == id || _isChanging) return;
    setState(() {
      _isChanging = true;
      _mensaje = null;
    });
    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/pagos/checkout?planId=$id'),
        headers: _headers,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));

        if (data['gratuito'] == true) {
          await _cambiarPlanGratuito(id);
          return;
        }

        final url = data['url']?.toString();
        if (url != null) {
          final uri = Uri.tryParse(url);
          if (uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            setState(() => _mensaje =
                'Te abrimos la pasarela de pago. Cuando termines, vuelve aquí y desliza para actualizar.');
          } else {
            setState(() => _mensaje = 'No se pudo abrir la pasarela de pago.');
          }
        } else {
          setState(() => _mensaje = 'No se pudo iniciar el pago.');
        }
      } else {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() => _mensaje = 'Error al iniciar el pago: ${body['error'] ?? 'Inténtalo de nuevo.'}');
      }
    } catch (e) {
      setState(() => _mensaje = 'Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _isChanging = false);
    }
  }

  Future<void> _cambiarPlanGratuito(int id) async {
    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/huellitas/planes/cambiar'),
        headers: _headers,
        body: jsonEncode({'planId': id}),
      );
      if (res.statusCode == 200) {
        setState(() {
          _planActualId = id;
          _mensaje = 'Tu plan se actualizó correctamente.';
        });
        await _cargar();
      } else {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() => _mensaje = 'Error al cambiar de plan: ${body['error'] ?? 'Inténtalo de nuevo.'}');
      }
    } catch (e) {
      setState(() => _mensaje = 'Error de conexión: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light(),
      child: Scaffold(
        backgroundColor: AppColors.surfaceLight,
        appBar: AppBar(title: const Text('Mi Plan')),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_mensaje != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: !_mensaje!.startsWith('Error') ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_mensaje!),
                      ),
                    if (_planes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Text('No se pudieron cargar los planes.', style: Theme.of(context).textTheme.bodyMedium),
                        ),
                      )
                    else
                      for (var i = 0; i < _planes.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildPlanCard(_planes[i], i),
                        ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPlanCard(dynamic plan, int index) {
    final id = plan['id'] is int ? plan['id'] : int.tryParse(plan['id'].toString());
    final esActual = id == _planActualId;
    final precio = plan['precio_oferta'] ?? plan['precio_mensual'];
    final tieneDescuento = plan['precio_oferta'] != null && plan['descuento_porcentaje'] != null;

    return AppCard(
      elevated: !esActual,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                (plan['nombre'] ?? '').toString().toUpperCase().contains('PREMIUM') ? Icons.workspace_premium : Icons.shield_outlined,
                color: AppColors.accentDark,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(plan['nombre'] ?? 'Plan', style: Theme.of(context).textTheme.titleLarge),
              ),
              if (esActual)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(999)),
                  child: const Text('Tu plan actual', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('\$${precio ?? '0'}', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(width: 4),
              const Text('/ mes'),
              if (tieneDescuento) ...[
                const SizedBox(width: 8),
                Text(
                  '\$${plan['precio_mensual']}',
                  style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey),
                ),
              ],
            ],
          ),
          if (plan['descripcion'] != null) ...[
            const SizedBox(height: 8),
            Text(plan['descripcion'], style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (plan['limite_mascotas'] != null) Text('Hasta ${plan['limite_mascotas']} mascotas'),
              if (plan['limite_dispositivos'] != null) Text('Hasta ${plan['limite_dispositivos']} dispositivos'),
              if (plan['limite_almacenamiento_mb'] != null) Text('${plan['limite_almacenamiento_mb']} MB de almacenamiento'),
            ],
          ),
          const SizedBox(height: 16),
          AppButton(
            label: esActual ? 'Plan activo' : (_isChanging ? 'Cambiando...' : 'Seleccionar este plan'),
            variant: esActual ? AppButtonVariant.outline : AppButtonVariant.accent,
            expand: true,
            onPressed: esActual || _isChanging || id == null ? null : () => _seleccionarPlan(id),
          ),
        ],
      ),
    ).animate().fadeIn(delay: (index * 80).ms, duration: 250.ms).slideY(begin: 0.05, end: 0);
  }
}
