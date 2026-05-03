import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/catalogo_provider.dart';
import '../utils/theme.dart';
import 'config_screen.dart';
import 'producto_editor_screen.dart';
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
              if (sesion.esAdmin) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _openCrudUsuarios(context),
                    icon: const Icon(Icons.group),
                    label: const Text('CRUD usuarios'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
