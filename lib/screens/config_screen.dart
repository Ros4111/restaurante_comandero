// lib/screens/config_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
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

  // Bluetooth printer state
  String _btMac = '';
  String _btName = '';
  final _btTablaCtrl = TextEditingController(text: 'CP1252');
  String _btPapel = 'mm58';
  bool _btEscaneando = false;

  @override
  void initState() {
    super.initState();
    _initConfig();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _btTablaCtrl.dispose();
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
      _btMac = prefs.getString('bt_printer_mac') ?? '';
      _btName = prefs.getString('bt_printer_name') ?? '';
      _btTablaCtrl.text =
          prefs.getString('bt_printer_tabla_codigos') ?? 'CP1252';
      _btPapel = prefs.getString('bt_printer_papel') ?? 'mm58';
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
      if (mounted) {
        setState(() {
          _error =
              'No se pudo cargar la configuración de impresoras. Revisa la URL.';
          _errorIcon = Icons.print_disabled;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingImpresoras = false);
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
            _error =
                'El puerto de "${imp.nombreCtrl.text.trim()}" no es válido.';
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

    // Guardar config BT localmente (no depende del servidor)
    if (widget.showPrinterConfig) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bt_printer_mac', _btMac);
      await prefs.setString('bt_printer_name', _btName);
      await prefs.setString(
          'bt_printer_tabla_codigos', _btTablaCtrl.text.trim().toUpperCase());
      await prefs.setString('bt_printer_papel', _btPapel);
    }

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
                      'tabla_codigos':
                          e.tablaCodigosCtrl.text.trim().toUpperCase(),
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
      if (mounted) {
        setState(() {
          _error = e.toString();
          _errorIcon = Icons.print_disabled;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingImpresoras = false);
    }
  }

  Future<void> _eliminarImpresora(_ImpresoraFormData impresora) async {
    final api = context.read<ApiService>();
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
      if (mounted) {
        setState(() {
          _error = e.toString();
          _errorIcon = Icons.warning_amber_rounded;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingImpresoras = false);
    }
  }

  Future<void> _escanearBluetooth() async {
    setState(() => _btEscaneando = true);
    try {
      final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!granted) {
        if (mounted) {
          setState(() {
            _error =
                'Permiso Bluetooth no concedido. Actívalo en Ajustes > Aplicaciones.';
            _errorIcon = Icons.bluetooth_disabled;
          });
        }
        return;
      }
      final btOn = await PrintBluetoothThermal.bluetoothEnabled;
      if (!btOn) {
        if (mounted) {
          setState(() {
            _error =
                'El Bluetooth está desactivado. Actívalo e inténtalo de nuevo.';
            _errorIcon = Icons.bluetooth_disabled;
          });
        }
        return;
      }
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      if (!mounted) return;
      if (devices.isEmpty) {
        setState(() {
          _error =
              'No hay dispositivos Bluetooth emparejados. Empareja la impresora en los ajustes del sistema.';
          _errorIcon = Icons.bluetooth_searching;
        });
        return;
      }
      final seleccionado = await showDialog<BluetoothInfo>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Seleccionar impresora Bluetooth'),
          children: devices
              .map(
                (d) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, d),
                  child: ListTile(
                    leading: const Icon(Icons.print),
                    title: Text(d.name),
                    subtitle: Text(d.macAdress),
                    dense: true,
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (seleccionado != null && mounted) {
        setState(() {
          _btMac = seleccionado.macAdress;
          _btName = seleccionado.name;
          _error = null;
          _errorIcon = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error al escanear Bluetooth: $e';
          _errorIcon = Icons.bluetooth_disabled;
        });
      }
    } finally {
      if (mounted) setState(() => _btEscaneando = false);
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
                const Icon(Icons.settings,
                    color: AppTheme.colorPrimario, size: 56),
                const SizedBox(height: 16),
                Text(
                  widget.showUrlConfig && widget.showPrinterConfig
                      ? 'Configuración del Servidor'
                      : widget.showUrlConfig
                          ? 'Configurar URL'
                          : 'Configurar Impresoras',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
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
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
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
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  _BluetoothPrinterCard(
                    mac: _btMac,
                    name: _btName,
                    tablaCtrl: _btTablaCtrl,
                    papel: _btPapel,
                    escaneando: _btEscaneando,
                    onScanPressed: _escanearBluetooth,
                    onClear: () => setState(() {
                      _btMac = '';
                      _btName = '';
                    }),
                    onPapelChanged: (v) => setState(() => _btPapel = v),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[900]!.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.colorAcento.withValues(alpha: 0.6)),
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

  factory _ImpresoraFormData.fromJson(Map<String, dynamic> j) =>
      _ImpresoraFormData(
        id: int.parse((j['id_impresora'] ?? 0).toString()),
        nombreCtrl: TextEditingController(text: j['nombre']?.toString() ?? ''),
        ipCtrl: TextEditingController(text: j['ip']?.toString() ?? ''),
        puertoCtrl:
            TextEditingController(text: (j['puerto'] ?? 9100).toString()),
        tablaCodigosCtrl: TextEditingController(
            text: j['tabla_codigos']?.toString() ?? 'CP1252'),
      );

  void dispose() {
    nombreCtrl.dispose();
    ipCtrl.dispose();
    puertoCtrl.dispose();
    tablaCodigosCtrl.dispose();
  }
}

class _BluetoothPrinterCard extends StatelessWidget {
  final String mac;
  final String name;
  final TextEditingController tablaCtrl;
  final String papel;
  final bool escaneando;
  final VoidCallback onScanPressed;
  final VoidCallback onClear;
  final ValueChanged<String> onPapelChanged;

  const _BluetoothPrinterCard({
    required this.mac,
    required this.name,
    required this.tablaCtrl,
    required this.papel,
    required this.escaneando,
    required this.onScanPressed,
    required this.onClear,
    required this.onPapelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final conectada = mac.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.colorSuperficie.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: conectada
              ? Colors.blueAccent.withValues(alpha: 0.6)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bluetooth,
                  color:
                      conectada ? Colors.blueAccent : AppTheme.colorTextoGris,
                  size: 20),
              const SizedBox(width: 8),
              const Text('Impresora Bluetooth',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (conectada)
                IconButton(
                  tooltip: 'Quitar impresora Bluetooth',
                  onPressed: onClear,
                  icon: const Icon(Icons.clear,
                      color: Colors.redAccent, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (conectada) ...[
            Text(name,
                style:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            Text(mac,
                style: const TextStyle(
                    color: AppTheme.colorTextoGris, fontSize: 12)),
            const SizedBox(height: 12),
          ] else
            const Text('Sin dispositivo seleccionado.',
                style: TextStyle(color: AppTheme.colorTextoGris)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: escaneando ? null : onScanPressed,
            icon: escaneando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bluetooth_searching),
            label: Text(
                conectada ? 'Cambiar dispositivo' : 'Seleccionar dispositivo'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: tablaCtrl,
                  decoration: const InputDecoration(labelText: 'Tabla códigos'),
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: papel,
                  decoration: const InputDecoration(labelText: 'Ancho papel'),
                  items: const [
                    DropdownMenuItem(value: 'mm58', child: Text('58 mm')),
                    DropdownMenuItem(value: 'mm80', child: Text('80 mm')),
                  ],
                  onChanged: (v) {
                    if (v != null) onPapelChanged(v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
