// lib/widgets/producto_opciones_dialog.dart
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';

class ProductoOpcionesDialog extends StatefulWidget {
  final Producto producto;
  final List<GrupoOpciones> grupos;
  final CatalogoProvider catalogo;
  final int? cantidadInicial;
  final String? comentarioInicial;
  final Map<int, OpcionElegida>? opcionesIniciales;
  final bool modoEdicion;

  const ProductoOpcionesDialog({
    super.key,
    required this.producto,
    required this.grupos,
    required this.catalogo,
    this.cantidadInicial,
    this.comentarioInicial,
    this.opcionesIniciales,
    this.modoEdicion = false,
  });

  @override
  State<ProductoOpcionesDialog> createState() => _ProductoOpcionesDialogState();
}

class _ProductoOpcionesDialogState extends State<ProductoOpcionesDialog> {
  final Map<int, OpcionElegida> _seleccion = {};
  late int _cantidad;
  late final TextEditingController _comentCtrl;

  @override
  void initState() {
    super.initState();
    _cantidad = widget.cantidadInicial ?? 1;
    _comentCtrl = TextEditingController(text: widget.comentarioInicial ?? '');

    if (widget.opcionesIniciales != null) {
      _seleccion.addAll(widget.opcionesIniciales!);
    }

    // Completar con valores predeterminados en grupos sin selección inicial
    for (final g in widget.grupos) {
      if (_seleccion.containsKey(g.id)) continue;
      final opts = widget.catalogo.opcionesDeGrupo(widget.producto.id, g.id);
      final def  = opts.where((o) => o.predeterminado).firstOrNull ?? opts.firstOrNull;
      if (def != null) {
        _seleccion[g.id] = OpcionElegida(
          nombre: def.nombre,
          predeterminado: def.predeterminado,
        );
      }
    }
  }

  @override
  void dispose() {
    _comentCtrl.dispose();
    super.dispose();
  }

  bool get _valido => widget.grupos.every((g) => _seleccion.containsKey(g.id));

  void _confirmar() {
    Navigator.pop(context, {
      'accion': widget.modoEdicion ? 'guardar' : 'anadir',
      'cantidad':   _cantidad,
      'comentario': _comentCtrl.text.trim(),
      'opciones':   Map<int, OpcionElegida>.from(_seleccion),
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
              Row(
                children: [
                  const Text('Cantidad',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 32),
                    onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
                  ),
                  Text('$_cantidad',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
                    RadioGroup<String>(
                      groupValue: _seleccion[g.id]?.nombre,
                      onChanged: (v) {
                        if (v != null) {
                          final opcion = opts.firstWhere((o) => o.nombre == v);
                          setState(() {
                            _seleccion[g.id] = OpcionElegida(
                              nombre: opcion.nombre,
                              predeterminado: opcion.predeterminado,
                            );
                          });
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: opts.map((o) => RadioListTile<String>(
                              value: o.nombre,
                              title: Text(o.nombre, style: const TextStyle(fontSize: 16)),
                              activeColor: AppTheme.colorPrimario,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            )).toList(),
                      ),
                    ),
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
        SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (widget.modoEdicion)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.colorAcento,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => Navigator.pop(context, {'accion': 'eliminar'}),
                  child: const Icon(Icons.delete_outline, size: 26),
                ),
              Expanded(
                child: Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: _valido ? _confirmar : null,
                child: Icon(widget.modoEdicion ? Icons.save_outlined : Icons.add, size: 30),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
