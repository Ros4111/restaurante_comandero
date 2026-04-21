// lib/widgets/producto_opciones_dialog.dart
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';

class ProductoOpcionesDialog extends StatefulWidget {
  final Producto producto;
  final List<GrupoOpciones> grupos;
  final CatalogoProvider catalogo;

  const ProductoOpcionesDialog({
    super.key,
    required this.producto,
    required this.grupos,
    required this.catalogo,
  });

  @override
  State<ProductoOpcionesDialog> createState() => _ProductoOpcionesDialogState();
}

class _ProductoOpcionesDialogState extends State<ProductoOpcionesDialog> {
  final Map<int, String> _seleccion = {};
  int _cantidad = 1;
  final _comentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Cargar valores predeterminados
    for (final g in widget.grupos) {
      final opts = widget.catalogo.opcionesDeGrupo(widget.producto.id, g.id);
      final def  = opts.where((o) => o.predeterminado).firstOrNull ?? opts.firstOrNull;
      if (def != null) _seleccion[g.id] = def.nombre;
    }
  }

  bool get _valido => widget.grupos.every((g) => _seleccion.containsKey(g.id));

  void _confirmar() {
    Navigator.pop(context, {
      'cantidad':   _cantidad,
      'comentario': _comentCtrl.text.trim(),
      'opciones':   Map<int, String>.from(_seleccion),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.colorTarjeta,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      title: Text(widget.producto.nombre,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cantidad
              const SizedBox(height: 12),
              const Text('Cantidad', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 32),
                    onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
                  ),
                  Text('$_cantidad', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 32),
                    onPressed: () => setState(() => _cantidad++),
                  ),
                ],
              ),

              // Grupos de opciones
              ...widget.grupos.map((g) {
                final opts = widget.catalogo.opcionesDeGrupo(widget.producto.id, g.id);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    Text(g.nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    ...opts.map((o) => RadioListTile<String>(
                          value: o.nombre,
                          groupValue: _seleccion[g.id],
                          title: Text(o.nombre, style: const TextStyle(fontSize: 16)),
                          // No permitir deseleccionar (siempre obligatorio)
                          onChanged: (v) {
                            if (v != null) setState(() => _seleccion[g.id] = v);
                          },
                          activeColor: AppTheme.colorPrimario,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        )),
                  ],
                );
              }),

              // Comentario
              const Divider(),
              const Text('Comentario (opcional)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 6),
              TextField(
                controller: _comentCtrl,
                style: const TextStyle(fontSize: 16),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Sin cebolla, sin gluten...',
                  filled: true,
                  fillColor: AppTheme.colorSuperficie,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
            onPressed: _valido ? _confirmar : null,
            child: const Text('Añadir')),
      ],
    );
  }
}
