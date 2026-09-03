import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tipografía compartida con `huellitas-web`: `DM Serif Display` para
/// títulos, `Inter` para el resto — reemplaza las llamadas sueltas a
/// `GoogleFonts.outfit`/`GoogleFonts.inter` repetidas por pantalla.
class AppTextTheme {
  AppTextTheme._();

  /// Construye el [TextTheme] de la app con [baseColor] como color de texto
  /// base, combinando la tipografía serif de títulos con la sans-serif del
  /// resto del contenido.
  static TextTheme build(Color baseColor) {
    final serif = GoogleFonts.dmSerifDisplayTextTheme();
    final body = GoogleFonts.interTextTheme();

    return body
        .copyWith(
          displayLarge: serif.displayLarge?.copyWith(color: baseColor),
          displayMedium: serif.displayMedium?.copyWith(color: baseColor),
          displaySmall: serif.displaySmall?.copyWith(color: baseColor),
          headlineLarge: serif.headlineLarge?.copyWith(color: baseColor, fontSize: 28),
          headlineMedium: serif.headlineMedium?.copyWith(color: baseColor, fontSize: 22),
          headlineSmall: serif.headlineSmall?.copyWith(color: baseColor, fontSize: 18),
          titleLarge: body.titleLarge?.copyWith(color: baseColor, fontWeight: FontWeight.w700),
          titleMedium: body.titleMedium?.copyWith(color: baseColor, fontWeight: FontWeight.w600),
          titleSmall: body.titleSmall?.copyWith(color: baseColor, fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: baseColor, displayColor: baseColor);
  }
}
