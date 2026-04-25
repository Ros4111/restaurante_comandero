// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String _pass = '';          // contraseña como string interno
  bool _loading = true;
  bool _logging = false;
  String? _error;
  int _intentosFallo = 0;

  @override
  void initState() {
    super.initState();
    _cargarUsuarios();
  }

  // ── Teclado numérico ────────────────────────────────────────
  void _tecla(String v) {
    if (_pass.length < 20) setState(() => _pass += v);
  }

  void _borrar() {
    if (_pass.isNotEmpty) setState(() => _pass = _pass.substring(0, _pass.length - 1));
  }

  // ── Carga de usuarios ───────────────────────────────────────
  Future<void> _cargarUsuarios() async {
    setState(() { _loading = true; _error = null; });
    final api = context.read<ApiService>();
    try {
      final lista = await api.getUsuarios();
      setState(() { _usuarios = lista; _loading = false; });
    } catch (e) {
      _intentosFallo++;
      if (_intentosFallo >= 3) {
        setState(() { _error = 'Imposible conectar con el servidor'; _loading = false; });
      } else {
        await Future.delayed(const Duration(seconds: 2));
        _cargarUsuarios();
      }
    }
  }

  // ── Login ───────────────────────────────────────────────────
  Future<void> _login() async {
    if (_seleccionado == null || _pass.isEmpty) return;
    setState(() { _logging = true; _error = null; });
    final api = context.read<ApiService>();
    try {
      final data = await api.login(_seleccionado!.id, _pass);
      api.setToken(data['token']);

      final catalogo = await api.getCatalogo();
      if (mounted) context.read<CatalogoProvider>().cargar(catalogo);

      if (!mounted) return;
      context.read<SesionProvider>().login(Usuario(
        id: _seleccionado!.id,
        nombre: data['usuario']['nombre'],
        permisos: data['usuario']['permisos'],
        orden: 0,
      ));

      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MesasScreen()));
    } catch (e) {
      setState(() { _error = e.toString(); _logging = false; _pass = ''; });
    }
  }

  void _cerrarApp() {
    SystemNavigator.pop();
  }

  // ── Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Consumer<ApiService>(
              builder: (context, api, _) => Column(
                children: [
                  // Banner servidor inaccesible
                  if (!api.serverReachable)
                    Container(
                      width: double.infinity,
                      color: Colors.red[900],
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_off, color: Colors.white, size: 16),
                          SizedBox(width: 8),
                          Text('SERVIDOR INACCESIBLE',
                              style: TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),

                  // Cuerpo principal estirado
                  Expanded(
                    child: _loading
                        ? const Center(child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Cargando usuarios...'),
                            ]))
                        : _buildForm(),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: 'Cerrar aplicación',
                icon: const Icon(Icons.power_settings_new, color: Colors.white70),
                onPressed: _cerrarApp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    // Pantalla de error de conexión
    if (_error != null && _usuarios.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 56, color: AppTheme.colorAcento),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.colorAcento, fontSize: 16)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _cargarUsuarios, child: const Text('Reintentar')),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const ConfigScreen())),
            child: const Text('Configurar servidor'),
          ),
        ]),
      );
    }

    // Formulario principal — ocupa toda la altura disponible
    return Container(
      color: AppTheme.colorTarjeta,   // fondo gris estirado de arriba a abajo
      child: Column(
        children: [
          // ── Título ──────────────────────────────────────────
          const SizedBox(height: 12),
          const Icon(Icons.restaurant, color: AppTheme.colorPrimario, size: 44),
          const SizedBox(height: 6),
          const Text('Iniciar Sesión',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          // ── Lista de usuarios ────────────────────────────────
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.colorSuperficie,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _usuarios.length,
                itemBuilder: (ctx, i) {
                  final u = _usuarios[i];
                  final sel = _seleccionado?.id == u.id;
                  return ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -2),
                    title: Text(u.nombre,
                        style: TextStyle(
                            fontSize: 17,
                            color: sel ? AppTheme.colorPrimario : AppTheme.colorTexto,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                    tileColor: sel
                        ? AppTheme.colorPrimario.withValues(alpha: 0.15)
                        : null,
                    onTap: () => setState(() {
                      _seleccionado = u;
                      _pass = '';
                    }),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── Display contraseña (solo lectura) ────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.colorSuperficie,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _seleccionado != null
                      ? AppTheme.colorPrimario
                      : Colors.white24,
                  width: 2,
                ),
              ),
              child: Row(children: [
                const Icon(Icons.lock, color: AppTheme.colorTextoGris, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _pass.isEmpty ? 'Contraseña' : '●' * _pass.length,
                    style: TextStyle(
                      fontSize: 20,
                      color: _pass.isEmpty
                          ? AppTheme.colorTextoGris
                          : AppTheme.colorTexto,
                      letterSpacing: _pass.isEmpty ? 0 : 4,
                    ),
                  ),
                ),
              ]),
            ),
          ),

          // ── Error ────────────────────────────────────────────
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 16, right: 16),
              child: Text(_error!,
                  style: const TextStyle(
                      color: AppTheme.colorAcento, fontSize: 13)),
            ),

          const SizedBox(height: 10),

          // ── Teclado numérico ─────────────────────────────────
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _logging
                  ? const Center(child: CircularProgressIndicator())
                  : _Teclado(
                      onTecla: _tecla,
                      onBorrar: _borrar,
                      onOk: _seleccionado != null && _pass.isNotEmpty
                          ? _login
                          : null,
                    ),
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ── Widget teclado numérico ─────────────────────────────────────
class _Teclado extends StatelessWidget {
  final void Function(String) onTecla;
  final VoidCallback onBorrar;
  final VoidCallback? onOk;

  const _Teclado({
    required this.onTecla,
    required this.onBorrar,
    required this.onOk,
  });

  @override
  Widget build(BuildContext context) {
    // Layout:
    // 1  2  3
    // 4  5  6
    // 7  8  9
    // ← 0 Ok
    return Column(
      children: [
        _fila(['1', '2', '3']),
        _fila(['4', '5', '6']),
        _fila(['7', '8', '9']),
        _filaEspecial(),
      ],
    );
  }

  Widget _fila(List<String> nums) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: nums.map((n) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: _BotonNum(
              label: n,
              onTap: () => onTecla(n),
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _filaEspecial() {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Borrar
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _BotonAccion(
                color: const Color(0xFF333333),
                onTap: onBorrar,
                child: const Icon(Icons.backspace_outlined,
                    color: Colors.white70, size: 24),
              ),
            ),
          ),
          // 0
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _BotonNum(label: '0', onTap: () => onTecla('0')),
            ),
          ),
          // Ok / Entrar
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _BotonAccion(
                color: onOk != null
                    ? AppTheme.colorPrimario
                    : AppTheme.colorPrimario.withValues(alpha: 0.35),
                onTap: onOk,
                child: const Text('OK',
                    style: TextStyle(color: Colors.white,
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BotonNum extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _BotonNum({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class _BotonAccion extends StatelessWidget {
  final Widget child;
  final Color color;
  final VoidCallback? onTap;
  const _BotonAccion({required this.child, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}