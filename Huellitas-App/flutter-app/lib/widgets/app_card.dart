import 'package:flutter/material.dart';
import '../theme/app_radii.dart';
import '../theme/app_shadows.dart';

/// Tarjeta estandarizada que toma el color de `CardTheme` actual (oscuro en
/// móvil, claro en escritorio vía `ResponsiveScaffold`), en vez de que cada
/// pantalla defina su propio `BoxDecoration` con colores sueltos.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool elevated;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: AppRadii.xlRadius,
      boxShadow: elevated ? AppShadows.md : null,
    );

    if (onTap == null) {
      return Container(padding: padding, decoration: decoration, child: child);
    }

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadii.xlRadius,
      child: InkWell(
        borderRadius: AppRadii.xlRadius,
        onTap: onTap,
        child: Container(padding: padding, decoration: decoration, child: child),
      ),
    );
  }
}
