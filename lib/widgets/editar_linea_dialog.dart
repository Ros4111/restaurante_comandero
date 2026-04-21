// lib/widgets/editar_linea_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';

class EditarLineaDialog extends StatefulWidget {
  final LineaPedido linea;
  final int idMesa;

  const EditarLineaDialog({super.key, required this.linea, required this.idMesa});

  @override
  State<EditarLineaDialog> createState() => _EditarLineaDialogState();
}

class _EditarLineaDialogState extends State<EditarLineaDialog> {
  late int _cantidad;
  late TextEditingController _comentCtrl;
  final _mesaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cantidad   = widget.linea.cantidad;
    _comentCtrl = TextEditingController(text: widget.linea.comentario);
  }

  @override
  void dispose() {
    _comentCtrl.dispose();
    _mesaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esNuevo  = widget.linea.esNuevo;
    final sesion   = context.read<SesionProvider>();
    final puedeElim  = esNuevo || sesion.esSupervisor;
    final puedeMover = esNuevo || sesion.esSupervisor;

    return AlertDialog(
      backgroundColor: AppTheme.colorTarjeta,
      title: Text(widget.linea.nombreProducto,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cantidad (solo si es nuevo)
              if (esNuevo) ...[
                const Text('Cantidad', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 28),
                    onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
                  ),
                  Text('$_cantidad', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 28),
                    onPressed: () => setState(() => _cantidad++),
                  ),
                ]),
                const SizedBox(height: 12),
                const Text('Comentario', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _comentCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppTheme.colorSuperficie,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ] else
                const Text('Producto ya enviado — opciones limitadas',
                    style: TextStyle(color: AppTheme.colorTextoGris)),

              // Mover mesa
              if (puedeMover) ...[
                const Divider(),
                const Text('Mover a mesa nº:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _mesaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Nº mesa destino',
                        filled: true,
                        fillColor: AppTheme.colorSuperficie,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    onPressed: () {
                      final num = int.tryParse(_mesaCtrl.text);
                      if (num != null && num > 0 && num != widget.idMesa) {
                        Navigator.pop(context, {'accion': 'mover', 'mesa_destino': num});
                      }
                    },
                    child: const Text('Mover'),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (puedeElim)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.colorAcento),
            onPressed: () => Navigator.pop(context, {'accion': 'eliminar'}),
            child: const Text('Eliminar'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        if (esNuevo)
          ElevatedButton(
            onPressed: () => Navigator.pop(context, {
              'accion':     'guardar',
              'cantidad':   _cantidad,
              'comentario': _comentCtrl.text.trim(),
            }),
            child: const Text('Guardar'),
          ),
      ],
    );
  }
}
