// lib/widgets/linea_pedido_tile.dart
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';

class LineaPedidoTile extends StatelessWidget {
  final LineaPedido linea;
  final VoidCallback? onLongPress;

  const LineaPedidoTile({super.key, required this.linea, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final esNuevo   = linea.esNuevo;
    final colorBase = esNuevo ? AppTheme.colorLineasNuevas : AppTheme.colorLineasViejas;

    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.colorTarjeta,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: colorBase, width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              // Cantidad
              Container(
                constraints: const BoxConstraints(minWidth: 36),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorBase.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${linea.cantidad}',
                    style: TextStyle(
                        color: colorBase,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  linea.nombreProducto,
                  style: TextStyle(
                      color: colorBase,
                      fontSize: 17,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Solo muestra icono si la línea se está moviendo de mesa
              if (linea.moverAMesa != null)
                Tooltip(
                  message: 'Mover a mesa ${linea.moverAMesa}',
                  child: const Icon(Icons.swap_horiz,
                      color: Colors.orange, size: 18),
                ),
              // ELIMINADO: icono more_vert
            ]),
            // Opciones elegidas
            if (linea.opcionesNoPredeterminadas.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 46, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: linea.opcionesNoPredeterminadas
                      .map((v) => Text(
                            '▸ $v',
                            style: const TextStyle(
                                color: AppTheme.colorTextoGris, fontSize: 14),
                          ))
                      .toList(),
                ),
              ),
            // Comentario
            if (linea.comentario.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 46, top: 3),
                child: Row(children: [
                  const Icon(Icons.chat_bubble_outline,
                      color: AppTheme.colorTextoGris, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(linea.comentario,
                        style: const TextStyle(
                            color: AppTheme.colorTextoGris,
                            fontSize: 14,
                            fontStyle: FontStyle.italic)),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
