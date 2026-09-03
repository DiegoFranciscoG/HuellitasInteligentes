import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

/// Punto de entrada de la app Huellitas Inteligentes: carga la
/// configuración de entorno (`.env`), registra el [ApiService] como
/// provider global y arranca la interfaz mostrando el login.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ApiService()),
      ],
      child: const MyApp(),
    ),
  );
}

/// Raíz de la aplicación: configura el `MaterialApp` (título, tema claro y
/// pantalla inicial de login) para toda la app.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Huellitas inteligentes',
      // Las pantallas de la app están diseñadas sobre fondo claro (tarjetas
      // blancas). Con el tema oscuro, los textos y lo que se escribía en los
      // campos salían en blanco sobre blanco y no se leían.
      theme: AppTheme.light(),
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}