// lib/widgets/lineas_panel.dart
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';

class LineasPanel extends StatelessWidget {
  final List<LineaPedido> lineas;
  final bool soloLectura;
  final void Function(LineaPedido) onLineaTap;

  const LineasPanel({
    super.key,
    required this.lineas,
    required this.soloLectura,
    required this.onLineaTap,
  });

  @override
  Widget build(BuildContext context) {
    if (lineas.isEmpty) {
      return const Center(
        child: Text('Sin productos', style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 18)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: lineas.length,
      itemBuilder: (ctx, i) {
        final l = lineas[i];
        return _LineaTile(linea: l, soloLectura: soloLectura, onLongPress: () => onLineaTap(l));
      },
    );
  }
}

class _LineaTile extends StatelessWidget {
  final LineaPedido linea;
  final bool soloLectura;
  final VoidCallback onLongPress;

  const _LineaTile({required this.linea, required this.soloLectura, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final esNuevo = linea.esNuevo;
    final color   = esNuevo ? AppTheme.colorLineasNuevas : AppTheme.colorLineasViejas;
    final bg      = esNuevo
        ? AppTheme.colorAcento.withValues(alpha:0.08)
        : AppTheme.colorTarjeta;

    return GestureDetector(
      onLongPress: soloLectura ? null : onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha:0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha:0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${linea.cantidad}x',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(linea.nombreProducto,
                      style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                if (!soloLectura)
                  Icon(Icons.touch_app, color: color.withValues(alpha:0.4), size: 16),
              ],
            ),
            if (linea.opcionesElegidas.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...linea.opcionesElegidas.values.map((op) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text('▸ $op',
                        style: const TextStyle(color: AppTheme.colorTextoGris, fontSize: 13)),
                  )),
            ],
            if (linea.comentario.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('📝 ${linea.comentario}',
                    style: const TextStyle(color: AppTheme.colorTextoGris, fontSize: 13,
                        fontStyle: FontStyle.italic)),
              ),
            ],
            if (linea.moverAMesa != null) ...[
              const SizedBox(height: 4),
              Text('→ Mover a mesa ${linea.moverAMesa}',
                  style: const TextStyle(color: Colors.orange, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}
