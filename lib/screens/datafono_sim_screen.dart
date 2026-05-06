// lib/screens/datafono_sim_screen.dart
// Simulador de datáfono (importe, lectura NFC simulada, ticket SUNMI).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/sunmi_service.dart';
import '../utils/theme.dart';

/// Pantalla inicial: importe + teclado + «Cobrar».
class DatafonoSimScreen extends StatefulWidget {
  const DatafonoSimScreen({super.key});

  @override
  State<DatafonoSimScreen> createState() => _DatafonoSimScreenState();
}

class _DatafonoSimScreenState extends State<DatafonoSimScreen> {
  String _raw = '';

  String get _textoImporte {
    if (_raw.isEmpty) return '0,00';
    if (!_raw.contains(',')) {
      return '${_raw.isEmpty ? '0' : _raw},00';
    }
    final p = _raw.split(',');
    final ent = p[0].isEmpty ? '0' : p[0];
    var dec = p.length > 1 ? p[1] : '';
    dec = dec.padRight(2, '0');
    if (dec.length > 2) dec = dec.substring(0, 2);
    return '$ent,$dec';
  }

  double get _importeValor {
    if (_raw.isEmpty || _raw == ',') return 0;
    if (!_raw.contains(',')) {
      final ent = _raw.isEmpty ? '0' : _raw;
      return double.tryParse('$ent.00') ?? 0;
    }
    final p = _raw.split(',');
    final ent = p[0].isEmpty ? '0' : p[0];
    var dec = p.length > 1 ? p[1] : '';
    dec = dec.padRight(2, '0');
    if (dec.length > 2) dec = dec.substring(0, 2);
    return double.tryParse('$ent.$dec') ?? 0;
  }

  void _digito(String d) {
    if (_raw.contains(',')) {
      final dec = _raw.split(',').length > 1 ? _raw.split(',')[1] : '';
      if (dec.length >= 2) return;
    } else {
      if (_raw.length >= 7) return;
    }
    setState(() => _raw += d);
  }

  void _coma() {
    if (_raw.contains(',')) return;
    setState(() {
      if (_raw.isEmpty) {
        _raw = '0,';
      } else {
        _raw += ',';
      }
    });
  }

  void _borrar() {
    if (_raw.isEmpty) return;
    setState(() => _raw = _raw.substring(0, _raw.length - 1));
  }

  Future<void> _cobrar() async {
    if (_importeValor <= 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Importe'),
          content: const Text('No has introducido el importe'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DatafonoLecturaScreen(importeEtiqueta: '${_textoImporte} €'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Datáfono (simulación)')),
      backgroundColor: AppTheme.colorFondo,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: BoxDecoration(
                  color: AppTheme.colorTarjeta,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Importe a cobrar',
                      style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _textoImporte,
                        style: const TextStyle(
                          color: AppTheme.colorTexto,
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const Text(
                      'EUR',
                      style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  children: [
                    Expanded(child: _TeclaFila(const ['1', '2', '3'], _digito)),
                    Expanded(child: _TeclaFila(const ['4', '5', '6'], _digito)),
                    Expanded(child: _TeclaFila(const ['7', '8', '9'], _digito)),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: _TeclaAccion(
                                label: ',',
                                onTap: _coma,
                                color: const Color(0xFF3D3D3D),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: _TeclaAccion(
                                label: '0',
                                onTap: () => _digito('0'),
                                color: const Color(0xFF2A2A2A),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: _TeclaAccion(
                                icon: Icons.backspace_outlined,
                                onTap: _borrar,
                                color: const Color(0xFF333333),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _cobrar,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Cobrar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeclaFila extends StatelessWidget {
  const _TeclaFila(this.numeros, this.onDigito);

  final List<String> numeros;
  final void Function(String) onDigito;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: numeros
          .map(
            (n) => Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: _TeclaAccion(
                  label: n,
                  onTap: () => onDigito(n),
                  color: const Color(0xFF2A2A2A),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _TeclaAccion extends StatelessWidget {
  const _TeclaAccion({
    required this.onTap,
    required this.color,
    this.label,
    this.icon,
  }) : assert(label != null || icon != null);

  final VoidCallback onTap;
  final Color color;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: icon != null
              ? Icon(icon, color: Colors.white70, size: 24)
              : Text(
                  label!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Pantalla «acerca la tarjeta» + zona táctil y diálogo de conexión simulada.
class DatafonoLecturaScreen extends StatefulWidget {
  const DatafonoLecturaScreen({super.key, required this.importeEtiqueta});

  final String importeEtiqueta;

  @override
  State<DatafonoLecturaScreen> createState() => _DatafonoLecturaScreenState();
}

class _DatafonoLecturaScreenState extends State<DatafonoLecturaScreen>
    with SingleTickerProviderStateMixin {
  bool _enProceso = false;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _zonaLectura() async {
    if (_enProceso) return;
    setState(() => _enProceso = true);

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppTheme.colorTarjeta,
            title: const Text('Conectando'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RotationTransition(
                  turns: _spin,
                  child: const Icon(
                    Icons.sync,
                    size: 56,
                    color: AppTheme.colorPrimario,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Estableciendo conexión segura con el banco…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 15),
                ),
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 6),
              ],
            ),
          ),
        );
      },
    );

    await Future<void>.delayed(const Duration(seconds: 5));

    if (mounted) Navigator.of(context).pop();
    await SunmiService.imprimirTicketDatfonoDenunciada();

    if (mounted) {
      setState(() => _enProceso = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Operación finalizada (impresión si hay SUNMI).')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pago con tarjeta')),
      backgroundColor: AppTheme.colorFondo,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.importeEtiqueta,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.colorTexto,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Acerca tu tarjeta a la zona de lectura',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: AppTheme.colorTextoGris,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Material(
                  color: AppTheme.colorSuperficie,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _enProceso ? null : _zonaLectura,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.nfc,
                            size: math.min(
                              120,
                              MediaQuery.sizeOf(context).shortestSide * 0.28,
                            ),
                            color: _enProceso
                                ? AppTheme.colorTextoGris
                                : AppTheme.colorPrimario,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _enProceso ? 'Procesando…' : 'Pulsa aquí (zona de lectura)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: _enProceso
                                  ? AppTheme.colorTextoGris
                                  : AppTheme.colorTexto,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
