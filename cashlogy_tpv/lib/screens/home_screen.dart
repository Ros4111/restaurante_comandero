// lib/screens/home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/cashlogy_service.dart';
import 'config_screen.dart';

// ── Estado de la operación ────────────────────────────────────

enum _Estado {
  listo,
  conectando,
  inicializando,
  cobrando,
  exito,
  cancelado,
  error,
}

// ── Pantalla principal ────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final _fmtEuros = NumberFormat('#,##0.00', 'es_ES');

  // Importe en curso: se acumula como cadena de dígitos
  String _digitos = ''; // '' = 0.00
  _Estado _estado = _Estado.listo;
  String _mensajeEstado = 'Introduce el importe y pulsa COBRAR';
  CashlogyChargeResult? _resultado;
  CashlogyConfig? _config;
  int _contadorOp = 0;

  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }

  Future<void> _cargarConfig() async {
    _config = await CashlogyConfig.load();
    if (mounted) setState(() {});
  }

  // ── Importes ────────────────────────────────────────────────

  /// Convierte los dígitos acumulados a double (2 decimales fijos).
  /// "1234" → 12.34 €  |  "5" → 0.05 €  |  "" → 0.00 €
  double get _importeEuros {
    if (_digitos.isEmpty) return 0.0;
    final n = int.tryParse(_digitos) ?? 0;
    return n / 100.0;
  }

  int get _importeCentimos => int.tryParse(_digitos) ?? 0;

  String get _importeTexto => '${_fmtEuros.format(_importeEuros)} €';

  // ── Teclado ──────────────────────────────────────────────────

  void _pulsarDigito(String d) {
    if (_estado != _Estado.listo && _estado != _Estado.exito &&
        _estado != _Estado.cancelado && _estado != _Estado.error) return;
    setState(() {
      if (_estado != _Estado.listo) {
        // Tras un resultado, empezar nuevo importe
        _digitos = '';
        _resultado = null;
        _estado = _Estado.listo;
        _mensajeEstado = 'Introduce el importe y pulsa COBRAR';
      }
      if (_digitos.isEmpty && d == '0') return; // no añadir ceros al inicio
      if (_digitos.length >= 7) return; // max 99999.99 €
      _digitos += d;
    });
  }

  void _pulsarBorrar() {
    if (_estado != _Estado.listo && _estado != _Estado.exito &&
        _estado != _Estado.cancelado && _estado != _Estado.error) return;
    setState(() {
      if (_estado != _Estado.listo) {
        _digitos = '';
        _resultado = null;
        _estado = _Estado.listo;
        _mensajeEstado = 'Introduce el importe y pulsa COBRAR';
        return;
      }
      if (_digitos.isNotEmpty) {
        _digitos = _digitos.substring(0, _digitos.length - 1);
      }
    });
  }

  void _pulsarLimpiar() {
    if (_estado == _Estado.cobrando ||
        _estado == _Estado.conectando ||
        _estado == _Estado.inicializando) return;
    setState(() {
      _digitos = '';
      _resultado = null;
      _estado = _Estado.listo;
      _mensajeEstado = 'Introduce el importe y pulsa COBRAR';
    });
  }

  // ── Cobro ─────────────────────────────────────────────────────

  Future<void> _cobrar() async {
    if (_importeCentimos <= 0) {
      setState(() {
        _mensajeEstado = 'Introduce un importe mayor que cero';
      });
      return;
    }
    if (_config == null) {
      setState(() {
        _mensajeEstado = 'Configura la conexión con Cashlogy primero';
      });
      return;
    }

    _contadorOp++;
    final numOp = 'TPV${DateTime.now().millisecondsSinceEpoch}';
    final centimos = _importeCentimos;
    final cfg = _config!;

    setState(() {
      _estado = _Estado.conectando;
      _mensajeEstado = 'Conectando con Cashlogy (${cfg.host}:${cfg.port})…';
      _resultado = null;
    });

    try {
      setState(() {
        _estado = _Estado.inicializando;
        _mensajeEstado = 'Inicializando Cashlogy…';
      });

      final svc = CashlogyService();

      final init = await svc.inicializar(cfg);
      if (!init.ok) {
        setState(() {
          _estado = _Estado.error;
          _mensajeEstado =
              'Error al inicializar: ${init.error ?? init.raw}';
        });
        return;
      }

      setState(() {
        _estado = _Estado.cobrando;
        _mensajeEstado =
            'Esperando efectivo en Cashlogy…\n'
            'El cliente debe introducir ${_fmtEuros.format(centimos / 100.0)} €';
      });

      final result = await svc.cobrar(
        cfg: cfg,
        centimos: centimos,
        numOperacion: numOp,
      );

      if (!mounted) return;

      if (result.cancelled) {
        setState(() {
          _estado = _Estado.cancelado;
          _resultado = result;
          _mensajeEstado = 'Cobro cancelado';
        });
        return;
      }

      setState(() {
        _resultado = result;
        _estado = result.ok ? _Estado.exito : _Estado.error;
        _mensajeEstado = result.ok ? '¡Cobro completado!' : result.message ?? 'Error';
      });
    } on CashlogyException catch (e) {
      if (!mounted) return;
      setState(() {
        _estado = _Estado.error;
        _mensajeEstado = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _estado = _Estado.error;
        _mensajeEstado = 'Error inesperado: $e';
      });
    }
  }

  // ── Navegación ────────────────────────────────────────────────

  Future<void> _abrirConfig() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConfigScreen()),
    );
    await _cargarConfig();
  }

  // ── BUILD ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ocupado = _estado == _Estado.conectando ||
        _estado == _Estado.inicializando ||
        _estado == _Estado.cobrando;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Row(
          children: [
            Icon(Icons.toll_outlined, color: Color(0xFF58A6FF)),
            SizedBox(width: 10),
            Text('Cobro Cashlogy',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        actions: [
          if (_config != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Chip(
                avatar: Icon(
                  Icons.circle,
                  size: 10,
                  color: _config!.host.isNotEmpty
                      ? Colors.greenAccent
                      : Colors.red,
                ),
                label: Text(
                  '${_config!.host}:${_config!.port}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                backgroundColor: const Color(0xFF21262D),
                side: BorderSide.none,
              ),
            ),
          IconButton(
            tooltip: 'Configuración',
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: ocupado ? null : _abrirConfig,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                // ── Display de importe ─────────────────────────
                _ImporteDisplay(
                  texto: _importeTexto,
                  estado: _estado,
                ),
                const SizedBox(height: 16),
                // ── Panel de resultado ─────────────────────────
                _ResultadoPanel(resultado: _resultado, estado: _estado),
                const SizedBox(height: 12),
                // ── Teclado numérico ───────────────────────────
                Expanded(
                  child: _Teclado(
                    onDigito: _pulsarDigito,
                    onBorrar: _pulsarBorrar,
                    onLimpiar: _pulsarLimpiar,
                    deshabilitado: ocupado,
                  ),
                ),
                const SizedBox(height: 16),
                // ── Botón cobrar / estado ──────────────────────
                _BotonCobrar(
                  estado: _estado,
                  mensaje: _mensajeEstado,
                  onCobrar: ocupado ? null : _cobrar,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Widget: display del importe ───────────────────────────────

class _ImporteDisplay extends StatelessWidget {
  final String texto;
  final _Estado estado;
  const _ImporteDisplay({required this.texto, required this.estado});

  Color get _color => switch (estado) {
        _Estado.exito => const Color(0xFF3FB950),
        _Estado.error => const Color(0xFFF85149),
        _Estado.cancelado => const Color(0xFFD29922),
        _Estado.cobrando => const Color(0xFF58A6FF),
        _ => Colors.white,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _color.withValues(alpha: 0.6),
          width: 2,
        ),
      ),
      child: Text(
        texto,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.bold,
          color: _color,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ── Widget: panel de resultado ────────────────────────────────

class _ResultadoPanel extends StatelessWidget {
  final CashlogyChargeResult? resultado;
  final _Estado estado;
  const _ResultadoPanel({this.resultado, required this.estado});

  static final _fmt = NumberFormat('#,##0.00', 'es_ES');
  String _e(double v) => '${_fmt.format(v)} €';

  @override
  Widget build(BuildContext context) {
    final r = resultado;
    if (r == null || estado == _Estado.listo || estado == _Estado.conectando ||
        estado == _Estado.inicializando || estado == _Estado.cobrando) {
      return const SizedBox(height: 4);
    }

    final isOk = estado == _Estado.exito;
    final isCancelled = estado == _Estado.cancelado;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOk
            ? const Color(0xFF0D2818)
            : isCancelled
                ? const Color(0xFF271D0C)
                : const Color(0xFF2D1414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOk
              ? const Color(0xFF3FB950)
              : isCancelled
                  ? const Color(0xFFD29922)
                  : const Color(0xFFF85149),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isOk
                    ? Icons.check_circle
                    : isCancelled
                        ? Icons.cancel
                        : Icons.error,
                color: isOk
                    ? const Color(0xFF3FB950)
                    : isCancelled
                        ? const Color(0xFFD29922)
                        : const Color(0xFFF85149),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isOk
                    ? 'COBRO COMPLETADO'
                    : isCancelled
                        ? 'CANCELADO'
                        : 'ERROR',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isOk
                      ? const Color(0xFF3FB950)
                      : isCancelled
                          ? const Color(0xFFD29922)
                          : const Color(0xFFF85149),
                ),
              ),
            ],
          ),
          if (isOk || r.autoCents > 0 || r.manualCents > 0) ...[
            const SizedBox(height: 10),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 8),
            _Fila('Solicitado', _e(r.requestedEuros)),
            if (r.autoCents > 0) _Fila('Automático', _e(r.autoEuros)),
            if (r.manualCents > 0) _Fila('Manual', _e(r.manualEuros)),
            if (r.returnedCents > 0) _Fila('Devuelto', _e(r.returnedEuros)),
            if (r.changeCents > 0) _Fila('Cambio dado', _e(r.changeEuros)),
          ],
          if (r.message != null && !isOk) ...[
            const SizedBox(height: 8),
            Text(
              r.message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String label;
  final String valor;
  const _Fila(this.label, this.valor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(valor,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Widget: teclado numérico ──────────────────────────────────

class _Teclado extends StatelessWidget {
  final void Function(String) onDigito;
  final VoidCallback onBorrar;
  final VoidCallback onLimpiar;
  final bool deshabilitado;

  const _Teclado({
    required this.onDigito,
    required this.onBorrar,
    required this.onLimpiar,
    this.deshabilitado = false,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _Btn('1', onTap: () => onDigito('1'), disabled: deshabilitado),
        _Btn('2', onTap: () => onDigito('2'), disabled: deshabilitado),
        _Btn('3', onTap: () => onDigito('3'), disabled: deshabilitado),
        _Btn('4', onTap: () => onDigito('4'), disabled: deshabilitado),
        _Btn('5', onTap: () => onDigito('5'), disabled: deshabilitado),
        _Btn('6', onTap: () => onDigito('6'), disabled: deshabilitado),
        _Btn('7', onTap: () => onDigito('7'), disabled: deshabilitado),
        _Btn('8', onTap: () => onDigito('8'), disabled: deshabilitado),
        _Btn('9', onTap: () => onDigito('9'), disabled: deshabilitado),
        _Btn('C',
            onTap: onLimpiar,
            disabled: deshabilitado,
            color: const Color(0xFF6E3629)),
        _Btn('0', onTap: () => onDigito('0'), disabled: deshabilitado),
        _Btn('⌫',
            onTap: onBorrar,
            disabled: deshabilitado,
            color: const Color(0xFF21262D)),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool disabled;
  final Color? color;

  const _Btn(this.label,
      {required this.onTap, this.disabled = false, this.color});

  @override
  Widget build(BuildContext context) {
    final bg = disabled
        ? const Color(0xFF161B22)
        : (color ?? const Color(0xFF21262D));
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: disabled ? null : onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: disabled ? Colors.white24 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Widget: botón cobrar ──────────────────────────────────────

class _BotonCobrar extends StatelessWidget {
  final _Estado estado;
  final String mensaje;
  final VoidCallback? onCobrar;

  const _BotonCobrar({
    required this.estado,
    required this.mensaje,
    this.onCobrar,
  });

  @override
  Widget build(BuildContext context) {
    final ocupado = estado == _Estado.conectando ||
        estado == _Estado.inicializando ||
        estado == _Estado.cobrando;

    return Column(
      children: [
        // Mensaje de estado
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Container(
            key: ValueKey(mensaje),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (ocupado) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    mensaje,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: switch (estado) {
                        _Estado.exito => const Color(0xFF3FB950),
                        _Estado.error => const Color(0xFFF85149),
                        _Estado.cancelado => const Color(0xFFD29922),
                        _Estado.cobrando => const Color(0xFF58A6FF),
                        _ => Colors.white60,
                      },
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Botón principal
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: onCobrar,
            style: ElevatedButton.styleFrom(
              backgroundColor: ocupado
                  ? const Color(0xFF21262D)
                  : const Color(0xFF1A7F37),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF21262D),
              disabledForegroundColor: Colors.white24,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: ocupado
                ? const Text('PROCESANDO…',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.toll_outlined, size: 22),
                      SizedBox(width: 10),
                      Text('COBRAR',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
