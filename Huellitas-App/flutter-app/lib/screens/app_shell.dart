import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/notificacion_emergente.dart';
import '../widgets/responsive_scaffold.dart';
import 'home_dashboard_screen.dart';
import 'devices_screen.dart';
import 'community_screen.dart';
import 'profile_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_devices_screen.dart';
import 'admin_users_screen.dart';
import 'cameras_screen.dart';
import 'pet_moments_screen.dart';
import 'history_screen.dart';
import 'iot_history_screen.dart';
import 'pets_screen.dart';
import 'groups_screen.dart';
import 'my_plan_screen.dart';
import 'alerts_screen.dart';
import 'admin_subscriptions_screen.dart';
import 'admin_moderation_screen.dart';
import 'admin_announcements_screen.dart';
import 'admin_groups_screen.dart';
import 'admin_activity_screen.dart';
import 'admin_ia_training_screen.dart';
import 'admin_plans_screen.dart';
import 'admin_exportar_datos_screen.dart';
import 'asistente_ia_screen.dart';

import '../services/auth_service.dart';

/// Contenedor principal de la app una vez el usuario inició sesión: arma la
/// navegación inferior/drawer y decide qué pantallas mostrar según el rol
/// (`ADMINISTRADOR`, `MIEMBRO` o propietario), ya que cada uno ve un
/// subconjunto distinto de secciones.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  bool _isAdmin = false;
  bool _isPropietario = false;
  bool _isMiembro = false;

  late List<Widget> _bottomNavScreens;
  late List<AppNavItem> _navItems;

  @override
  void initState() {
    super.initState();
    // Antes un rol vacío o inesperado caía en la rama del propietario (menú
    // completo: mascotas, plan, comunidad, gestión de miembros). Si el rol no
    // llegó bien por algún motivo, debe ver MENOS, no más: se trata como
    // MIEMBRO (el panel más restringido) salvo que el rol realmente diga
    // ADMINISTRADOR o PROPIETARIO.
    final role = (AuthService.rol ?? '').trim().toUpperCase();
    _isAdmin = (role == 'ADMINISTRADOR');
    _isPropietario = (role == 'PROPIETARIO');
    _isMiembro = !_isAdmin && !_isPropietario;

    if (_isAdmin) {
      _bottomNavScreens = [
        const AdminDashboardScreen(),
        const AdminUsersScreen(),
        const AdminDevicesScreen(),
        const AdminIaTrainingScreen(),
        const ProfileScreen(),
      ];
      _navItems = const [
        AppNavItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Home'),
        AppNavItem(icon: Icons.people_outline, selectedIcon: Icons.people, label: 'Usuarios'),
        AppNavItem(icon: Icons.memory_outlined, selectedIcon: Icons.memory, label: 'Monitoreo'),
        AppNavItem(icon: Icons.psychology_outlined, selectedIcon: Icons.psychology, label: 'IA'),
        AppNavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Perfil'),
      ];
    } else if (_isMiembro) {
      // El miembro tiene su propio apartado, igual que en la web: solo lo que
      // le corresponde de la casa a la que fue invitado (dispositivos, cámaras
      // y alertas). Antes caía en el `else` del propietario y veía el panel
      // completo del dueño, con mascotas, plan, comunidad e historial.
      _bottomNavScreens = [
        const DevicesScreen(),
        const CamerasScreen(),
        const AlertsScreen(),
        const ProfileScreen(),
      ];
      _navItems = const [
        AppNavItem(icon: Icons.router_outlined, selectedIcon: Icons.router, label: 'Dispositivos'),
        AppNavItem(icon: Icons.videocam_outlined, selectedIcon: Icons.videocam, label: 'Cámaras'),
        AppNavItem(icon: Icons.warning_amber_outlined, selectedIcon: Icons.warning, label: 'Alertas'),
        AppNavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Perfil'),
      ];
    } else {
      _bottomNavScreens = [
        const HomeDashboardScreen(),
        const DevicesScreen(),
        const CamerasScreen(),
        const CommunityScreen(),
        const ProfileScreen(),
      ];
      _navItems = const [
        AppNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Inicio'),
        AppNavItem(icon: Icons.router_outlined, selectedIcon: Icons.router, label: 'Dispositivos'),
        AppNavItem(icon: Icons.videocam_outlined, selectedIcon: Icons.videocam, label: 'Cámaras'),
        AppNavItem(icon: Icons.forum_outlined, selectedIcon: Icons.forum, label: 'Comunidad'),
        AppNavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Perfil'),
      ];
    }

    // Vale para todos los roles: al entrar traemos la foto y el nombre
    // actuales del servidor.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sincronizarUsuario());
  }

  /// Refresca el usuario al entrar para que la foto/nombre cambiados desde la
  /// web aparezcan sin tener que cerrar sesión.
  Future<void> _sincronizarUsuario() async {
    await AuthService.refrescarUsuario();
    if (mounted) setState(() {});
  }

  void _onDrawerItemTapped(int bottomNavIndex) {
    Navigator.pop(context); // Close drawer
    setState(() {
      _currentIndex = bottomNavIndex;
    });
  }

  void _navigateTo(Widget screen) {
    Navigator.pop(context); // Close drawer
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  Widget _buildDrawerHeader() {
    final name = AuthService.userData?['nombre'] ?? 'Usuario';
    final email = AuthService.userData?['email'] ?? '';
    final role = AuthService.rol ?? 'PROPIETARIO';
    final fotoUrl = ApiService.resolveMediaUrl(AuthService.userData?['fotoUrl']);

    return UserAccountsDrawerHeader(
      accountName: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
      accountEmail: Text(email),
      currentAccountPicture: CircleAvatar(
        backgroundColor: Colors.white,
        backgroundImage: fotoUrl != null ? NetworkImage(fotoUrl) : null,
        child: fotoUrl == null
            ? Text(
                name[0].toUpperCase(),
                style: const TextStyle(fontSize: 24, color: Color(0xFF1B3022), fontWeight: FontWeight.bold),
              )
            : null,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1B3022),
      ),
      otherAccountsPictures: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            role,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAdminDrawerItems() {
    final tiles = [
      ListTile(leading: const Icon(Icons.dashboard), title: const Text('Dashboard Admin'), onTap: () => _onDrawerItemTapped(0)),
      ListTile(leading: const Icon(Icons.people), title: const Text('Usuarios'), onTap: () => _onDrawerItemTapped(1)),
      ListTile(leading: const Icon(Icons.card_membership), title: const Text('Planes'), onTap: () => _navigateTo(const AdminPlansScreen())),
      ListTile(leading: const Icon(Icons.subscriptions), title: const Text('Suscripciones'), onTap: () => _navigateTo(const AdminSubscriptionsScreen())),
      ListTile(leading: const Icon(Icons.gavel), title: const Text('Moderación'), onTap: () => _navigateTo(const AdminModerationScreen())),
      ListTile(leading: const Icon(Icons.campaign), title: const Text('Avisos Masivos'), onTap: () => _navigateTo(const AdminAnnouncementsScreen())),
      ListTile(leading: const Icon(Icons.groups), title: const Text('Grupos (Admin)'), onTap: () => _navigateTo(const AdminGroupsScreen())),
      ListTile(leading: const Icon(Icons.local_activity), title: const Text('Actividad Plataforma'), onTap: () => _navigateTo(const AdminActivityScreen())),
      ListTile(leading: const Icon(Icons.download_outlined), title: const Text('Exportar Datos'), onTap: () => _navigateTo(const AdminExportarDatosScreen())),
      ListTile(leading: const Icon(Icons.memory), title: const Text('Monitoreo IoT'), onTap: () => _onDrawerItemTapped(2)),
      ListTile(leading: const Icon(Icons.psychology), title: const Text('Entrenamiento IA'), onTap: () => _onDrawerItemTapped(3)),
      const Divider(),
      ListTile(leading: const Icon(Icons.person), title: const Text('Perfil'), onTap: () => _onDrawerItemTapped(4)),
    ];
    return _staggerDrawerTiles(tiles);
  }

  /// Menú del miembro. Los índices siguen a `_bottomNavScreens` de su propia
  /// rama, que no es la del propietario.
  List<Widget> _buildMiembroDrawerItems() {
    final tiles = [
      ListTile(leading: const Icon(Icons.router), title: const Text('Dispositivos'), onTap: () => _onDrawerItemTapped(0)),
      ListTile(leading: const Icon(Icons.videocam), title: const Text('Cámaras'), onTap: () => _onDrawerItemTapped(1)),
      ListTile(leading: const Icon(Icons.auto_awesome), title: const Text('Momentos'), onTap: () => _navigateTo(const PetMomentsScreen())),
      ListTile(leading: const Icon(Icons.warning), title: const Text('Alertas'), onTap: () => _onDrawerItemTapped(2)),
      const Divider(),
      ListTile(leading: const Icon(Icons.person), title: const Text('Perfil'), onTap: () => _onDrawerItemTapped(3)),
    ];
    return _staggerDrawerTiles(tiles);
  }

  List<Widget> _buildUserDrawerItems() {
    final tiles = [
      ListTile(leading: const Icon(Icons.home), title: const Text('Inicio'), onTap: () => _onDrawerItemTapped(0)),
      if (_isPropietario) ListTile(leading: const Icon(Icons.pets), title: const Text('Mascotas'), onTap: () => _navigateTo(const PetsScreen())),
      ListTile(leading: const Icon(Icons.router), title: const Text('Dispositivos'), onTap: () => _onDrawerItemTapped(1)),
      ListTile(leading: const Icon(Icons.videocam), title: const Text('Cámaras'), onTap: () => _onDrawerItemTapped(2)),
      ListTile(leading: const Icon(Icons.auto_awesome), title: const Text('Momentos'), onTap: () => _navigateTo(const PetMomentsScreen())),
      ListTile(leading: const Icon(Icons.warning), title: const Text('Alertas'), onTap: () => _navigateTo(const AlertsScreen())),
      ListTile(leading: const Icon(Icons.forum), title: const Text('Comunidad'), onTap: () => _onDrawerItemTapped(3)),
      ListTile(leading: const Icon(Icons.smart_toy_outlined), title: const Text('Asistente IA'), onTap: () => _navigateTo(const AsistenteIaScreen())),
      ListTile(leading: const Icon(Icons.groups), title: const Text('Grupos'), onTap: () => _navigateTo(const GroupsScreen())),
      ListTile(leading: const Icon(Icons.history), title: const Text('Historial'), onTap: () => _navigateTo(const HistoryScreen())),
      ListTile(leading: const Icon(Icons.analytics), title: const Text('Historial IoT'), onTap: () => _navigateTo(const IotHistoryScreen())),
      if (_isPropietario) ListTile(leading: const Icon(Icons.star), title: const Text('Mi Plan'), onTap: () => _navigateTo(const MyPlanScreen())),
      const Divider(),
      ListTile(leading: const Icon(Icons.person), title: const Text('Perfil'), onTap: () => _onDrawerItemTapped(4)),
    ];
    return _staggerDrawerTiles(tiles);
  }

  List<Widget> _staggerDrawerTiles(List<Widget> tiles) {
    return [
      for (var i = 0; i < tiles.length; i++)
        tiles[i].animate().fadeIn(delay: (i * 40).ms, duration: 220.ms).slideX(begin: -0.05, end: 0),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Envuelve toda la aplicación autenticada para que un aviso nuevo aparezca
    // esté donde esté el usuario, no solo si abre la pantalla de alertas.
    return VigilanteNotificaciones(
      child: _buildShell(),
    );
  }

  Widget _buildShell() {
    return ResponsiveScaffold(
      items: _navItems,
      currentIndex: _currentIndex,
      onDestinationSelected: (index) => setState(() => _currentIndex = index),
      screens: _bottomNavScreens,
      drawer: Drawer(
        backgroundColor: AppColors.surfaceCardDark,
        child: Column(
          children: [
            ValueListenableBuilder<int>(
              valueListenable: AuthService.userVersion,
              builder: (context, _, __) => _buildDrawerHeader(),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _isAdmin
                    ? _buildAdminDrawerItems()
                    : (_isMiembro ? _buildMiembroDrawerItems() : _buildUserDrawerItems()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
