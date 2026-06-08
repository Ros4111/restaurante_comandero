// lib/widgets/producto_opciones_dialog.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/catalogo_provider.dart';
import '../utils/precio_redondeo.dart';
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
  late final FocusNode _comentFocus;

  void _syncTeclado() {
    // Windows: evita asserts de HardwareKeyboard (p. ej. Alt ya “pulsada”) al
    // abrir el diálogo o al enfocar el TextField tras Alt-Tab / menú sistema.
    unawaited(HardwareKeyboard.instance.syncKeyboardState());
  }

  @override
  void initState() {
    super.initState();
    _cantidad = widget.cantidadInicial ?? 1;
    _comentCtrl = TextEditingController(text: widget.comentarioInicial ?? '');
    _comentFocus = FocusNode();
    _comentFocus.addListener(() {
      if (_comentFocus.hasFocus) _syncTeclado();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTeclado());

    if (widget.opcionesIniciales != null) {
      _seleccion.addAll(widget.opcionesIniciales!);
    }

    // Completar con valores predeterminados en grupos sin selección inicial
    for (final g in widget.grupos) {
      if (_seleccion.containsKey(g.id)) continue;
      final opts = widget.catalogo.opcionesDeGrupo(widget.producto.id, g.id);
      final def =
          opts.where((o) => o.predeterminado).firstOrNull ?? opts.firstOrNull;
      if (def != null) {
        _seleccion[g.id] = OpcionElegida(
          nombre: def.nombreOpcion,
          predeterminado: def.predeterminado,
        );
      }
    }
  }

  @override
  void dispose() {
    _comentFocus.dispose();
    _comentCtrl.dispose();
    super.dispose();
  }

  bool get _valido => widget.grupos.every((g) => _seleccion.containsKey(g.id));

  /// PVP unitario (IVA incl.) a céntimos, coherente con totales del pedido.
  double get _precioUnitario {
    final supl = <double>[];
    for (final entry in _seleccion.entries) {
      final opcion = entry.value;
      if (opcion.predeterminado) continue;
      final opts =
          widget.catalogo.opcionesDeGrupo(widget.producto.id, entry.key);
      final match =
          opts.where((o) => o.nombreOpcion == opcion.nombre).firstOrNull;
      if (match != null) supl.add(match.suplementoSinIva);
    }
    final baseUnit = baseImponibleUnitariaProductoLinea(
      baseImponibleProducto: widget.producto.baseImponible,
      suplementosSinIvaNoPredeterminados: supl,
    );
    return pvpUnitarioDesdeBaseSinIva(
      baseSinIvaUnitaria: baseUnit,
      porcentajeIva: widget.producto.porcentajeIVA,
    );
  }

  double get _precioTotal =>
      importeTtcLinea(pvpUnitario: _precioUnitario, cantidad: _cantidad);

  void _confirmar() {
    Navigator.pop(context, {
      'accion': widget.modoEdicion ? 'guardar' : 'anadir',
      'cantidad': _cantidad,
      'comentario': _comentCtrl.text.trim(),
      'opciones': Map<int, OpcionElegida>.from(_seleccion),
    });
  }

  @override
  Widget build(BuildContext context) {
    final widthPantalla = MediaQuery.of(context).size.width - 20;
    return Dialog.fullscreen(
      backgroundColor: AppTheme.colorTarjeta,
      child: SizedBox(
        width: widthPantalla,
        child: SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.only(left: 8, right: 6, top: 6, bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.producto.nombreProductoPantalla,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.producto.baseImponible > 0) ...[
                      const SizedBox(width: 8),
                      _PrecioBadge(
                        unitario: _precioUnitario,
                        total: _precioTotal,
                        cantidad: _cantidad,
                      ),
                    ],
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _valido ? _confirmar : null,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: EdgeInsets.zero,
                      ),
                      child: Icon(
                        widget.modoEdicion ? Icons.save : Icons.add,
                        size: 30,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Text('Cantidad',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 32),
                            onPressed: _cantidad > 1
                                ? () => setState(() => _cantidad--)
                                : null,
                          ),
                          Text('$_cantidad',
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon:
                                const Icon(Icons.add_circle_outline, size: 32),
                            onPressed: () => setState(() => _cantidad++),
                          ),
                        ]),

                        // Grupos de opciones
                        ...widget.grupos.map((g) {
                          final opts = widget.catalogo
                              .opcionesDeGrupo(widget.producto.id, g.id);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(height: 8),
                              Text(g.nombre,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              Theme(
                                data: Theme.of(context).copyWith(
                                  listTileTheme: const ListTileThemeData(
                                    horizontalTitleGap: 2,
                                    minLeadingWidth: 0,
                                    minVerticalPadding: 0,
                                    dense: true,
                                  ),
                                ),
                                child: RadioGroup<String>(
                                  groupValue: _seleccion[g.id]?.nombre,
                                  onChanged: (v) {
                                    if (v != null) {
                                      final opcion = opts.firstWhere(
                                          (o) => o.nombreOpcion == v);
                                      setState(() {
                                        _seleccion[g.id] = OpcionElegida(
                                          nombre: opcion.nombreOpcion,
                                          predeterminado: opcion.predeterminado,
                                        );
                                      });
                                    }
                                  },
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: opts
                                        .map((o) => RadioListTile<String>(
                                              value: o.nombreOpcion,
                                              title: Text(o.nombreOpcion,
                                                  style: const TextStyle(
                                                      fontSize: 16)),
                                              activeColor:
                                                  AppTheme.colorPrimario,
                                              dense: true,
                                              visualDensity:
                                                  const VisualDensity(
                                                horizontal: -4,
                                                vertical: -4,
                                              ),
                                              contentPadding: EdgeInsets.zero,
                                              radioScaleFactor: 1.0,
                                              radioInnerRadius:
                                                  WidgetStateProperty
                                                      .resolveWith<double>(
                                                          (states) {
                                                if (states.contains(
                                                    WidgetState.selected)) {
                                                  return 3.0;
                                                }
                                                return 0.0;
                                              }),
                                            ))
                                        .toList(),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),

                        // Comentario
                        const Divider(height: 8),
                        const Text('Comentario (opcional)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 4),
                        TextField(
                          focusNode: _comentFocus,
                          controller: _comentCtrl,
                          style: const TextStyle(fontSize: 16),
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'Sin cebolla, sin gluten...',
                            filled: true,
                            fillColor: AppTheme.colorSuperficie,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
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
                        onPressed: () =>
                            Navigator.pop(context, {'accion': 'eliminar'}),
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
                    if (widget.modoEdicion)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[800],
                          foregroundColor: Colors.white,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () async {
                          final mesaStr = await showDialog<String>(
                            context: context,
                            builder: (_) => const SeleccionarMesaDialog(),
                          );
                          if (mesaStr == null || mesaStr.isEmpty) return;
                          final numMesa = int.tryParse(mesaStr);
                          if (numMesa == null || numMesa <= 0) return;
                          if (!context.mounted) return;
                          Navigator.pop(context, {
                            'accion': 'mover',
                            'mesa_destino': numMesa,
                          });
                        },
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swap_horiz, size: 22),
                            SizedBox(width: 4),
                            Text('Mover'),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Diálogo selector de número de mesa ─────────────────────────

class SeleccionarMesaDialog extends StatefulWidget {
  const SeleccionarMesaDialog({super.key});

  @override
  State<SeleccionarMesaDialog> createState() => _SeleccionarMesaDialogState();
}

class _SeleccionarMesaDialogState extends State<SeleccionarMesaDialog> {
  String _numero = '';

  void _tecla(String v) {
    if (_numero.length >= 4) return;
    setState(() => _numero += v);
  }

  void _borrar() {
    if (_numero.isEmpty) return;
    setState(() => _numero = _numero.substring(0, _numero.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = (screenWidth - 20).clamp(0.0, 400.0);
    final horizontalInset =
        ((screenWidth - dialogWidth) / 2).clamp(0.0, double.infinity);
    return AlertDialog(
      backgroundColor: AppTheme.colorTarjeta,
      contentPadding: const EdgeInsets.all(6),
      insetPadding:
          EdgeInsets.symmetric(horizontal: horizontalInset, vertical: 24),
      title: const Text('Mover a mesa número'),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.colorSuperficie,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                _numero.isEmpty ? 'Número de mesa destino' : _numero,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  letterSpacing: _numero.isEmpty ? 0 : 3,
                  color: _numero.isEmpty
                      ? AppTheme.colorTextoGris
                      : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 240,
              child: _TecladoNumMesa(
                onTecla: _tecla,
                onBorrar: _borrar,
                onOk: _numero.isNotEmpty
                    ? () => Navigator.pop(context, _numero)
                    : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _TecladoNumMesa extends StatelessWidget {
  final void Function(String) onTecla;
  final VoidCallback onBorrar;
  final VoidCallback? onOk;

  const _TecladoNumMesa({
    required this.onTecla,
    required this.onBorrar,
    required this.onOk,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _fila(['1', '2', '3']),
        _fila(['4', '5', '6']),
        _fila(['7', '8', '9']),
        _filaEspecial(),
      ],
    );
  }

  Widget _fila(List<String> nums) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: nums
            .map((n) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: _BtnNum(label: n, onTap: () => onTecla(n)),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _filaEspecial() {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _BtnAccion(
                color: const Color(0xFF333333),
                onTap: onBorrar,
                child: const Icon(Icons.backspace_outlined,
                    color: Colors.white70, size: 24),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _BtnNum(label: '0', onTap: () => onTecla('0')),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: _BtnAccion(
                color: onOk != null
                    ? AppTheme.colorPrimario
                    : AppTheme.colorPrimario.withValues(alpha: 0.35),
                onTap: onOk,
                child: const Text(
                  'OK',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BtnNum extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _BtnNum({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2A2A2A),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class _BtnAccion extends StatelessWidget {
  final Widget child;
  final Color color;
  final VoidCallback? onTap;
  const _BtnAccion({required this.child, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}

// ── Badge de precio (unitario + total si cantidad > 1) ─────────

class _PrecioBadge extends StatelessWidget {
  final double unitario;
  final double total;
  final int cantidad;

  const _PrecioBadge({
    required this.unitario,
    required this.total,
    required this.cantidad,
  });

  String _fmt(double v) => '${v.toStringAsFixed(2)} €';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.colorPrimario.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.colorPrimario, width: 1),
      ),
      child: cantidad > 1
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fmt(unitario),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.colorTextoGris,
                  ),
                ),
                Text(
                  _fmt(total),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.colorPrimario,
                  ),
                ),
              ],
            )
          : Text(
              _fmt(unitario),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.colorPrimario,
              ),
            ),
    );
  }
}
