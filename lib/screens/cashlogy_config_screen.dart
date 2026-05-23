import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cashlogy_service.dart';
import '../utils/theme.dart';

class CashlogyConfigScreen extends StatefulWidget {
  const CashlogyConfigScreen({super.key});

  @override
  State<CashlogyConfigScreen> createState() => _CashlogyConfigScreenState();
}

class _CashlogyConfigScreenState extends State<CashlogyConfigScreen> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _tillCtrl = TextEditingController();
  bool _cargando = false;
  bool _habilitado = false;
  String? _log;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _tillCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final cfg = await CashlogyService.loadConfig();
    final habilitado = await CashlogyService.isEnabled();
    _hostCtrl.text = cfg.host;
    _portCtrl.text = '${cfg.port}';
    _tillCtrl.text = cfg.tillCode;
    if (mounted) {
      setState(() => _habilitado = habilitado);
    }
  }

  Future<void> _cambiarHabilitado(bool value) async {
    await CashlogyService.setEnabled(value);
    if (mounted) setState(() => _habilitado = value);
    _mostrarSnack(
      value
          ? 'Cobro con Cashlogy activado al cerrar mesa'
          : 'Cobro con Cashlogy desactivado (la configuración se conserva)',
    );
  }

  Future<CashlogyConfig?> _guardarConfig() async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      _mostrarSnack('IP y puerto válidos son obligatorios');
      return null;
    }
    final cfg = CashlogyConfig(
      host: host,
      port: port,
      tillCode: _tillCtrl.text.trim().isEmpty ? 'TPV' : _tillCtrl.text.trim(),
    );
    await CashlogyService.saveConfig(cfg);
    return cfg;
  }

  void _mostrarSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red[900] : Colors.green[800],
      ),
    );
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    if (_cargando) return;
    setState(() {
      _cargando = true;
      _log = null;
    });
    try {
      await accion();
    } on CashlogyException catch (e) {
      setState(() => _log = e.message);
      _mostrarSnack(e.message, error: true);
    } catch (e) {
      setState(() => _log = e.toString());
      _mostrarSnack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _inicializar() async {
    await _ejecutar(() async {
      final cfg = await _guardarConfig();
      if (cfg == null) return;
      final r = await CashlogyService().inicializar(config: cfg);
      setState(() {
        _log = r.rawResponse;
      });
      if (r.ok) {
        _mostrarSnack(
          'Cashlogy inicializado'
          '${r.protocolVersion != null ? ' (v${r.protocolVersion})' : ''}',
        );
      } else {
        _mostrarSnack(r.message ?? 'Error al inicializar', error: true);
      }
    });
  }

  Future<void> _cobrarPrueba() async {
    await _ejecutar(() async {
      final cfg = await _guardarConfig();
      if (cfg == null) return;
      const importe = 10.25;
      final centimos = CashlogyService.eurosACentimos(importe);
      final r = await CashlogyService().cobrar(
        importeCentimos: centimos,
        numeroOperacion: 'TEST1025',
        config: cfg,
      );
      setState(() {
        _log = '${r.rawResponse}\n'
            'Cobrado auto: ${r.amountChargedAuto} cts · '
            'Devuelto: ${r.amountReturned} cts · '
            'Manual: ${r.amountManual} cts';
      });
      if (r.ok) {
        _mostrarSnack('Cobro de ${importe.toStringAsFixed(2)} € correcto');
      } else {
        _mostrarSnack(r.message ?? 'Cobro no completado', error: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cashlogy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Cobro al cerrar mesa',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _habilitado
                    ? 'Al cerrar una mesa con importe se cobra en Cashlogy.'
                    : 'Desactivado: cerrar mesa no usa Cashlogy. Puedes seguir configurando y probando aquí.',
                style: const TextStyle(
                  color: AppTheme.colorTextoGris,
                  fontSize: 13,
                ),
              ),
              value: _habilitado,
              onChanged: _cargando ? null : _cambiarHabilitado,
            ),
            const Divider(height: 24),
            const Text(
              'Conexión con Cashlogy Connector (TCP). '
              'El PC debe tener Connector en ejecución y la máquina encendida.',
              style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hostCtrl,
              decoration: const InputDecoration(
                labelText: 'IP del PC Connector',
                hintText: CashlogyConfig.defaultHost,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portCtrl,
              decoration: const InputDecoration(
                labelText: 'Puerto',
                hintText: '${CashlogyConfig.defaultPort}',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tillCtrl,
              decoration: const InputDecoration(
                labelText: 'Código de caja (parámetro b del cobro)',
                hintText: 'TPV',
              ),
            ),
            const SizedBox(height: 20),
            if (_cargando)
              const Center(child: CircularProgressIndicator())
            else ...[
              ElevatedButton.icon(
                onPressed: _inicializar,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Inicializar máquina (#I#)'),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _cobrarPrueba,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Cobrar prueba 10,25 €'),
              ),
            ],
            if (_log != null) ...[
              const SizedBox(height: 20),
              const Text(
                'Última respuesta',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              SelectableText(
                _log!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppTheme.colorTextoGris,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
