// lib/widgets/lineas_panel.dart
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';

class LineasPanel extends StatefulWidget {
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
  State<LineasPanel> createState() => _LineasPanelState();
}

class _LineasPanelState extends State<LineasPanel> {
  late final ScrollController _scrollController;
  late int _lastLineCount;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _lastLineCount = widget.lineas.length;
  }

  @override
  void didUpdateWidget(covariant LineasPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentCount = widget.lineas.length;
    final seAnadioLinea = currentCount > _lastLineCount;
    _lastLineCount = currentCount;
    if (!seAnadioLinea) return;
    

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hayLineas = widget.lineas.isNotEmpty;

    Widget body;
    if (!hayLineas) {
      body = const Center(
        child: Text('Sin productos', style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 18)),
      );
    } else {
      body = ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        itemCount: widget.lineas.length,
        itemBuilder: (ctx, i) {
          final l = widget.lineas[i];
          return _LineaTile(
            linea: l,
            soloLectura: widget.soloLectura,
            onLongPress: () => widget.onLineaTap(l),
            backgroundColor: i.isEven ? AppTheme.colorTarjeta : AppTheme.colorSuperficie,
          );
        },
      );
    }

//no se muestra el título "Pedido" si no hay líneas, para no ocupar espacio innecesario
    return Column(
      children: [
        Container(
          color: AppTheme.colorSuperficie,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          alignment: Alignment.centerLeft,
          child: const Text(
            'Pedido',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _LineaTile extends StatelessWidget {
  final LineaPedido linea;
  final bool soloLectura;
  final VoidCallback onLongPress;
  final Color backgroundColor;

  const _LineaTile({
    required this.linea,
    required this.soloLectura,
    required this.onLongPress,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final esNuevo = linea.esNuevo;
    final color = linea.editada
        ? Colors.green
        : (esNuevo ? AppTheme.colorLineasNuevas : AppTheme.colorLineasViejas);

    return GestureDetector(
      onLongPress: soloLectura ? null : onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: const Border(bottom: BorderSide(color: Colors.black26, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    linea.nombreProducto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (linea.cantidad > 1) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${linea.cantidad}x',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ],
            ),
            if (linea.opcionesNoPredeterminadas.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...linea.opcionesNoPredeterminadas.map(
                (op) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text('▸ $op', style: const TextStyle(color: AppTheme.colorTextoGris, fontSize: 13)),
                ),
              ),
            ],
            if (linea.comentario.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '📝 ${linea.comentario}',
                  style: const TextStyle(
                    color: AppTheme.colorTextoGris,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            if (linea.moverAMesa != null) ...[
              const SizedBox(height: 4),
              Text(
                '→ Mover a mesa ${linea.moverAMesa}',
                style: const TextStyle(color: Colors.orange, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
