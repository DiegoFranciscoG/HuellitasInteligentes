import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/device_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'alerts_screen.dart';
import 'asistente_ia_screen.dart';
import 'groups_screen.dart';
import 'history_screen.dart';
import 'iot_history_screen.dart';
import 'my_plan_screen.dart';
import 'pets_screen.dart';

/// Pantalla de inicio del propietario: muestra el carrusel de sus
/// mascotas, el plan contratado, las lecturas ambientales (temperatura y
/// humedad) del dispositivo IoT y accesos rápidos a las demás secciones.
class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  final PageController _petsController = PageController();
  int _petPage = 0;

  static const String _fallbackPetImage =
      'https://images.unsplash.com/photo-1552053831-71594a27632d?auto=format&fit=crop&q=80&w=800';

  Timer? _refresco;

  @override
  void dispose() {
    _refresco?.cancel();
    _petsController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
    // El resumen de la casa (alertas pendientes, dispositivos activos) tiene
    // que reflejar el estado real aunque el usuario se quede quieto en esta
    // pantalla, igual que en la web.
    _refresco = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _loadData();
    });
  }

  Future<void> _loadData() async {
    final userData = AuthService.userData;
    final token = AuthService.token;
    if (userData != null && token != null) {
      final api = context.read<ApiService>();

      final rawCasaId = userData['casa_id'] ?? userData['casa']?['id'];
      int? parsedCasaId;
      if (rawCasaId is int) parsedCasaId = rawCasaId;
      else if (rawCasaId is String) parsedCasaId = int.tryParse(rawCasaId);

      if (parsedCasaId != null) {
        await api.fetchDashboard(parsedCasaId, token);
      }
      await api.fetchDevices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiService>();
    final dashboardData = api.dashboardData;
    final isLoading = api.isLoading;
    final userData = AuthService.userData;
    final userName = userData?['nombre'] ?? 'Usuario';

    if (isLoading && dashboardData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    String ecosystemName = dashboardData?['casa']?['nombre'] ?? 'Mi Casa';
    String tempValue = 'N/A';
    String humValue = 'N/A';

    // Todas las mascotas de la casa, no solo la primera: el carrusel de abajo
    // permite deslizar entre ellas igual que en la web.
    final List<dynamic> perros = (dashboardData?['perros'] as List?) ?? const [];

    final deviceState = api.deviceState;
    if (deviceState != null) {
      tempValue = deviceState.dht.temperature1.toStringAsFixed(1);
      humValue = deviceState.dht.humidity1.toStringAsFixed(0);
    }

    // El plan real viene en `plan.nombre` (unido desde la suscripción activa).
    // El campo `casa.suscripcion_tipo` es de una versión anterior y llega
    // vacío, por eso el panel mostraba siempre "Básico" aunque el plan
    // estuviera actualizado.
    final planName = dashboardData?['plan']?['nombre'] ??
        dashboardData?['casa']?['suscripcion_tipo'] ??
        'FREE';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Huellitas Pro & Bell
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pets, color: Color(0xFF1B3022)),
                    const SizedBox(width: 8),
                    Text(
                      'Huellitas Pro',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1B3022),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.notifications, color: Color(0xFF1B3022)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AlertsScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Greeting
            Text(
              'DASHBOARD OVERVIEW',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hola, $userName',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1B3022),
              ),
            ).animate().fadeIn(duration: 300.ms).slideX(begin: -0.03, end: 0),
            if (perros.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildEstadoHero(perros[_petPage.clamp(0, perros.length - 1)], api.deviceState)
                  .animate()
                  .fadeIn(duration: 300.ms, delay: 60.ms)
                  .slideX(begin: -0.03, end: 0),
            ],
            const SizedBox(height: 24),

            // Plan Card
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B3022), Color(0xFF1a3d1a)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5)),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Color(0xFFF9A826), size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tu Plan Actual',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFF9A826), letterSpacing: 1.2),
                        ),
                        Text(
                          'Huellitas $planName',
                          style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 80.ms).slideY(begin: 0.06, end: 0),

            // Carrusel de mascotas: una tarjeta por mascota registrada,
            // deslizable, con los mismos datos que muestra la web.
            SizedBox(
              height: 360,
              child: PageView.builder(
                controller: _petsController,
                itemCount: perros.isEmpty ? 1 : perros.length,
                onPageChanged: (i) => setState(() => _petPage = i),
                itemBuilder: (context, petIndex) {
                  final perro = perros.isEmpty ? null : perros[petIndex];
                  final dogName = perro?['nombre'] ?? 'Sin mascotas';
                  final dogBreed = perro?['raza'] ?? 'Registra tu primera mascota';
                  final dogImage = ApiService.resolveMediaUrl(perro?['foto_url']) ?? _fallbackPetImage;
                  return Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                color: const Color(0xFF1B3022),
                image: DecorationImage(
                  image: NetworkImage(dogImage),
                  fit: BoxFit.cover,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Gradient Overlay
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.1),
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                  // Live Status Badge
                  Positioned(
                    top: 24,
                    left: 24,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: Colors.white.withOpacity(0.2), // Glass effect
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'LIVE STATUS: CALM',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Name and Info at Bottom
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                dogName,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFC107),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.favorite, size: 20, color: Color(0xFF1B3022)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              dogBreed,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  ecosystemName,
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
                },
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 160.ms).slideY(begin: 0.05, end: 0),
            if (perros.length > 1) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < perros.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _petPage == i ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _petPage == i ? const Color(0xFF1B3022) : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),

            // Environment Cards
            Row(
              children: [
                Expanded(
                  child: _buildEnvCard(
                    icon: Icons.thermostat,
                    title: 'TEMPERATURA',
                    value: tempValue,
                    unit: '°C',
                    progressColor: const Color(0xFFFFC107),
                    progress: 0.6,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildEnvCard(
                    icon: Icons.water_drop,
                    title: 'HUMEDAD',
                    value: humValue,
                    unit: '%',
                    progressColor: const Color(0xFF1B3022),
                    progress: 0.48,
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 300.ms, delay: 240.ms).slideY(begin: 0.05, end: 0),

            const SizedBox(height: 20),
            _buildResumenEcosistema(api.deviceState),

            const SizedBox(height: 32),
            Text(
              'ACCESOS RÁPIDOS',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _buildAccesosRapidos(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Accesos directos a las secciones que antes solo estaban en el menú
  /// lateral. Se adapta al ancho disponible para verse bien en cualquier
  /// teléfono o tablet.
  Widget _buildAccesosRapidos(BuildContext context) {
    final esPropietario = AuthService.rol == 'PROPIETARIO';

    final accesos = <Map<String, dynamic>>[
      {'label': 'Mascotas', 'icon': Icons.pets_outlined, 'screen': const PetsScreen()},
      {'label': 'Alertas', 'icon': Icons.notifications_outlined, 'screen': const AlertsScreen()},
      {'label': 'Asistente IA', 'icon': Icons.smart_toy_outlined, 'screen': const AsistenteIaScreen()},
      {'label': 'Grupos', 'icon': Icons.groups_outlined, 'screen': const GroupsScreen()},
      {'label': 'Historial', 'icon': Icons.history, 'screen': const HistoryScreen()},
      {'label': 'Historial IoT', 'icon': Icons.analytics_outlined, 'screen': const IotHistoryScreen()},
      if (esPropietario)
        {'label': 'Mi Plan', 'icon': Icons.star_outline, 'screen': const MyPlanScreen()},
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = constraints.maxWidth > 600 ? 4 : 3;
        return GridView.count(
          crossAxisCount: columnas,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.95,
          children: [
            for (var i = 0; i < accesos.length; i++)
              _buildAccesoCard(
                context,
                accesos[i]['label'] as String,
                accesos[i]['icon'] as IconData,
                accesos[i]['screen'] as Widget,
                i,
              ),
          ],
        );
      },
    );
  }

  Widget _buildAccesoCard(BuildContext context, String label, IconData icon, Widget screen, int index) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        ),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF1B3022), size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1B3022),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 50).ms, duration: 220.ms).slideY(begin: 0.08, end: 0);
  }

  Widget _buildEnvCard({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
    required Color progressColor,
    required double progress,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B3022).withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF1B3022), size: 24),
          const SizedBox(height: 24),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1B3022),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  /// Hero de estado en vivo: foto circular de la mascota seleccionada en el
  /// carrusel con un anillo que "respira" (glow suave), y un titular en
  /// Playfair Display. El estado (activo/en reposo) sale del sensor de
  /// movimiento real de la casa, no es un texto fijo.
  Widget _buildEstadoHero(dynamic perro, DeviceState? deviceState) {
    final dogName = perro?['nombre'] ?? 'Tu mascota';
    final dogImage = ApiService.resolveMediaUrl(perro?['foto_url']) ?? _fallbackPetImage;
    final movimiento = deviceState?.motion.room1Entry == true || deviceState?.motion.room2Entry == true;
    final estadoTexto = movimiento ? '$dogName está activo' : '$dogName está en reposo';
    final glowColor = movimiento ? const Color(0xFFFFC107) : const Color(0xFF34D399);

    return Row(
      children: [
        _PulsingGlowAvatar(imageUrl: dogImage, glowColor: glowColor),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ESTADO EN VIVO',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                estadoTexto,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1B3022),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Tarjeta oscura de "Resumen del Ecosistema": lee las lecturas reales que
  /// ya trae [deviceState] (temperatura, humedad, calidad de aire, movimiento)
  /// y arma frases simples según umbrales — nada inventado ni una predicción
  /// de IA que no exista, solo una lectura honesta del estado actual.
  Widget _buildResumenEcosistema(DeviceState? deviceState) {
    if (deviceState == null) return const SizedBox.shrink();

    final temp = deviceState.dht.temperature1;
    final hum = deviceState.dht.humidity1;
    final aire = deviceState.mq135.airQuality1;
    final movimiento = deviceState.motion.room1Entry || deviceState.motion.room2Entry;

    final puntos = <String>[];
    if (temp < 18) {
      puntos.add('Temperatura algo baja (${temp.toStringAsFixed(1)}°C).');
    } else if (temp > 28) {
      puntos.add('Temperatura alta (${temp.toStringAsFixed(1)}°C).');
    } else {
      puntos.add('Temperatura estable en ${temp.toStringAsFixed(1)}°C.');
    }
    if (hum < 30) {
      puntos.add('Humedad baja (${hum.toStringAsFixed(0)}%).');
    } else if (hum > 70) {
      puntos.add('Humedad elevada (${hum.toStringAsFixed(0)}%).');
    }
    if (aire > 400) {
      puntos.add('Calidad del aire a vigilar ($aire PPM).');
    }
    puntos.add(movimiento ? 'Movimiento detectado ahora mismo en casa.' : 'Sin movimiento: todo tranquilo.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B3022), Color(0xFF12241a)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1B3022).withOpacity(0.25), blurRadius: 28, offset: const Offset(0, 14)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, color: Color(0xFFF9A826), size: 18),
              const SizedBox(width: 8),
              Text(
                'RESUMEN DEL ECOSISTEMA',
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in puntos)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('•  $p', style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withOpacity(0.92))),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 280.ms).slideY(begin: 0.05, end: 0);
  }
}

/// Avatar circular con un anillo de brillo que "respira" (pulsa lento entre
/// tenue e intenso), usado como indicador de estado en vivo. Vive aparte del
/// resto de la pantalla porque necesita su propio [AnimationController].
class _PulsingGlowAvatar extends StatefulWidget {
  final String imageUrl;
  final Color glowColor;

  const _PulsingGlowAvatar({required this.imageUrl, required this.glowColor});

  @override
  State<_PulsingGlowAvatar> createState() => _PulsingGlowAvatarState();
}

class _PulsingGlowAvatarState extends State<_PulsingGlowAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: widget.glowColor.withOpacity(0.5 + t * 0.3), width: 3),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withOpacity(0.22 + t * 0.25),
                blurRadius: 14 + (t * 10),
                spreadRadius: t * 3,
              ),
            ],
          ),
          child: child,
        );
      },
      child: CircleAvatar(
        radius: 42,
        backgroundColor: Colors.white,
        backgroundImage: NetworkImage(widget.imageUrl),
      ),
    );
  }
}
