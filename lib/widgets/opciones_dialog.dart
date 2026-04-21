// lib/widgets/opciones_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';

class OpcionesDialog extends StatefulWidget {
  final Producto producto;
  final Map<int, String> gruposInicialesOpciones; // idGrupo -> nombre opcion seleccionada

  const OpcionesDialog({
    super.key,
    required this.producto,
    required this.gruposInicialesOpciones,
  });

  @override
  State<OpcionesDialog> createState() => _OpcionesDialogState();
}

class _OpcionesDialogState extends State<OpcionesDialog> {
  late Map<int, String> _opcionesElegidas;
  int _cantidad = 1;
  final _comentarioCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _opcionesElegidas = Map.from(widget.gruposInicialesOpciones);
  }

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  bool get _valido {
    final catalogo = context.read<CatalogoProvider>();
    final grupos = catalogo.gruposDeProducto(widget.producto.id);
    // Todos los grupos deben tener una opción seleccionada
    return grupos.every((g) => _opcionesElegidas.containsKey(g.id));
  }

  void _seleccionarOpcion(int idGrupo, String nombreOpcion) {
    setState(() => _opcionesElegidas[idGrupo] = nombreOpcion);
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = context.read<CatalogoProvider>();
    final grupos   = catalogo.gruposDeProducto(widget.producto.id);

    return Dialog(
      backgroundColor: AppTheme.colorTarjeta,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Título
            Text(widget.producto.nombre,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center),
            const Divider(height: 24, color: Colors.white24),

            // Grupos de opciones
            if (grupos.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: grupos.map((grupo) {
                      final opts = catalogo.opcionesDeGrupo(widget.producto.id, grupo.id);
                      final elegida = _opcionesElegidas[grupo.id];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(grupo.nombre,
                                style: const TextStyle(
                                    color: AppTheme.colorTextoGris,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: opts.map((op) {
                                final sel = elegida == op.nombre;
                                return GestureDetector(
                                  onTap: () => _seleccionarOpcion(grupo.id, op.nombre),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? AppTheme.colorPrimario
                                          : AppTheme.colorSuperficie,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: sel
                                            ? AppTheme.colorPrimario
                                            : Colors.white24,
                                      ),
                                    ),
                                    child: Text(op.nombre,
                                        style: TextStyle(
                                          color: sel ? Colors.white : AppTheme.colorTexto,
                                          fontSize: 16,
                                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                                        )),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            // Cantidad
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Cantidad:', style: TextStyle(fontSize: 17, color: Colors.white)),
                const SizedBox(width: 16),
                _BotonCantidad(
                  icono: Icons.remove,
                  onTap: () { if (_cantidad > 1) setState(() => _cantidad--); },
                ),
                const SizedBox(width: 12),
                Text('$_cantidad',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(width: 12),
                _BotonCantidad(
                  icono: Icons.add,
                  onTap: () => setState(() => _cantidad++),
                ),
              ],
            ),

            // Comentario
            const SizedBox(height: 16),
            TextField(
              controller: _comentarioCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Comentario (opcional)',
                labelStyle: const TextStyle(color: AppTheme.colorTextoGris),
                filled: true,
                fillColor: AppTheme.colorSuperficie,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
              ),
            ),

            const SizedBox(height: 24),
            // Botones
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Cancelar', style: TextStyle(fontSize: 17)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _valido ? () {
                    Navigator.pop(context, {
                      'opciones':   _opcionesElegidas,
                      'cantidad':   _cantidad,
                      'comentario': _comentarioCtrl.text.trim(),
                    });
                  } : null,
                  child: const Text('Añadir', style: TextStyle(fontSize: 17)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _BotonCantidad extends StatelessWidget {
  final IconData icono;
  final VoidCallback onTap;
  const _BotonCantidad({required this.icono, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.colorSuperficie,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        padding: const EdgeInsets.all(8),
        child: Icon(icono, color: Colors.white, size: 22),
      ),
    );
  }
}
