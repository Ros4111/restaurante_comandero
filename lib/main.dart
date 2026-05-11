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

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

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

class RestauranteApp extends StatefulWidget {
  const RestauranteApp({super.key});

  @override
  State<RestauranteApp> createState() => _RestauranteAppState();
}

class _RestauranteAppState extends State<RestauranteApp> {
  late ApiService _api;
  bool _initialized = false;
  bool _mostrandoDialogo = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _api = context.read<ApiService>();
      _api.addListener(_onApiChange);
    }
  }

  @override
  void dispose() {
    _api.removeListener(_onApiChange);
    super.dispose();
  }

  void _onApiChange() {
    if (_api.tokenExpirado && !_mostrandoDialogo) {
      _mostrandoDialogo = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _mostrarDialogoSesion());
    }
  }

  Future<void> _mostrarDialogoSesion() async {
    final nav = _navigatorKey.currentState;
    if (nav == null || !mounted) {
      _mostrandoDialogo = false;
      return;
    }

    await showDialog(
      context: nav.overlay!.context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.colorTarjeta,
        title: const Text('Reiniciar sesión'),
        content: const Text(
            'La sesión ha caducado o no es válida. Inicia sesión de nuevo.'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(nav.overlay!.context).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );

    _api.clearToken();
    _api.resetTokenExpirado();
    if (mounted) context.read<SesionProvider>().logout();
    _mostrandoDialogo = false;

    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TPV Restaurante',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      navigatorKey: _navigatorKey,
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
      context,
      MaterialPageRoute(
          builder: (_) => const ConfigScreen(
                showUrlConfig: true,
                showPrinterConfig: false,
              )));

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
