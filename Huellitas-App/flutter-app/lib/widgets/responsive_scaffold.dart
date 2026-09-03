import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Un ítem de navegación compartido entre el bottom nav (móvil) y el
/// sidebar (pantallas anchas), para no duplicar la lista de destinos.
class AppNavItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  const AppNavItem({required this.icon, this.selectedIcon, required this.label});
}

/// Breakpoint compartido con `huellitas-web` (`src/styles.scss`,
/// `@media (max-width: 768px)`), para que el punto de quiebre entre layout
/// móvil y de escritorio sea el mismo en ambas plataformas.
const double kWideLayoutBreakpoint = 768;

/// Shell responsive de la app: por debajo de [kWideLayoutBreakpoint] se
/// comporta como antes (Drawer + BottomNavigationBar, ideal para teléfono).
/// A partir de ese ancho, se reemplaza por un sidebar oscuro fijo tipo panel
/// SaaS (igual al de `huellitas-web`) y el contenido pasa a usar el tema
/// claro de escritorio.
class ResponsiveScaffold extends StatelessWidget {
  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> screens;
  final Widget? drawer;
  final String brandLabel;
  final Widget? floatingActionButton;

  const ResponsiveScaffold({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.screens,
    this.drawer,
    this.brandLabel = 'Huellitas',
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= kWideLayoutBreakpoint;
        return isWide ? _buildWide(context) : _buildNarrow(context);
      },
    );
  }

  Widget _buildNarrow(BuildContext context) {
    return Scaffold(
      drawer: drawer,
      body: IndexedStack(index: currentIndex, children: screens),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, -5)),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: onDestinationSelected,
            type: BottomNavigationBarType.fixed,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 10),
            items: [
              for (final item in items)
                BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  activeIcon: Icon(item.selectedIcon ?? item.icon),
                  label: item.label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    return Scaffold(
      drawer: drawer,
      body: Row(
        children: [
          SizedBox(
            width: 260,
            child: NavigationRail(
              extended: true,
              minExtendedWidth: 260,
              backgroundColor: AppColors.primary,
              selectedIndex: currentIndex,
              onDestinationSelected: onDestinationSelected,
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: Row(
                  children: [
                    const Icon(Icons.pets, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Text(
                      brandLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              trailing: drawer == null
                  ? null
                  : Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Builder(
                            builder: (context) => TextButton.icon(
                              onPressed: () => Scaffold.of(context).openDrawer(),
                              icon: const Icon(Icons.more_horiz, color: Colors.white70),
                              label: const Text('Más', style: TextStyle(color: Colors.white70)),
                            ),
                          ),
                        ),
                      ),
                    ),
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon ?? item.icon),
                    label: Text(item.label),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: AppColors.outlineDark),
          Expanded(
            child: Theme(
              data: AppTheme.light(),
              child: ColoredBox(
                color: AppColors.surfaceLight,
                child: IndexedStack(index: currentIndex, children: screens),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
