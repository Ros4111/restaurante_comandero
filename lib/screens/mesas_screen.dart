// lib/screens/mesas_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';
import 'hacer_pedido_screen.dart';
import 'login_screen.dart';

class MesasScreen extends StatefulWidget {
  const MesasScreen({super.key});
  @override
  State<MesasScreen> createState() => _MesasScreenState();
}

class _MesasScreenState extends State<MesasScreen> {
  List<MesaResumen> _mesas = [];
  bool _loading = true;
  Timer? _refreshTimer;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarVersion();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _cargar());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _cargarVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = 'v${info.version}');
  }

  Future<void> _cargar() async {
    final api = context.read<ApiService>();
    try {
      final lista = await api.getMesas();
      if (mounted)
        setState(() {
          _mesas = lista;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _abrirMesa() async {
    final ctrl = TextEditingController();
    final numStr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.colorTarjeta,
        title: const Text('Número de mesa'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(fontSize: 22),
          decoration:
              const InputDecoration(labelText: 'Introduce el nº de mesa'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Abrir')),
        ],
      ),
    );

    if (numStr == null || numStr.isEmpty) return;
    final num = int.tryParse(numStr);
    if (num == null || num <= 0) return;

    // Verificar si ya existe
    final existe = _mesas.where((m) => m.idMesa == num).firstOrNull;
    if (existe != null) {
      _entrarMesa(existe);
      return;
    }

    try {
      final api = context.read<ApiService>();
      final idPedido = await api.abrirMesa(num);
      _navPedido(idPedido, num, bloqueadoPorMi: true);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _entrarMesa(MesaResumen mesa) async {
    final api = context.read<ApiService>();
    try {
      await api.bloquearMesa(mesa.idPedido);
      _navPedido(mesa.idPedido, mesa.idMesa, bloqueadoPorMi: true);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        // Mesa bloqueada por otro: entrar en solo lectura
        _navPedido(mesa.idPedido, mesa.idMesa,
            bloqueadoPorMi: false, bloqueador: mesa.nombreUsuarioBloqueo);
      } else {
        _showError(e.toString());
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _navPedido(int idPedido, int idMesa,
      {required bool bloqueadoPorMi, String? bloqueador}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HacerPedidoScreen(
          idPedido: idPedido,
          idMesa: idMesa,
          bloqueadoPorMi: bloqueadoPorMi,
          bloqueador: bloqueador,
        ),
      ),
    ).then((_) => _cargar());
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red[700]));
  }

  void _logout() {
    context.read<SesionProvider>().logout();
    context.read<ApiService>().clearToken();
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    final api = context.watch<ApiService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Mesas · ${sesion.usuario?.nombre ?? ''}'),
        actions: [
          // ── Versión ──────────────────────────────────────────
          if (_version.isNotEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  _version,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
        bottom: api.serverReachable
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(30),
                child: Container(
                  color: Colors.red[900],
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('SERVIDOR INACCESIBLE',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ]),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirMesa,
        icon: const Icon(Icons.add),
        label: const Text('Abrir Mesa'),
        backgroundColor: AppTheme.colorPrimario,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mesas.isEmpty
              ? const Center(
                  child: Text('No hay mesas abiertas',
                      style: TextStyle(
                          fontSize: 20, color: AppTheme.colorTextoGris)))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: _mesas.length,
                  itemBuilder: (ctx, i) => _MesaTile(
                    mesa: _mesas[i],
                    sesion: sesion,
                    onTap: () => _entrarMesa(_mesas[i]),
                  ),
                ),
    );
  }
}

class _MesaTile extends StatelessWidget {
  final MesaResumen mesa;
  final SesionProvider sesion;
  final VoidCallback onTap;

  const _MesaTile(
      {required this.mesa, required this.sesion, required this.onTap});

  String _hhmm(String? value) {
    if (value == null || value.isEmpty) return '--:--';
    final timePart = value.contains(' ') ? value.split(' ').last : value;
    if (timePart.length >= 5) return timePart.substring(0, 5);
    return '--:--';
  }

  @override
  Widget build(BuildContext context) {
    final bloqueadaPorOtro = mesa.idUsuarioBloqueo != null &&
        mesa.idUsuarioBloqueo != sesion.usuario?.id &&
        mesa.horaBloqueo != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.colorTarjeta,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: bloqueadaPorOtro ? Colors.orange : AppTheme.colorPrimario,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${mesa.idMesa}',
                style:
                    const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            //const SizedBox(height: 2),
            Text(mesa.estado,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.colorTextoGris)),
            //const SizedBox(height: 2),
            Text(
                '${_hhmm(mesa.horaCreacion)} -- ${_hhmm(mesa.horaUltimaAccion)}',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.colorTextoGris)),
            if (bloqueadaPorOtro) ...[
              const SizedBox(height: 2),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.lock, color: Colors.orange, size: 14),
                const SizedBox(width: 4),
                Text(mesa.nombreUsuarioBloqueo ?? '?',
                    style: const TextStyle(color: Colors.orange, fontSize: 12)),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
