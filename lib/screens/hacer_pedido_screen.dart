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

  Future<bool> _guardar() async {
    if (_guardando) return false;
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
      return true;
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
    return false;
  }

  void _scheduleRetryGuardar() {
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _offline) _guardar();
    });
  }

  Future<void> _cerrarMesa() async {
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final confirmacionValida =
              confirmCtrl.text.trim().toLowerCase() == 'cerrar';
          return AlertDialog(
            backgroundColor: AppTheme.colorTarjeta,
            title: const Text('Cerrar mesa'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Escribe "Cerrar" para confirmar el cierre de la mesa ${widget.idMesa}.'),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmCtrl,
                  autofocus: true,
                  onChanged: (_) => setStateDialog(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Confirmacion',
                    hintText: 'Cerrar',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: confirmacionValida
                    ? () => Navigator.pop(context, true)
                    : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
    confirmCtrl.dispose();
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
    final opciones = Map<int, OpcionElegida>.from(result['opciones'] as Map);
    _addProducto(p,
        cantidad: result['cantidad'],
        comentario: result['comentario'],
        opciones: opciones);
  }

  Map<int, OpcionElegida> _defaultOpciones(Producto p) {
    final catalogo = context.read<CatalogoProvider>();
    final grupos   = catalogo.gruposDeProducto(p.id);
    final Map<int, OpcionElegida> defaults = {};
    for (final g in grupos) {
      final opts = catalogo.opcionesDeGrupo(p.id, g.id);
      final def  = opts.where((o) => o.predeterminado).firstOrNull ?? opts.firstOrNull;
      if (def != null) {
        defaults[g.id] = OpcionElegida(
          nombre: def.nombre,
          predeterminado: def.predeterminado,
        );
      }
    }
    return defaults;
  }

  void _addProducto(Producto p,
      {required int cantidad,
      required String comentario,
      required Map<int, OpcionElegida> opciones}) {
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
    final catalogo = context.read<CatalogoProvider>();
    final producto = catalogo.productos
        .where((p) => p.id == linea.idProducto)
        .firstOrNull;
    if (producto == null) {
      _showError('No se pudo abrir el editor del producto');
      return;
    }
    final grupos = catalogo.gruposDeProducto(producto.id);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProductoOpcionesDialog(
        producto: producto,
        grupos: grupos,
        catalogo: catalogo,
        cantidadInicial: linea.cantidad,
        comentarioInicial: linea.comentario,
        opcionesIniciales: linea.opcionesElegidas,
        modoEdicion: true,
      ),
    );
    if (result == null) return;
    final mesaPv = context.read<MesaProvider>();
    if (result['accion'] == 'eliminar') {
      mesaPv.eliminarLinea(linea);
    } else if (result['accion'] == 'mover') {
      mesaPv.modificarLinea(linea, moverAMesa: result['mesa_destino']);
    } else {
      final nuevasOpciones = result['opciones'] != null
          ? Map<int, OpcionElegida>.from(result['opciones'] as Map)
          : linea.opcionesElegidas;
      final nuevaCantidad = result['cantidad'] as int;
      final nuevoComentario = result['comentario'] as String;
      final hayCambios = nuevaCantidad != linea.cantidad ||
          nuevoComentario != linea.comentario ||
          !_opcionesIguales(linea.opcionesElegidas, nuevasOpciones);

      mesaPv.modificarLinea(linea,
          cantidad: nuevaCantidad,
          comentario: nuevoComentario,
          opcionesElegidas: nuevasOpciones,
          marcarEditada: hayCambios);
    }
  }

  bool _opcionesIguales(
    Map<int, OpcionElegida> a,
    Map<int, OpcionElegida> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (other.nombre != entry.value.nombre ||
          other.predeterminado != entry.value.predeterminado) {
        return false;
      }
    }
    return true;
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
            IconButton(
              onPressed: _guardando
                  ? null
                  : () async {
                      final guardadoOk = await _guardar();
                      if (guardadoOk && mounted) {
                        Navigator.pop(context);
                      }
                    },
              icon: Icon(
                Icons.save,
                color: _guardando ? Colors.red : Colors.white,
                size: 20,
              ),
            ),
            if (sesion.esSupervisor)
              IconButton(
                onPressed: _cerrarMesa,
                tooltip: 'Cerrar mesa',
                icon: const Icon(Icons.euro, color: Colors.green, size: 22),
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
            flex: 1,
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
            flex: 1,
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
