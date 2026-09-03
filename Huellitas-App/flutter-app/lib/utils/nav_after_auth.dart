import 'package:flutter/widgets.dart';
import '../services/auth_service.dart';
import '../screens/app_shell.dart';
import '../screens/force_password_change_screen.dart';
import '../screens/onboarding_screen.dart';

/// Decide a qué pantalla ir justo después de cualquier inicio de sesión
/// (correo, Google, QR, Facebook, registro, verificación de email).
///
/// Antes cada pantalla de login navegaba directo a [AppShell], así que una
/// cuenta sin vivienda —un miembro recién dado de baja, o una cuenta nueva
/// de Google/Facebook que nunca completó el registro— entraba a un panel sin
/// datos que mostrar, sin ninguna indicación de qué hacer. Centralizar la
/// decisión aquí evita que un quinto punto de entrada futuro se olvide de
/// repetirla.
Widget destinoTrasAutenticar() {
  if (AuthService.debeCambiarPassword) return const ForcePasswordChangeScreen();
  if (AuthService.needsOnboarding) return const OnboardingScreen();
  return const AppShell();
}
