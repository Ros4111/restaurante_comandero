// lib/screens/config_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cashlogy_service.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _tillCtrl = TextEditingController();

  bool _guardando = false;
  bool _probando = false;
  String? _resultadoPrueba;
  bool _pruebaOk = false;

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
    final cfg = await CashlogyConfig.load();
    _hostCtrl.text = cfg.host;
    _portCtrl.text = cfg.port.toString();
    _tillCtrl.text = cfg.tillCode;
    if (mounted) setState(() {});
  }

  CashlogyConfig _configActual() => CashlogyConfig(
        host: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? CashlogyConfig.defaultPort,
        tillCode: _tillCtrl.text.trim().isEmpty
            ? 'TPV'
            : _tillCtrl.text.trim(),
      );

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    await _configActual().save();
    if (!mounted) return;
    setState(() => _guardando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Configuración guardada'),
          backgroundColor: Color(0xFF1A7F37)),
    );
  }

  Future<void> _probar() async {
    final cfg = _configActual();
    if (cfg.host.isEmpty) {
      setState(() {
        _resultadoPrueba = 'Introduce la IP del Cashlogy Connector';
        _pruebaOk = false;
      });
      return;
    }

    setState(() {
      _probando = true;
      _resultadoPrueba = null;
    });

    try {
      final svc = CashlogyService();
      final result = await svc.inicializar(cfg);
      if (!mounted) return;
      setState(() {
        _probando = false;
        _pruebaOk = result.ok;
        _resultadoPrueba = result.ok
            ? 'Conexión OK · Protocolo v${result.version ?? '?'}'
            : 'Error: ${result.error ?? result.raw}';
      });
    } on CashlogyException catch (e) {
      if (!mounted) return;
      setState(() {
        _probando = false;
        _pruebaOk = false;
        _resultadoPrueba = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probando = false;
        _pruebaOk = false;
        _resultadoPrueba = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Configuración Cashlogy',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Sección: Conexión ──────────────────────────
                _Seccion(
                  icon: Icons.settings_ethernet,
                  titulo: 'Cashlogy Connector',
                  subtitulo:
                      'Dirección IP y puerto TCP del Connector instalado en el PC con la máquina.',
                ),
                const SizedBox(height: 16),
                _Campo(
                  label: 'Dirección IP',
                  hint: CashlogyConfig.defaultHost,
                  controller: _hostCtrl,
                  teclado: TextInputType.url,
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                const SizedBox(height: 12),
                _Campo(
                  label: 'Puerto TCP',
                  hint: '${CashlogyConfig.defaultPort}',
                  controller: _portCtrl,
                  teclado: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 12),
                _Campo(
                  label: 'Código de caja',
                  hint: 'TPV',
                  helper: 'Identificador de este terminal en Cashlogy',
                  controller: _tillCtrl,
                  maxLength: 20,
                ),
                const SizedBox(height: 24),
                // ── Botón probar ───────────────────────────────
                OutlinedButton.icon(
                  onPressed: _probando ? null : _probar,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF58A6FF),
                    side: const BorderSide(color: Color(0xFF30363D)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _probando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.power_settings_new, size: 18),
                  label: Text(_probando
                      ? 'Probando conexión…'
                      : 'Probar conexión (#I#)'),
                ),
                // Resultado prueba
                if (_resultadoPrueba != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _pruebaOk
                          ? const Color(0xFF0D2818)
                          : const Color(0xFF2D1414),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _pruebaOk
                            ? const Color(0xFF3FB950)
                            : const Color(0xFFF85149),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _pruebaOk ? Icons.check_circle : Icons.error,
                          color: _pruebaOk
                              ? const Color(0xFF3FB950)
                              : const Color(0xFFF85149),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _resultadoPrueba!,
                            style: TextStyle(
                              color: _pruebaOk
                                  ? const Color(0xFF3FB950)
                                  : const Color(0xFFF85149),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // ── Botón guardar ──────────────────────────────
                ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A7F37),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  icon: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 20),
                  label: Text(
                    _guardando ? 'Guardando…' : 'Guardar configuración',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 32),
                // ── Ayuda ──────────────────────────────────────
                _InfoBox(
                  icon: Icons.info_outline,
                  texto: 'El Cashlogy Connector debe estar en ejecución en el '
                      'PC al que está conectada la máquina de efectivo. '
                      'La IP por defecto es ${CashlogyConfig.defaultHost} '
                      'y el puerto ${CashlogyConfig.defaultPort}.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────

class _Seccion extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String? subtitulo;
  const _Seccion({required this.icon, required this.titulo, this.subtitulo});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF58A6FF), size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              if (subtitulo != null) ...[
                const SizedBox(height: 2),
                Text(subtitulo!,
                    style: const TextStyle(
                        color: Color(0xFF8B949E), fontSize: 12)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Campo extends StatelessWidget {
  final String label;
  final String hint;
  final String? helper;
  final TextEditingController controller;
  final TextInputType teclado;
  final List<TextInputFormatter> formatters;
  final int? maxLength;

  const _Campo({
    required this.label,
    required this.hint,
    required this.controller,
    this.helper,
    this.teclado = TextInputType.text,
    this.formatters = const [],
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: teclado,
      inputFormatters: formatters,
      maxLength: maxLength,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      cursorColor: const Color(0xFF58A6FF),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8B949E)),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF484F58)),
        helperText: helper,
        helperStyle: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
        counterStyle: const TextStyle(color: Color(0xFF8B949E)),
        filled: true,
        fillColor: const Color(0xFF161B22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF30363D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: Color(0xFF58A6FF), width: 1.5),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String texto;
  const _InfoBox({required this.icon, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF8B949E)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                  color: Color(0xFF8B949E), fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
