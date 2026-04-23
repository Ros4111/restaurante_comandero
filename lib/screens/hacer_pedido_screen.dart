// lib/screens/hacer_pedido_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';
import '../widgets/catalogo_panel.dart';
import '../widgets/lineas_panel.dart';
import '../widgets/producto_opciones_dialog.dart';
import '../widgets/editar_linea_dialog.dart';
import 'package:restaurante_tpv/services/sunmi_service.dart';

class HacerPedidoScreen extends StatefulWidget {
  final int idPedido;
  final int idMesa;
  final bool bloqueadoPorMi;
  final String? bloqueador;

  const HacerPedidoScreen({
    super.key,
    required this.idPedido,
    required this.idMesa,
    required this.bloqueadoPorMi,
    this.bloqueador,
  });

  @override
  State<HacerPedidoScreen> createState() => _HacerPedidoScreenState();
}

class _HacerPedidoScreenState extends State<HacerPedidoScreen> {
  Timer? _pingTimer;
  bool _guardando = false;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _cargarPedido();
    if (widget.bloqueadoPorMi) {
      // Ping cada 60s para mantener bloqueo
      _pingTimer = Timer.periodic(const Duration(seconds: 60), (_) => _ping());
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _cargarPedido() async {
    final api    = context.read<ApiService>();
    final mesaPv = context.read<MesaProvider>();

    try {
      final data = await api.getPedido(widget.idPedido);
      mesaPv.cargar(
        widget.idPedido,
        widget.idMesa,
        data,
        tengoBloqueo: widget.bloqueadoPorMi,
        bloqueador: widget.bloqueador,
      );
      setState(() => _offline = false);
    } catch (_) {
      setState(() => _offline = true);
      // modo offline: esperar y reintentar
      Future.delayed(const Duration(seconds: 5), _cargarPedido);
    }
  }

  Future<void> _ping() async {
    final api = context.read<ApiService>();
    try {
      await api.pingMesa(widget.idPedido);
      if (_offline) setState(() => _offline = false);
    } catch (_) {
      setState(() => _offline = true);
    }
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    final api    = context.read<ApiService>();
    final mesaPv = context.read<MesaProvider>();
    final sesion = context.read<SesionProvider>();

    setState(() => _guardando = true);

    final lineasNuevas     = mesaPv.lineas.where((l) => l.esNuevo).toList();
    final lineasEliminadas = <LineaPedido>[];
    final lineasMovidas    = mesaPv.lineas.where((l) => l.moverAMesa != null).toList();

    try {
      await api.guardarPedido(widget.idPedido, mesaPv.lineasParaEnviar());

      // Imprimir confirmación en Sunmi
      await SunmiService.imprimirConfirmacion(
        idMesa: widget.idMesa,
        camarero: sesion.usuario?.nombre ?? '',
        lineasNuevas: lineasNuevas,
        lineasEliminadas: lineasEliminadas,
        lineasMovidas: lineasMovidas,
      );

      // Recargar para sincronizar estado con servidor
      await _cargarPedido();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Pedido guardado'),
                backgroundColor: Colors.green));
      }
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        _showError('Bloqueo perdido: ${e.message}');
      } else {
        setState(() => _offline = true);
        _showError('Sin conexión. Los cambios se guardarán al reconectar.');
        _scheduleRetryGuardar();
      }
    } catch (e) {
      setState(() => _offline = true);
      _scheduleRetryGuardar();
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _scheduleRetryGuardar() {
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _offline) _guardar();
    });
  }

  Future<void> _cerrarMesa() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.colorTarjeta,
        title: const Text('Cerrar mesa'),
        content: Text('¿Cerrar la mesa ${widget.idMesa}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Cerrar')),
        ],
      ),
    );
    if (ok != true) return;
    final api = context.read<ApiService>();
    try {
      await api.cerrarMesa(widget.idPedido);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red[800]));
  }

  // ── Añadir producto ────────────────────────────────────────
  void onProductoTap(Producto p) {
    // Click simple: añadir con defaults
    _addProducto(p, cantidad: 1, comentario: '', opciones: _defaultOpciones(p));
  }

  void onProductoLongPress(Producto p) async {
    final catalogo = context.read<CatalogoProvider>();
    final grupos   = catalogo.gruposDeProducto(p.id);

    // Si tiene opciones o es personalizable → mostrar diálogo
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProductoOpcionesDialog(producto: p, grupos: grupos, catalogo: catalogo),
    );
    if (result == null) return;
    _addProducto(p,
        cantidad: result['cantidad'],
        comentario: result['comentario'],
        opciones: result['opciones']);
  }

  Map<int, String> _defaultOpciones(Producto p) {
    final catalogo = context.read<CatalogoProvider>();
    final grupos   = catalogo.gruposDeProducto(p.id);
    final Map<int, String> defaults = {};
    for (final g in grupos) {
      final opts = catalogo.opcionesDeGrupo(p.id, g.id);
      final def  = opts.where((o) => o.predeterminado).firstOrNull ?? opts.firstOrNull;
      if (def != null) defaults[g.id] = def.nombre;
    }
    return defaults;
  }

  void _addProducto(Producto p,
      {required int cantidad,
      required String comentario,
      required Map<int, String> opciones}) {
    final mesaPv = context.read<MesaProvider>();
    mesaPv.agregarLinea(LineaPedido(
      idProducto: p.id,
      cantidad: cantidad,
      comentario: comentario,
      nombreProducto: p.nombre,
      opcionesElegidas: opciones,
      textoImprimir: p.textoImprimir,
      orden: 0,
    ));
  }

  void onLineaTap(LineaPedido linea) async {
    if (context.read<MesaProvider>().soloLectura) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => EditarLineaDialog(linea: linea, idMesa: widget.idMesa),
    );
    if (result == null) return;
    final mesaPv = context.read<MesaProvider>();
    if (result['accion'] == 'eliminar') {
      mesaPv.eliminarLinea(linea);
    } else if (result['accion'] == 'mover') {
      mesaPv.modificarLinea(linea, moverAMesa: result['mesa_destino']);
    } else {
      mesaPv.modificarLinea(linea,
          cantidad: result['cantidad'],
          comentario: result['comentario']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api    = context.watch<ApiService>();
    final mesaPv = context.watch<MesaProvider>();
    final sesion = context.watch<SesionProvider>();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Mesa ${widget.idMesa}'),
        actions: [
          if (mesaPv.soloLectura)
            Chip(
              label: Text('Solo lectura · ${mesaPv.nombreBloqueador ?? ''}'),
              backgroundColor: Colors.orange[800],
            )
          else ...[
            if (_guardando)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              TextButton.icon(
                onPressed: _guardar,
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text('Guardar', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            if (sesion.esSupervisor)
              TextButton.icon(
                onPressed: _cerrarMesa,
                icon: const Icon(Icons.check_circle, color: Colors.green),
                label: const Text('Cerrar Mesa', style: TextStyle(color: Colors.green, fontSize: 16)),
              ),
          ],
        ],
        bottom: _offline || !api.serverReachable
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  color: Colors.red[900],
                  width: double.infinity,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.wifi_off, color: Colors.white, size: 14),
                    SizedBox(width: 6),
                    Text('SERVIDOR INACCESIBLE — cambios pendientes de sincronizar',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ]),
                ),
              )
            : null,
      ),
      body: Row(
        children: [
          // ── Columna izquierda: catálogo ────────────────────
          Expanded(
            flex: 5,
            child: mesaPv.soloLectura
                ? const Center(child: Text('Modo solo lectura',
                    style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 18)))
                : CatalogoPanel(
                    onTap: onProductoTap,
                    onLongPress: onProductoLongPress,
                  ),
          ),
          const VerticalDivider(width: 1, color: Color(0xFF333333)),
          // ── Columna derecha: líneas del pedido ─────────────
          Expanded(
            flex: 4,
            child: LineasPanel(
              lineas: mesaPv.lineas,
              soloLectura: mesaPv.soloLectura,
              onLineaTap: onLineaTap,
            ),
          ),
        ],
      ),
    );
  }
}
