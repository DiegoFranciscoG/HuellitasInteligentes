import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

/// Panel de control de los dispositivos IoT de la casa (ESP32): muestra el
/// estado de sensores y actuadores (LEDs, ventiladores, servos, bomba,
/// dispensador) y permite operarlos manualmente o alternar el modo
/// automático.
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiService>();
    final state = api.deviceState;
    final isLoading = api.isLoading;

    // Los controles físicos se bloquean si la vivienda no tiene ningún aparato
    // dado de alta o si el que tiene lleva rato sin dar señal. Mientras el
    // estado todavía no se conoce no se bloquea nada, para no mostrar un aviso
    // falso durante la primera carga. El bloqueo de verdad vive en el backend:
    // esto solo evita ofrecer botones que van a fallar.
    final sinIot = !api.iotEstadoDesconocido && api.iotTotal == 0;
    final iotCaido = !api.iotEstadoDesconocido && api.iotTotal > 0 && !api.iotConectado;
    final bloqueado = sinIot || iotCaido;

    final autoMode = (state?.automaticMode ?? true) || bloqueado;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => api.refreshDevices(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Panel IoT de la Casa',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1B3022),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Monitorea y controla tu infraestructura inteligente.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (state != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1B3022).withOpacity(0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Control Global',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade500,
                              letterSpacing: 1.0,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                'Modo Auto',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1B3022),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _premiumSwitch(
                                value: autoMode,
                                onChanged: (val) => api.toggleAutomaticMode(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              if (isLoading && state == null)
                const Center(child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ))
              else if (state == null)
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 32),
                      Icon(Icons.wifi_off, size: 64, color: Colors.red.shade200),
                      const SizedBox(height: 16),
                      Text(
                        'Fallo de Conexión',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1B3022),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        api.errorMessage ?? 'No se pudo conectar con el servidor IoT.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => api.refreshDevices(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B3022),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    if (sinIot) _avisoIot(
                      icono: Icons.memory,
                      color: const Color(0xFF1B3022),
                      titulo: 'Todavía no tienes un IoT',
                      texto: 'Conecta tu ESP32 a la misma red y agrégalo desde Cámaras → '
                             'Buscar en mi red. Hasta entonces los controles quedan '
                             'bloqueados, porque no hay ningún aparato al que mandarlos.',
                    ),
                    if (iotCaido) _avisoIot(
                      icono: Icons.wifi_off,
                      color: Colors.red.shade700,
                      titulo: 'Tu IoT está desconectado',
                      texto: 'Los ${api.iotTotal} aparatos de tu vivienda llevan más de '
                             '${api.iotVentanaSegundos} segundos sin dar señal. Comprueba '
                             'que el ESP32 esté encendido y conectado al WiFi.',
                    ),
                    if (bloqueado) const SizedBox(height: 20),

                    // ROOM 1
                    _buildZoneCard(
                      title: 'Zona de Confort (Habitación 1)',
                      subtitle: 'Sensores climáticos y luz ambiental',
                      icon: Icons.lightbulb,
                      iconColor: Colors.amber.shade600,
                      iconBg: Colors.amber.shade50,
                      sensors: [
                        _buildSensorBlock(context, 'Temperatura', '${state.dht.temperature1.toStringAsFixed(1)}°C', Icons.thermostat, Colors.orange),
                        _buildSensorBlock(context, 'Humedad', '${state.dht.humidity1.toStringAsFixed(0)}%', Icons.water_drop, Colors.blue),
                        _buildSensorBlock(context, 'Calidad Aire', _textoAire(state.mq135.airQuality1), Icons.air, _colorAire(state.mq135.airQuality1)),
                        _buildSensorBlock(context, 'Movimiento', state.motion.room1Entry ? 'Detectado' : 'Despejado', Icons.directions_run, Colors.purple),
                      ],
                      controls: [
                        _buildToggleControl('Luz Principal', Icons.lightbulb, Colors.amber, state.led.room1Led, autoMode, () => api.toggleLed(1)),
                        _buildToggleControl('Ventilador', Icons.mode_fan_off, Colors.blue, state.fan.fan1, autoMode, () => api.toggleFan(1)),
                        _buildServoControl('Ventana Habitación 1', Icons.window, state.servo.angle, autoMode, (angle) => api.changeServo(1, angle)),
                      ],
                    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),
                    const SizedBox(height: 24),

                    // ROOM 2
                    _buildZoneCard(
                      title: 'Zona de Alimentación (Hab. 2)',
                      subtitle: 'Control de comida y agua',
                      icon: Icons.science,
                      iconColor: Colors.blue.shade600,
                      iconBg: Colors.blue.shade50,
                      sensors: [
                        _buildSensorBlock(context, 'Nivel Agua', '${_porcentajeAgua(state.water.level)}% · ${_textoAgua(state.water.level)}', Icons.water_drop, Colors.blue),
                        _buildSensorBlock(context, 'Nivel Comida', '${_porcentajeComida(state.ultrasonic.distance)}% · ${_textoComida(state.ultrasonic.distance)}', Icons.line_weight, Colors.green),
                        _buildSensorBlock(context, 'Temperatura', '${state.dht.temperature2.toStringAsFixed(1)}°C', Icons.thermostat, Colors.orange),
                        _buildSensorBlock(context, 'Humedad', '${state.dht.humidity2.toStringAsFixed(0)}%', Icons.water_drop, Colors.blue),
                        _buildSensorBlock(context, 'Calidad Aire', _textoAire(state.mq135.airQuality2), Icons.air, _colorAire(state.mq135.airQuality2)),
                      ],
                      controls: [
                        _buildToggleControl('Luz de Zona', Icons.lightbulb, Colors.amber, state.led.room2Led, autoMode, () => api.toggleLed(2)),
                        _buildToggleControl('Ventilador', Icons.mode_fan_off, Colors.blue, state.fan.fan2, autoMode, () => api.toggleFan(2)),
                        _buildToggleControl('Bomba de Agua', Icons.water, Colors.blue, state.pump.enabled, autoMode, () => api.togglePump()),
                        // El servo 2 se retiró de esta pantalla a petición. Sigue
                        // existiendo en el firmware y en el backend; reponerlo es
                        // volver a añadir su _buildServoControl aquí.
                        _buildDispenserControl(context, api, autoMode),
                      ],
                    ).animate().fadeIn(duration: 300.ms, delay: 100.ms).slideY(begin: 0.05, end: 0),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoneCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required List<Widget> sensors,
    required List<Widget> controls,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B3022).withOpacity(0.07),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1B3022),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Sensores: la proporción se calcula según el ancho real y el tamaño
          // de letra del sistema. Con una relación fija, en pantallas angostas
          // o con fuente grande el contenido se desbordaba unos píxeles.
          LayoutBuilder(
            builder: (context, constraints) {
              final escalaTexto = MediaQuery.textScalerOf(context).scale(14) / 14;
              final columnas = constraints.maxWidth > 520 ? 4 : 2;
              final anchoTile = (constraints.maxWidth - (columnas - 1) * 12) / columnas;
              final altoTile = 68 * escalaTexto;
              return GridView.count(
                crossAxisCount: columnas,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: anchoTile / altoTile,
                children: sensors,
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'CONTROL MANUAL',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          // Controles
          Column(
            children: controls,
          ),
        ],
      ),
    );
  }

  /// Bloque de sensor con relieve neumórfico (una sombra clara y una oscura,
  /// como si estuviera esculpido en la superficie). Al tocarlo abre una
  /// vista de vidrio (glassmorphism) con el mismo valor real en grande —
  /// puramente informativo, no cambia ningún dato ni control existente.
  Widget _buildSensorBlock(BuildContext context, String label, String value, IconData icon, MaterialColor color) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showSensorGlassDetail(context, label, value, icon, color),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: _neumorphicInset(radius: 16),
        child: Row(
          children: [
            Icon(icon, color: color.shade400, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1B3022),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sombra doble (clara arriba-izquierda, oscura abajo-derecha) para el
  /// efecto "esculpido en arcilla" de la guía de estilo, sin bordes duros.
  BoxDecoration _neumorphicInset({double radius = 16}) {
    return BoxDecoration(
      color: const Color(0xFFF8FAF8),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(color: Colors.white.withOpacity(0.9), blurRadius: 6, offset: const Offset(-3, -3)),
        BoxShadow(color: const Color(0xFF1B3022).withOpacity(0.10), blurRadius: 8, offset: const Offset(3, 3)),
      ],
    );
  }

  void _showSensorGlassDetail(BuildContext context, String label, String value, IconData icon, MaterialColor color) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color.shade500, size: 40),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: GoogleFonts.outfit(fontSize: 36, fontWeight: FontWeight.bold, color: const Color(0xFF1B3022)),
                ),
                const SizedBox(height: 4),
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Switch con look de interruptor físico premium: pista más ancha en tono
  /// arcilla y una pastilla de sombra debajo que le da relieve, en vez del
  /// switch plano por defecto de Material.
  Widget _premiumSwitch({required bool value, required ValueChanged<bool>? onChanged}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1B3022).withOpacity(value ? 0.18 : 0.06), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: const Color(0xFFF9A826),
        activeTrackColor: const Color(0xFF1B3022),
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: Colors.grey.shade300,
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }

  Widget _buildToggleControl(String label, IconData icon, MaterialColor color, bool value, bool autoMode, VoidCallback onToggle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _neumorphicInset(radius: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(icon, size: 20, color: color.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1B3022),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _premiumSwitch(
            value: value,
            onChanged: autoMode ? null : (_) => onToggle(),
          ),
        ],
      ),
    );
  }

  Widget _buildDispenserControl(BuildContext context, ApiService api, bool autoMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: _neumorphicInset(radius: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(Icons.restaurant, size: 20, color: Colors.green.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Dispensador de Comida',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1B3022),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: autoMode ? null : () => _dispenseFoodNow(context, api),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B3022),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(90, 32),
            ),
            child: const Text('Dispensar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// Tarjeta que explica por qué los controles están bloqueados.
  ///
  /// Se distingue "no hay ningún aparato" de "el aparato no responde" porque
  /// lo que el usuario tiene que hacer en cada caso es distinto: en el primero
  /// hay que darlo de alta, en el segundo hay que encenderlo.
  Widget _avisoIot({
    required IconData icono,
    required Color color,
    required String titulo,
    required String texto,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1B3022),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  texto,
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Lecturas en crudo convertidas a algo legible.
  //
  // El firmware manda lo que sale del conversor analógico del ESP32 (0–4095)
  // y la distancia del ultrasónico en centímetros. Mostrar esos números tal
  // cual no dice nada, y ponerles "%" o "PPM" al lado dice algo falso. Se
  // convierten con los mismos criterios que usa la web, para que las dos
  // pantallas no den cifras distintas del mismo sensor.
  // -------------------------------------------------------------------

  /// Lectura del sensor de agua (0–4095) llevada a porcentaje del depósito.
  int _porcentajeAgua(int nivel) => ((nivel / 4095) * 100).round().clamp(0, 100);

  String _textoAgua(int nivel) {
    final p = _porcentajeAgua(nivel);
    if (p <= 10) return 'Vacío';
    if (p <= 35) return 'Bajo';
    if (p <= 70) return 'Medio';
    return 'Lleno';
  }

  /// Cuanto más cerca está la comida del sensor, más lleno está el depósito.
  /// Se toman 30 cm como fondo del recipiente.
  int _porcentajeComida(double distancia) =>
      (((30 - distancia) * 100) / 30).round().clamp(0, 100);

  String _textoComida(double distancia) {
    final p = _porcentajeComida(distancia);
    if (p <= 10) return 'Vacío';
    if (p <= 30) return 'Poco';
    if (p <= 70) return 'Medio';
    return 'Suficiente';
  }

  /// El MQ135 no entrega partes por millón sin calibrar: lo que llega es el
  /// valor en crudo del conversor, así que se muestra la escala, no la unidad.
  String _textoAire(int valor) {
    if (valor < 1200) return 'Excelente';
    if (valor < 2000) return 'Buena';
    if (valor < 2800) return 'Regular';
    if (valor < 3400) return 'Mala';
    return 'Muy mala';
  }

  MaterialColor _colorAire(int valor) {
    if (valor < 1200) return Colors.green;
    if (valor < 2000) return Colors.lightGreen;
    if (valor < 2800) return Colors.amber;
    if (valor < 3400) return Colors.deepOrange;
    return Colors.red;
  }

  /// Dispensa una ración llevando el motor a su tope y devolviéndolo al reposo.
  ///
  /// El destino sale del propio backend (`maxPosition`) en vez de ir escrito
  /// aquí: antes se pedía 2048, un valor que el servidor recortaba en silencio
  /// a su máximo real, de modo que el número de la app nunca fue el que se
  /// ejecutaba.
  Future<void> _dispenseFoodNow(BuildContext context, ApiService api) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Dispensando comida...'), duration: Duration(seconds: 2)),
    );
    final tope = api.deviceState?.stepper.maxPosition ?? 200;
    await api.changeStepper(tope);
    await Future.delayed(const Duration(seconds: 2));
    await api.changeStepper(0);
  }

  Widget _buildServoControl(String label, IconData icon, int currentAngle, bool autoMode, Function(int) onChange) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: _neumorphicInset(radius: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Expanded + ellipsis: con nombres largos o fuente grande, la fila
          // se salía de la pantalla (el desbordamiento a la derecha).
          Expanded(
            child: Row(
              children: [
                Icon(icon, size: 20, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1B3022),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: autoMode ? null : () => onChange(0),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1B3022),
                  elevation: 0,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  minimumSize: const Size(60, 32),
                ),
                child: const Text('Abrir', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: autoMode ? null : () => onChange(90),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B3022),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  minimumSize: const Size(60, 32),
                ),
                child: const Text('Cerrar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
