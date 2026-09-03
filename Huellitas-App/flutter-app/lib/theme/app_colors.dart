import 'package:flutter/material.dart';

/// Paleta de colores compartida con `huellitas-web` (ver
/// `huellitas-web/src/styles.scss`), para que la app y la web se vean
/// como el mismo producto.
class AppColors {
  AppColors._();

  // Verde principal de marca
  static const Color primary = Color(0xFF061B0E);
  static const Color primaryLight = Color(0xFF1A3D1A);
  static const Color primarySurface = Color(0xFFD0E9D4);

  // Ámbar de acento
  static const Color accent = Color(0xFFFDC003);
  static const Color accentDark = Color(0xFFE5AC00);

  // Superficies claras (panel ancho / escritorio)
  static const Color surfaceLight = Color(0xFFF8FAF8);
  static const Color surfaceCream = Color(0xFFFFFAED);
  static const Color surfaceCardLight = Color(0xFFFFFFFF);
  static const Color onSurfaceLight = Color(0xFF191C1B);
  static const Color onSurfaceVariantLight = Color(0xFF434843);
  static const Color outlineLight = Color(0xFFC3C8C1);

  // Superficies oscuras (móvil, según referencias visuales)
  static const Color surfaceDark = Color(0xFF07170E);
  static const Color surfaceCardDark = Color(0xFF10281A);
  static const Color surfaceCardDarkElevated = Color(0xFF163722);
  static const Color onSurfaceDark = Color(0xFFF3F6F3);
  static const Color onSurfaceVariantDark = Color(0xFFB7C2BA);
  static const Color outlineDark = Color(0xFF2B4534);

  // Estado
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorSurface = Color(0xFFFFDAD6);
  static const Color success = Color(0xFF15803D);
  static const Color successSurface = Color(0x1F16A34A);
  static const Color warning = Color(0xFF92400E);
  static const Color warningSurface = Color(0x26FDC003);
}
