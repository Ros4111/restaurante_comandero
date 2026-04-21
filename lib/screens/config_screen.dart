// lib/screens/config_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../utils/theme.dart';
import 'login_screen.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _ctrl = TextEditingController(text: 'https://restaurante.guardamar.es');
  bool _loading = false;
  String? _error;

  Future<void> _guardar() async {
    final url = _ctrl.text.trim();
    if (!url.startsWith('https://')) {
      setState(() => _error = 'La URL debe comenzar por https://');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final api = context.read<ApiService>();
    api.setBaseUrl(url);
    final ok = await api.checkHealth();

    if (!mounted) return;
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', url);
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    } else {
      setState(() {
        _error = 'No se puede conectar al servidor. Verifica la URL.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.colorTarjeta,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings, color: AppTheme.colorPrimario, size: 56),
              const SizedBox(height: 16),
              const Text('Configuración del Servidor',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: _ctrl,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  labelText: 'URL del servidor (HTTPS)',
                  filled: true,
                  fillColor: AppTheme.colorSuperficie,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  hintText: 'https://192.168.1.x',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.colorAcento, fontSize: 15)),
              ],
              const SizedBox(height: 24),
              _loading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _guardar,
                        child: const Text('Guardar y Conectar'),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
