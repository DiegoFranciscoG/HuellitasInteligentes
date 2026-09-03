import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Sombras equivalentes a `--shadow-*` en `huellitas-web/src/styles.scss`,
/// tintadas con el verde de marca en vez de negro puro.
class AppShadows {
  AppShadows._();

  static List<BoxShadow> sm = [
    BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 2)),
  ];

  static List<BoxShadow> md = [
    BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 25, offset: const Offset(0, 10)),
    BoxShadow(color: AppColors.primary.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
  ];

  static List<BoxShadow> lg = [
    BoxShadow(color: AppColors.primary.withOpacity(0.12), blurRadius: 60, offset: const Offset(0, 30)),
    BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 12)),
  ];
}
