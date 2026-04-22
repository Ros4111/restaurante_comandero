// lib/screens/config_screen.dart
import 'dart:io';
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
  
  IconData? _errorIcon;

  // Comprueba si hay salida a internet intentando resolver un dominio conocido
  Future<bool> _hayInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _guardar() async {
    final url = _ctrl.text.trim();
    if (!url.startsWith('https://')) {
      setState(() {
        _error = 'La URL debe comenzar por https://';
        _errorIcon = Icons.link_off;
      });
      return;
    }

    setState(() { _loading = true; _error = null; _errorIcon = null; });

    // 1. Comprobar internet primero
    final internet = await _hayInternet();
    if (!mounted) return;
    if (!internet) {
      setState(() {
        _error = 'Sin conexión a Internet. Comprueba el WiFi o los datos móviles.';
        _errorIcon = Icons.wifi_off;
        _loading = false;
      });
      return;
    }

    // 2. Comprobar que el servidor responde
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
        _error = 'Internet OK, pero el servidor no responde.\nVerifica que la URL sea correcta y el servidor esté encendido.';
        _errorIcon = Icons.dns_outlined;
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
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[900]!.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.colorAcento.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_errorIcon ?? Icons.error_outline,
                          color: AppTheme.colorAcento, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _loading
                  ? const Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 10),
                        Text('Comprobando conexión...',
                            style: TextStyle(color: AppTheme.colorTextoGris)),
                      ],
                    )
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
