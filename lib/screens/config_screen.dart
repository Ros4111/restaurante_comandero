// lib/screens/config_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../utils/theme.dart';
import 'login_screen.dart';

class ConfigScreen extends StatefulWidget {
  final bool showUrlConfig;
  final bool showPrinterConfig;
  final bool navigateToLoginOnSave;

  const ConfigScreen({
    super.key,
    this.showUrlConfig = true,
    this.showPrinterConfig = false,
    this.navigateToLoginOnSave = true,
  });
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _ctrl = TextEditingController(text: 'https://restaurante.guardamar.es');
  final List<_ImpresoraFormData> _impresoras = [];
  bool _loading = false;
  bool _loadingImpresoras = false;
  String? _error;
  IconData? _errorIcon;

  @override
  void initState() {
    super.initState();
    _initConfig();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    for (final imp in _impresoras) {
      imp.dispose();
    }
    super.dispose();
  }

  Future<void> _initConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('server_url');
    if (savedUrl != null && savedUrl.trim().isNotEmpty) {
      _ctrl.text = savedUrl.trim();
    }
    if (!mounted) return;
    if (widget.showPrinterConfig) {
      await _cargarImpresoras();
    }
  }

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

  Future<void> _cargarImpresoras() async {
    final url = _ctrl.text.trim();
    if (!url.startsWith('https://')) return;
    setState(() {
      _loadingImpresoras = true;
      _error = null;
      _errorIcon = null;
    });
    try {
      final api = context.read<ApiService>();
      api.setBaseUrl(url);
      final ok = await api.checkHealth();
      if (!ok) {
        throw Exception('Servidor no accesible');
      }
      final data = await api.getImpresorasConfig();
      if (!mounted) return;
      for (final imp in _impresoras) {
        imp.dispose();
      }
      _impresoras
        ..clear()
        ..addAll(data.map(_ImpresoraFormData.fromJson));
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'No se pudo cargar la configuración de impresoras. Revisa la URL.';
        _errorIcon = Icons.print_disabled;
      });
    } finally {
      if (!mounted) return;
      setState(() => _loadingImpresoras = false);
    }
  }

  Future<void> _guardar() async {
    final url = _ctrl.text.trim();
    if (widget.showUrlConfig && !url.startsWith('https://')) {
      setState(() {
        _error = 'La URL debe comenzar por https://';
        _errorIcon = Icons.link_off;
      });
      return;
    }

    if (widget.showPrinterConfig) {
      for (final imp in _impresoras) {
        if (int.tryParse(imp.puertoCtrl.text.trim()) == null) {
          setState(() {
            _error = 'El puerto de "${imp.nombreCtrl.text.trim()}" no es válido.';
            _errorIcon = Icons.warning_amber_rounded;
          });
          return;
        }
      }
    }

    setState(() {
      _loading = true;
      _error = null;
      _errorIcon = null;
    });

    // 1. Comprobar internet primero
    final internet = await _hayInternet();
    if (!mounted) return;
    if (!internet) {
      setState(() {
        _error = 'Sin conexión a Internet. Comprueba el WiFi.';
        _errorIcon = Icons.wifi_off;
        _loading = false;
      });
      return;
    }

    final api = context.read<ApiService>();
    if (widget.showUrlConfig) {
      api.setBaseUrl(url);
    }
    final ok = await api.checkHealth();

    if (!mounted) return;
    if (ok) {
      if (widget.showPrinterConfig) {
        try {
          await api.saveImpresorasConfig(
            _impresoras
                .map((e) => {
                      'id_impresora': e.id,
                      'nombre': e.nombreCtrl.text.trim(),
                      'ip': e.ipCtrl.text.trim(),
                      'puerto': int.parse(e.puertoCtrl.text.trim()),
                      'tabla_codigos': e.tablaCodigosCtrl.text.trim().toUpperCase(),
                    })
                .toList(),
          );
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _error = 'No se pudo guardar la configuración de impresoras.';
            _errorIcon = Icons.print_disabled;
            _loading = false;
          });
          return;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      if (widget.showUrlConfig) {
        await prefs.setString('server_url', url);
      }
      if (mounted) {
        if (widget.navigateToLoginOnSave) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        } else {
          Navigator.pop(context, true);
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _error =
              'Internet OK, pero el servidor no responde.\nVerifica que la URL sea correcta y el servidor esté encendido.';
          _errorIcon = Icons.dns_outlined;
          _loading = false;
        });
      }
    }
  }

  Future<void> _crearImpresora() async {
    final api = context.read<ApiService>();
    setState(() {
      _loadingImpresoras = true;
      _error = null;
      _errorIcon = null;
    });
    try {
      final nueva = await api.crearImpresoraConfig();
      if (!mounted) return;
      _impresoras.add(_ImpresoraFormData.fromJson(nueva));
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _errorIcon = Icons.print_disabled;
      });
    } finally {
      if (!mounted) return;
      setState(() => _loadingImpresoras = false);
    }
  }

  Future<void> _eliminarImpresora(_ImpresoraFormData impresora) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar impresora'),
        content: Text(
            '¿Seguro que quieres eliminar "${impresora.nombreCtrl.text.trim()}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final api = context.read<ApiService>();
    setState(() {
      _loadingImpresoras = true;
      _error = null;
      _errorIcon = null;
    });
    try {
      await api.eliminarImpresoraConfig(impresora.id);
      if (!mounted) return;
      _impresoras.remove(impresora);
      impresora.dispose();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _errorIcon = Icons.warning_amber_rounded;
      });
    } finally {
      if (!mounted) return;
      setState(() => _loadingImpresoras = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 760,
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
                Text(
                  widget.showUrlConfig && widget.showPrinterConfig
                      ? 'Configuración del Servidor'
                      : widget.showUrlConfig
                          ? 'Configurar URL'
                          : 'Configurar Impresoras',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                if (widget.showUrlConfig) ...[
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
                  const SizedBox(height: 16),
                ],
                if (widget.showPrinterConfig) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton.icon(
                            onPressed: _loadingImpresoras ? null : _cargarImpresoras,
                            icon: _loadingImpresoras
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh),
                            label: const Text('Cargar impresoras del servidor'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _loadingImpresoras ? null : _crearImpresora,
                        icon: const Icon(Icons.add),
                        label: const Text('Añadir impresora'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_impresoras.isNotEmpty)
                    Column(
                      children: _impresoras
                          .map(
                            (imp) => _ImpresoraCard(
                              impresora: imp,
                              onDelete: _loadingImpresoras
                                  ? null
                                  : () => _eliminarImpresora(imp),
                            ),
                          )
                          .toList(),
                    )
                  else
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No hay impresoras cargadas. Pulsa "Cargar impresoras del servidor".',
                        style: TextStyle(color: AppTheme.colorTextoGris),
                      ),
                    ),
                ],
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
                    : Column(
                        children: [
                          if (!widget.navigateToLoginOnSave) ...[
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                                label: const Text('Salir sin guardar'),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _guardar,
                              child: Text(widget.navigateToLoginOnSave
                                  ? 'Guardar y Conectar'
                                  : 'Guardar'),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImpresoraFormData {
  final int id;
  final TextEditingController nombreCtrl;
  final TextEditingController ipCtrl;
  final TextEditingController puertoCtrl;
  final TextEditingController tablaCodigosCtrl;

  _ImpresoraFormData({
    required this.id,
    required this.nombreCtrl,
    required this.ipCtrl,
    required this.puertoCtrl,
    required this.tablaCodigosCtrl,
  });

  factory _ImpresoraFormData.fromJson(Map<String, dynamic> j) => _ImpresoraFormData(
        id: int.parse((j['id_impresora'] ?? 0).toString()),
        nombreCtrl: TextEditingController(text: j['nombre']?.toString() ?? ''),
        ipCtrl: TextEditingController(text: j['ip']?.toString() ?? ''),
        puertoCtrl: TextEditingController(text: (j['puerto'] ?? 9100).toString()),
        tablaCodigosCtrl:
            TextEditingController(text: j['tabla_codigos']?.toString() ?? 'CP1252'),
      );

  void dispose() {
    nombreCtrl.dispose();
    ipCtrl.dispose();
    puertoCtrl.dispose();
    tablaCodigosCtrl.dispose();
  }
}

class _ImpresoraCard extends StatelessWidget {
  final _ImpresoraFormData impresora;
  final VoidCallback? onDelete;
  const _ImpresoraCard({required this.impresora, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.colorSuperficie.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('ID ${impresora.id}',
                  style: const TextStyle(color: AppTheme.colorTextoGris)),
              const Spacer(),
              IconButton(
                tooltip: 'Eliminar impresora',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              ),
            ],
          ),
          TextField(
            controller: impresora.nombreCtrl,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: impresora.ipCtrl,
            decoration: const InputDecoration(labelText: 'IP'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: impresora.puertoCtrl,
                  decoration: const InputDecoration(labelText: 'Puerto'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: impresora.tablaCodigosCtrl,
                  decoration: const InputDecoration(labelText: 'Tabla códigos'),
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
