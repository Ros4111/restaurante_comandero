// lib/widgets/lineas_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';

/// Misma regla que [ProductoOpcionesDialog]: predeterminada del catálogo o, si no hay, la primera opción del grupo.
List<String> _opcionesAMostrarEnPanel(
    LineaPedido linea, CatalogoProvider catalogo) {
  final out = <String>[];
  for (final entry in linea.opcionesElegidas.entries) {
    final idGrupo = entry.key;
    final elegida = entry.value;
    final opts = catalogo.opcionesDeGrupo(linea.idProducto, idGrupo);
    if (opts.isEmpty) {
      if (!elegida.predeterminado) out.add(elegida.nombre);
      continue;
    }
    OpcionProducto? predCatalogo;
    for (final o in opts) {
      if (o.predeterminado) {
        predCatalogo = o;
        break;
      }
    }
    predCatalogo ??= opts.first;
    if (predCatalogo.nombreOpcion != elegida.nombre) {
      out.add(elegida.nombre);
    }
  }
  return out;
}

class LineasPanel extends StatefulWidget {
  final List<LineaPedido> lineas;
  final bool soloLectura;
  final void Function(LineaPedido) onLineaTap;
  final void Function(LineaPedido) onLineaIncrement;
  final void Function(LineaPedido) onLineaDecrement;

  const LineasPanel({
    super.key,
    required this.lineas,
    required this.soloLectura,
    required this.onLineaTap,
    required this.onLineaIncrement,
    required this.onLineaDecrement,
  });

  @override
  State<LineasPanel> createState() => _LineasPanelState();
}

class _LineasPanelState extends State<LineasPanel> {
  late final ScrollController _scrollController;
  late int _lastLineCount;
  int? _indiceSeleccionado;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _lastLineCount = widget.lineas.length;
  }

  void _seleccionar(int index) {
    if (widget.soloLectura) return;
    setState(() => _indiceSeleccionado = index);
  }

  void _deseleccionarSiLineaEliminada() {
    final i = _indiceSeleccionado;
    if (i == null) return;
    if (i >= widget.lineas.length) {
      _indiceSeleccionado = null;
      return;
    }
  }

  @override
  void didUpdateWidget(covariant LineasPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _deseleccionarSiLineaEliminada();
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
    final catalogo = context.watch<CatalogoProvider>();
    // Solo si el catálogo puede cambiar durante el pedido
    final hayLineas = widget.lineas.isNotEmpty;

    Widget body;
    if (!hayLineas) {
      body = const Center(
        child: Text('Sin productos',
            style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 18)),
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
            catalogo: catalogo,
            soloLectura: widget.soloLectura,
            seleccionada: _indiceSeleccionado == i,
            onTap: () => _seleccionar(i),
            onLongPress: () => widget.onLineaTap(l),
            onIncrement: () => widget.onLineaIncrement(l),
            onDecrement: () {
              widget.onLineaDecrement(l);
              if (l.esNuevo && l.cantidad <= 1) {
                setState(() => _indiceSeleccionado = null);
              }
            },
            backgroundColor:
                i.isEven ? AppTheme.colorTarjeta : AppTheme.colorSuperficie,
          );
        },
      );
    }

    return body;
  }
}

class _LineaTile extends StatelessWidget {
  final LineaPedido linea;
  final CatalogoProvider catalogo;
  final bool soloLectura;
  final bool seleccionada;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final Color backgroundColor;

  const _LineaTile({
    required this.linea,
    required this.catalogo,
    required this.soloLectura,
    required this.seleccionada,
    required this.onTap,
    required this.onLongPress,
    required this.onIncrement,
    required this.onDecrement,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final opcionesPanel = _opcionesAMostrarEnPanel(linea, catalogo);
    final esNuevo = linea.esNuevo;
    final esNota = linea.esNotaLibre;
    final color = linea.editada
        ? Colors.green
        : (esNuevo ? AppTheme.colorLineasNuevas : AppTheme.colorLineasViejas);
    final notaColor = esNota ? Colors.amber[300]! : color;

    final mostrarControles = seleccionada && !soloLectura;
    final cantidadEnControles = mostrarControles && esNuevo;
    final mostrarCantidad =
        linea.cantidad > 1 && !cantidadEnControles;

    return GestureDetector(
      onTap: soloLectura ? null : onTap,
      onLongPress: soloLectura ? null : onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(
            bottom: const BorderSide(color: Colors.black26, width: 1),
            left: seleccionada
                ? BorderSide(color: AppTheme.colorPrimario, width: 3)
                : BorderSide.none,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (esNota) ...[
                  Icon(Icons.edit_note, size: 15, color: Colors.amber[300]),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    linea.nombreProducto,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: notaColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontStyle: esNota ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
                if (mostrarCantidad) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${linea.cantidad}x',
                    style: TextStyle(
                        color: notaColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ],
                if (mostrarControles && esNuevo) ...[
                  _CantidadBoton(
                    icon: Icons.remove,
                    onPressed: onDecrement,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '${linea.cantidad}',
                      style: TextStyle(
                        color: notaColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  _CantidadBoton(
                    icon: Icons.add,
                    onPressed: onIncrement,
                  ),
                ] else if (mostrarControles && !esNuevo) ...[
                  _CantidadBoton(
                    icon: Icons.add,
                    onPressed: onIncrement,
                  ),
                ],
                // Mostrar precio para notas libres con precio
                if (esNota && linea.pvpAlmacenado > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${linea.pvpAlmacenado.toStringAsFixed(2)} €',
                    style: TextStyle(
                      color: Colors.amber[200],
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            if (opcionesPanel.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...opcionesPanel.map(
                (op) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text('▸ $op',
                      style: const TextStyle(
                          color: AppTheme.colorTextoGris, fontSize: 13)),
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

class _CantidadBoton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CantidadBoton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.colorPrimario.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: AppTheme.colorPrimario),
        ),
      ),
    );
  }
}
