// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/api_service.dart';
import 'services/catalogo_provider.dart';
import 'utils/theme.dart';
import 'screens/config_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pantalla completa / modo kiosco
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString('server_url') ?? '';

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ApiService()..setBaseUrl(savedUrl)),
        ChangeNotifierProvider(create: (_) => SesionProvider()),
        ChangeNotifierProvider(create: (_) => CatalogoProvider()),
        ChangeNotifierProvider(create: (_) => MesaProvider()),
      ],
      child: const RestauranteApp(),
    ),
  );
}

class RestauranteApp extends StatelessWidget {
  const RestauranteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TPV Restaurante',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const Inicio(),
    );
  }
}

class Inicio extends StatefulWidget {
  const Inicio({super.key});
  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _arranque());
  }

  Future<void> _arranque() async {
    final api = context.read<ApiService>();
    if (api.baseUrl.isEmpty) {
      _goConfig();
      return;
    }
    final ok = await api.checkHealth();
    if (!mounted) return;
    if (ok) {
      _goLogin();
    } else {
      _goConfig();
    }
  }

  void _goConfig() => Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => const ConfigScreen()));

  void _goLogin() => Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => const LoginScreen()));

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
