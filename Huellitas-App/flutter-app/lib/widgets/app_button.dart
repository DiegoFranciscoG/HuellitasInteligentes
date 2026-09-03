import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';

/// Estilos visuales disponibles para [AppButton]: `primary` (relleno con el
/// color de marca), `accent` (relleno ámbar), `outline` (solo borde) y
/// `ghost` (solo texto).
enum AppButtonVariant { primary, accent, outline, ghost }

/// Botón estandarizado (variantes primaria/acento/outline/ghost) para
/// reemplazar los `ElevatedButton.styleFrom(...)` repetidos a mano en cada
/// pantalla.
class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool expand;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
          );

    late final Widget button;
    switch (variant) {
      case AppButtonVariant.primary:
        button = ElevatedButton(onPressed: onPressed, child: child);
      case AppButtonVariant.accent:
        button = ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.primary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: const RoundedRectangleBorder(borderRadius: AppRadii.fullRadius),
          ),
          child: child,
        );
      case AppButtonVariant.outline:
        button = OutlinedButton(onPressed: onPressed, child: child);
      case AppButtonVariant.ghost:
        button = TextButton(onPressed: onPressed, child: child);
    }

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
