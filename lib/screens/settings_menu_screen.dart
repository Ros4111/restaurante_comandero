import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/catalogo_provider.dart';
import '../services/kiosk_android.dart';
import '../services/sunmi_service.dart';
import '../utils/theme.dart';
import 'cashlogy_config_screen.dart';
import 'config_screen.dart';
import 'datafono_sim_screen.dart';
import 'dictado_screen.dart';
import 'nfc_screen.dart';
import 'producto_editor_screen.dart';
import 'reordenar_productos_screen.dart';
import 'usuarios_crud_screen.dart';

class SettingsMenuScreen extends StatelessWidget {
  const SettingsMenuScreen({super.key});

  void _openConfigUrl(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ConfigScreen(
          showUrlConfig: true,
          showPrinterConfig: false,
          navigateToLoginOnSave: false,
        ),
      ),
    );
  }

  void _openConfigPrinters(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ConfigScreen(
          showUrlConfig: false,
          showPrinterConfig: true,
          navigateToLoginOnSave: false,
        ),
      ),
    );
  }

  void _openCrudUsuarios(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const UsuariosCrudScreen(),
      ),
    );
  }

  void _openCrudProductos(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ProductoEditorScreen(),
      ),
    );
  }

  void _openReordenarProductos(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ReordenarProductosScreen(),
      ),
    );
  }

  void _openNfc(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NfcScreen()),
    );
  }

  void _openSimuladorDatfono(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DatafonoSimScreen()),
    );
  }

  void _openCashlogy(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CashlogyConfigScreen()),
    );
  }

  void _openDictado(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DictadoScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.colorTarjeta,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openConfigUrl(context),
                  icon: const Icon(Icons.link),
                  label: const Text('Configurar URL'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openConfigPrinters(context),
                  icon: const Icon(Icons.print),
                  label: const Text('Configurar impresoras'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openCrudProductos(context),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('CRUD productos'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openReordenarProductos(context),
                  icon: const Icon(Icons.sort),
                  label: const Text('Reordenar productos'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openNfc(context),
                  icon: const Icon(Icons.contactless_outlined),
                  label: const Text('Lector NFC'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openSimuladorDatfono(context),
                  icon: const Icon(Icons.credit_card),
                  label: const Text('Simulador datáfono'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openCashlogy(context),
                  icon: const Icon(Icons.toll_outlined),
                  label: const Text('Cashlogy (cobro efectivo)'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openDictado(context),
                  icon: const Icon(Icons.mic_outlined),
                  label: const Text('Dictado'),
                ),
              ),
              if (sesion.esUsuarioPrincipal) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _openCrudUsuarios(context),
                    icon: const Icon(Icons.group),
                    label: const Text('Gestión de usuarios'),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 12),
              const _PrintLogoPanel(),
              if (!kIsWeb && Platform.isAndroid) ...[
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 12),
                const _AndroidKioskPanel(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PrintLogoPanel extends StatefulWidget {
  const _PrintLogoPanel();

  @override
  State<_PrintLogoPanel> createState() => _PrintLogoPanelState();
}

class _PrintLogoPanelState extends State<_PrintLogoPanel> {
  static const _ip = '192.168.100.10';
  static const _puerto = 9100;

  bool _imprimiendo = false;
  String? _resultado;

  Future<void> _imprimir(String asset, bool raster) async {
    setState(() {
      _imprimiendo = true;
      _resultado = null;
    });
    try {
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List();
      final msg = await SunmiService.imprimirImagenLogoRed(
        imageBytes: bytes,
        usarRaster: raster,
        ip: _ip,
        puerto: _puerto,
      );
      if (mounted) setState(() => _resultado = msg);
    } catch (e) {
      if (mounted) setState(() => _resultado = 'Error: $e');
    } finally {
      if (mounted) setState(() => _imprimiendo = false);
    }
  }

  Widget _boton(String label, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onTap,
            child: Text(label),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Icon(Icons.image_outlined, color: AppTheme.colorPrimario),
          SizedBox(width: 8),
          Text(
            'Test impresión logo · $_ip:$_puerto',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ]),
        const SizedBox(height: 10),
        if (_imprimiendo)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          _boton(
              'JPG  ·  image()', () => _imprimir('assets/ticket.jpg', false)),
          _boton(
              'BMP  ·  image()', () => _imprimir('assets/ticket.bmp', false)),
        ],
        if (_resultado != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _resultado!,
              style: TextStyle(
                fontSize: 13,
                color: _resultado!.startsWith('Error') ||
                        _resultado!.startsWith('No se')
                    ? AppTheme.colorAcento
                    : Colors.green,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Kiosco: administrador de dispositivo + bloqueo de tarea (pantalla fija en esta app).
class _AndroidKioskPanel extends StatefulWidget {
  const _AndroidKioskPanel();

  @override
  State<_AndroidKioskPanel> createState() => _AndroidKioskPanelState();
}

class _AndroidKioskPanelState extends State<_AndroidKioskPanel> {
  bool _cargando = true;
  bool _admin = false;
  bool _lockPermitido = false;
  bool _enBloqueo = false;

  @override
  void initState() {
    super.initState();
    _refrescar();
  }

  Future<void> _refrescar() async {
    setState(() => _cargando = true);
    final admin = await KioskAndroid.administradorActivo();
    final permitido = await KioskAndroid.lockTaskPermitido();
    final bloqueo = await KioskAndroid.enModoBloqueo();
    if (!mounted) return;
    setState(() {
      _admin = admin;
      _lockPermitido = permitido;
      _enBloqueo = bloqueo;
      _cargando = false;
    });
  }

  Future<void> _mensaje(String texto) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.smartphone, color: AppTheme.colorPrimario),
            SizedBox(width: 8),
            Text(
              'Modo kiosco (Android)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Deja solo esta app a la vista: primero activa el administrador '
          'del dispositivo y luego «Iniciar bloqueo». En muchos móviles debes '
          'habilitar también «Fijar pantallas» / lock task en Ajustes del sistema '
          'o en opciones de desarrollador.',
          style: TextStyle(fontSize: 12, color: AppTheme.colorTextoGris),
        ),
        const SizedBox(height: 12),
        if (_cargando)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          Text(
            'Administrador: ${_admin ? "activo" : "no activo"} · '
            'Bloqueo permitido: ${_lockPermitido ? "sí" : "no"} · '
            'En bloqueo: ${_enBloqueo ? "sí" : "no"}',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (!_admin)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await KioskAndroid.solicitarAdministrador();
                  await Future<void>.delayed(const Duration(milliseconds: 500));
                  await _refrescar();
                },
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Activar administrador del dispositivo'),
              ),
            ),
          if (_admin) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await KioskAndroid.quitarAdministrador();
                  await _refrescar();
                  await _mensaje('Administrador desactivado');
                },
                icon: const Icon(Icons.remove_moderator_outlined),
                label: const Text('Quitar administrador'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _enBloqueo
                  ? null
                  : () async {
                      final ok = await KioskAndroid.iniciarBloqueoApp();
                      await _refrescar();
                      if (!mounted) return;
                      if (ok) {
                        await _mensaje('Modo bloqueo activado');
                      } else {
                        await _mensaje(
                          'No se pudo activar el bloqueo. Revisa «Fijar pantalla» / '
                          'lock task en ajustes del sistema o que el terminal permita '
                          'bloquear la app.',
                        );
                      }
                    },
              icon: const Icon(Icons.lock_outline),
              label: const Text('Iniciar bloqueo de app (kiosco)'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: !_enBloqueo
                  ? null
                  : () async {
                      await KioskAndroid.detenerBloqueoApp();
                      await _refrescar();
                      await _mensaje('Bloqueo desactivado');
                    },
              icon: const Icon(Icons.lock_open),
              label: const Text('Salir del bloqueo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.colorAcento,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _refrescar,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Actualizar estado'),
          ),
        ],
      ],
    );
  }
}
