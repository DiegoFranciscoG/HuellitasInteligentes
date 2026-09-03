import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'admin_users_screen.dart';
import 'admin_plans_screen.dart';
import 'admin_moderation_screen.dart';
import 'admin_announcements_screen.dart';
import 'admin_groups_screen.dart';
import 'admin_activity_screen.dart';
import 'admin_subscriptions_screen.dart';

/// Panel de inicio del administrador: muestra indicadores globales (hogares
/// conectados, usuarios activos, dispositivos IoT, suscripciones) y accesos
/// rápidos a las demás secciones de administración.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final token = AuthService.token;
    if (token != null) {
      final api = context.read<ApiService>();
      await api.fetchAdminDashboard(token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiService>();
    final data = api.adminDashboardData;
    final isLoading = api.isLoading;
    final userData = AuthService.userData;
    final userName = userData?['nombre'] ?? 'Administrador';

    if (isLoading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final resumen = data?['resumen'] ?? {};
    final totalCasas = resumen['total_casas'] ?? 0;
    final totalUsuarios = resumen['total_usuarios_activos'] ?? 0;
    final totalDispositivos = resumen['total_dispositivos'] ?? 0;
    final suscripcionesActivas = resumen['suscripciones_activas'] ?? 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield, color: Color(0xFF1B3022)),
                    const SizedBox(width: 8),
                    Text(
                      'Admin Panel',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1B3022),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Text(
                    'ADMIN',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Greeting
            Text(
              'VISTA GENERAL DEL SISTEMA',
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
            ),
            const SizedBox(height: 24),

            // KPI Cards
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
              children: [
                _buildKpiCard(
                  title: 'Hogares Conectados',
                  value: totalCasas.toString(),
                  icon: Icons.home,
                  color: Colors.blueGrey,
                ),
                _buildKpiCard(
                  title: 'Usuarios Activos',
                  value: totalUsuarios.toString(),
                  icon: Icons.people,
                  color: Colors.blue,
                ),
                _buildKpiCard(
                  title: 'Dispositivos IoT',
                  value: totalDispositivos.toString(),
                  icon: Icons.memory,
                  color: Colors.orange,
                ),
                _buildKpiCard(
                  title: 'Suscripciones',
                  value: suscripcionesActivas.toString(),
                  icon: Icons.verified,
                  color: Colors.green,
                ),
              ],
            ),
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
            const SizedBox(height: 16),
            
            _buildActionTile(
              context: context,
              title: 'Gestión de Usuarios',
              subtitle: 'Ver y administrar cuentas',
              icon: Icons.people_outline,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminUsersScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              context: context,
              title: 'Gestión de Planes',
              subtitle: 'Administrar suscripciones',
              icon: Icons.card_membership,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminPlansScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              context: context,
              title: 'Moderación',
              subtitle: 'Denuncias y sanciones de la comunidad',
              icon: Icons.gavel,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const AdminModerationScreen())),
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              context: context,
              title: 'Avisos Masivos',
              subtitle: 'Enviar comunicados a todos los usuarios',
              icon: Icons.campaign,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const AdminAnnouncementsScreen())),
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              context: context,
              title: 'Grupos',
              subtitle: 'Supervisar y moderar grupos',
              icon: Icons.groups,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const AdminGroupsScreen())),
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              context: context,
              title: 'Actividad de la Plataforma',
              subtitle: 'Usuarios conectados e inactivos',
              icon: Icons.insights,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const AdminActivityScreen())),
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              context: context,
              title: 'Suscripciones',
              subtitle: 'Estado de pagos y planes por casa',
              icon: Icons.credit_card,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const AdminSubscriptionsScreen())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1B3022).withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF1B3022)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
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
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required MaterialColor color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color.shade600, size: 24),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1B3022),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
