// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';
import 'mesas_screen.dart';
import 'config_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<Usuario> _usuarios = [];
  Usuario? _seleccionado;
  final _passCtrl = TextEditingController();
  bool _loading = true;
  bool _logging = false;
  String? _error;
  int _intentosFallo = 0;

  @override
  void initState() {
    super.initState();
    _cargarUsuarios();
  }

  Future<void> _cargarUsuarios() async {
    setState(() { _loading = true; _error = null; });
    final api = context.read<ApiService>();
    try {
      final lista = await api.getUsuarios();
      setState(() { _usuarios = lista; _loading = false; });
    } catch (e) {
      _intentosFallo++;
      if (_intentosFallo >= 3) {
        setState(() {
          _error = 'Imposible conectar con el servidor';
          _loading = false;
        });
      } else {
        await Future.delayed(const Duration(seconds: 2));
        _cargarUsuarios();
      }
    }
  }

  Future<void> _login() async {
    if (_seleccionado == null || _passCtrl.text.isEmpty) return;
    setState(() { _logging = true; _error = null; });
    final api = context.read<ApiService>();

    try {
      final data = await api.login(_seleccionado!.id, _passCtrl.text);
      api.setToken(data['token']);

      // Descargar catálogo
      final catalogo = await api.getCatalogo();
      if (mounted) context.read<CatalogoProvider>().cargar(catalogo);

      if (!mounted) return;
      context.read<SesionProvider>().login(
        Usuario(
          id: _seleccionado!.id,
          nombre: data['usuario']['nombre'],
          permisos: data['usuario']['permisos'],
          orden: 0,
        ),
      );

      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MesasScreen()));
    } catch (e) {
      setState(() { _error = e.toString(); _logging = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<ApiService>(
        builder: (context, api, _) => Column(
          children: [
            // Banner servidor inaccesible
            if (!api.serverReachable)
              Container(
                width: double.infinity,
                color: Colors.red[900],
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, color: Colors.white),
                    SizedBox(width: 8),
                    Text('SERVIDOR INACCESIBLE',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
            Expanded(
              child: Center(
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppTheme.colorTarjeta,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _loading
                      ? const Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Cargando usuarios...'),
                        ])
                      : _buildForm(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    if (_error != null && _usuarios.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 56, color: AppTheme.colorAcento),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppTheme.colorAcento, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _cargarUsuarios, child: const Text('Reintentar')),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const ConfigScreen())),
            child: const Text('Configurar servidor'),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.restaurant, color: AppTheme.colorPrimario, size: 56),
        const SizedBox(height: 12),
        const Text('Iniciar Sesión',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        // Lista de usuarios
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: AppTheme.colorSuperficie,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: ListView.builder(
            itemCount: _usuarios.length,
            itemBuilder: (ctx, i) {
              final u = _usuarios[i];
              final sel = _seleccionado?.id == u.id;
              return ListTile(
                title: Text(u.nombre, style: TextStyle(
                    fontSize: 18,
                    color: sel ? AppTheme.colorPrimario : AppTheme.colorTexto,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text(u.permisos,
                    style: const TextStyle(color: AppTheme.colorTextoGris)),
                tileColor: sel ? AppTheme.colorPrimario.withValues(alpha:0.15) : null,
                onTap: () => setState(() {
                  _seleccionado = u;
                  _passCtrl.clear();
                }),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passCtrl,
          obscureText: true,
          style: const TextStyle(fontSize: 20),
          decoration: InputDecoration(
            labelText: 'Contraseña',
            filled: true,
            fillColor: AppTheme.colorSuperficie,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            prefixIcon: const Icon(Icons.lock),
          ),
          onSubmitted: (_) => _login(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: AppTheme.colorAcento)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: _logging
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton.icon(
                  onPressed: _seleccionado != null ? _login : null,
                  icon: const Icon(Icons.login),
                  label: const Text('Entrar'),
                ),
        ),
      ],
    );
  }
}
