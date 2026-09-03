import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radii.dart';
import 'app_text_theme.dart';

/// Tema central de la app. `dark()` es el tema por defecto en móvil
/// (siguiendo las referencias visuales: tarjetas oscuras, foto de mascota
/// como hero, acentos ámbar). `light()` se usa para el panel de contenido
/// en pantallas anchas (≥768px), igual que el canvas claro de `huellitas-web`,
/// mientras la barra lateral se mantiene oscura en ambos casos.
/// Transición de pantalla: entra deslizando un poco desde abajo mientras
/// aparece. Es discreta y da sensación de continuidad al navegar.
class _DeslizarDesvanecer extends PageTransitionsBuilder {
  const _DeslizarDesvanecer();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curva = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curva,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(curva),
        child: child,
      ),
    );
  }
}

/// Fábrica de los `ThemeData` de la app. Ver [dark] y [light].
class AppTheme {
  AppTheme._();

  /// Tema oscuro, usado por defecto en móvil (tarjetas oscuras, foto de
  /// mascota como hero, acentos ámbar).
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.primaryLight,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: AppColors.primary,
      surface: AppColors.surfaceCardDark,
      onSurface: AppColors.onSurfaceDark,
      error: AppColors.error,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      // Transición suave al abrir cualquier pantalla, en toda la app.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _DeslizarDesvanecer(),
        TargetPlatform.iOS: _DeslizarDesvanecer(),
      }),
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surfaceDark,
      textTheme: AppTextTheme.build(AppColors.onSurfaceDark),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: AppColors.onSurfaceDark,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceCardDark,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.xlRadius),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.fullRadius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurfaceDark,
          side: const BorderSide(color: AppColors.outlineDark),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.fullRadius),
        ),
      ),
      // Los campos de escritura van sobre fondo blanco en toda la app, así que
      // el texto y el cursor van en oscuro: con el color claro del tema
      // quedaban blancos sobre blanco y no se leía nada de lo que se escribía.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: AppRadii.lgRadius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.lgRadius,
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.onSurfaceVariantLight),
        labelStyle: const TextStyle(color: AppColors.onSurfaceVariantLight),
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.primary),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceCardDark,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.onSurfaceVariantDark,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.primary,
        selectedIconTheme: const IconThemeData(color: AppColors.accent),
        unselectedIconTheme: IconThemeData(color: Colors.white.withOpacity(0.65)),
        selectedLabelTextStyle: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: TextStyle(color: Colors.white.withOpacity(0.65)),
        indicatorColor: AppColors.accent.withOpacity(0.15),
      ),
      dividerColor: AppColors.outlineDark,
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.accent : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent.withOpacity(0.4)
              : AppColors.outlineDark,
        ),
      ),
    );
  }

  /// Tema claro, usado en el panel de contenido de pantallas anchas
  /// (≥768px), igual que el canvas claro de `huellitas-web`.
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: AppColors.primary,
      surface: AppColors.surfaceCardLight,
      onSurface: AppColors.onSurfaceLight,
      error: AppColors.error,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      // Transición suave al abrir cualquier pantalla, en toda la app.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _DeslizarDesvanecer(),
        TargetPlatform.iOS: _DeslizarDesvanecer(),
      }),
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surfaceLight,
      textTheme: AppTextTheme.build(AppColors.onSurfaceLight),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceCardLight,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.xlRadius,
          side: BorderSide(color: AppColors.outlineLight.withOpacity(0.4)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.fullRadius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.fullRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: AppRadii.lgRadius,
          borderSide: const BorderSide(color: AppColors.outlineLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.lgRadius,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.onSurfaceVariantLight),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.onSurfaceVariantLight,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.primary,
        selectedIconTheme: const IconThemeData(color: AppColors.accent),
        unselectedIconTheme: IconThemeData(color: Colors.white.withOpacity(0.65)),
        selectedLabelTextStyle: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: TextStyle(color: Colors.white.withOpacity(0.65)),
        indicatorColor: AppColors.accent.withOpacity(0.15),
      ),
      dividerColor: AppColors.outlineLight,
    );
  }
}
