// Pantalla de productos pendientes de servir en mesa (cocina / barra / servicio).
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/catalogo_provider.dart';
import '../utils/opciones_linea.dart';
import '../utils/theme.dart';
import 'login_screen.dart';

class PendientesServirScreen extends StatefulWidget {
  const PendientesServirScreen({super.key});

  @override
  State<PendientesServirScreen> createState() => _PendientesServirScreenState();
}

class _PendientesServirScreenState extends State<PendientesServirScreen> {
  static const _deltaFuenteMin = -6;
  static const _deltaFuenteMax = 14;
  static const _pasoFuente = 2;

  List<PedidoPendienteServir> _pedidos = [];
  final Map<String, Set<int>> _seleccion = {};
  bool _cargando = true;
  bool _marcando = false;
  String? _error;
  int _deltaFuente = 0;
  Timer? _autoRefreshTimer;
  bool _actualizando = false;
  bool _cargaInicialHecha = false;
  Set<int> _lineasConocidas = {};
  Set<String> _gruposConocidos = {};
  AudioPlayer? _avisoPlayer;

  double _fs(double base) => (base + _deltaFuente).clamp(9.0, 36.0).toDouble();

  /// Clave de selección única por tarjeta (evita colisión si varios lotes comparten idGrupo).
  String _claveSeleccion(PedidoPendienteServir p) {
    if (p.lineas.isEmpty) return p.idGrupo;
    final ids = p.lineas.map((l) => l.idLinea).toList()..sort();
    return '${p.idGrupo}#${ids.join('-')}';
  }

  Set<int> _lineasSeleccionadas(PedidoPendienteServir p) {
    final sel = _seleccion[_claveSeleccion(p)];
    if (sel == null || sel.isEmpty) return {};
    final idsTarjeta = p.lineas.map((l) => l.idLinea).toSet();
    return sel.where(idsTarjeta.contains).toSet();
  }

  @override
  void initState() {
    super.initState();
    _avisoPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _cargar();
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) {
        if (!_marcando && mounted) _cargar(silencioso: true);
      },
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _avisoPlayer?.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (_actualizando) return;
    _actualizando = true;
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final lista = await context.read<ApiService>().getServicioPendientes();
      if (!mounted) return;

      final lineasActuales = {
        for (final p in lista) for (final l in p.lineas) l.idLinea,
      };
      final gruposActuales = lista.map((p) => p.idGrupo).toSet();
      final lineasNuevas = lineasActuales.difference(_lineasConocidas);
      final gruposNuevos = gruposActuales.difference(_gruposConocidos);
      final hayNovedad = _cargaInicialHecha &&
          (lineasNuevas.isNotEmpty || gruposNuevos.isNotEmpty);

      setState(() {
        _pedidos = lista;
        _lineasConocidas = lineasActuales;
        _gruposConocidos = gruposActuales;
        _cargaInicialHecha = true;
        _seleccion.removeWhere(
          (clave, _) => !lista.any((p) => _claveSeleccion(p) == clave),
        );
        for (final p in lista) {
          final vigentes = p.lineas.map((l) => l.idLinea).toSet();
          _seleccion
              .putIfAbsent(_claveSeleccion(p), () => {})
              .removeWhere((id) => !vigentes.contains(id));
        }
        if (!silencioso) _cargando = false;
      });

      if (hayNovedad) {
        debugPrint(
          '[pendientes_servir] Novedad: ${lineasNuevas.length} línea(s), '
          '${gruposNuevos.length} lote(s)',
        );
        unawaited(_sonidoPedidoNuevo());
      }
    } catch (e) {
      if (!mounted) return;
      if (silencioso) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    } finally {
      _actualizando = false;
    }
  }

  Future<void> _sonidoPedidoNuevo() async {
    final player = _avisoPlayer;
    if (player != null) {
      try {
        await player.stop();
        await player.play(
          AssetSource('cocina.mp3'),
          volume: 1.0,
        );
        return;
      } catch (e) {
        debugPrint('[pendientes_servir] audioplayers: $e');
      }
    }

    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      debugPrint('[pendientes_servir] SystemSound: $e');
    }
  }

  void _toggleLinea(String clave, int idLinea, bool? v) {
    setState(() {
      final set = _seleccion.putIfAbsent(clave, () => {});
      if (v == true) {
        set.add(idLinea);
      } else {
        set.remove(idLinea);
      }
    });
  }

  void _seleccionarTodo(PedidoPendienteServir pedido) {
    final clave = _claveSeleccion(pedido);
    setState(() {
      _seleccion
          .putIfAbsent(clave, () => {})
          .addAll(pedido.lineas.map((l) => l.idLinea));
    });
  }

  Future<void> _hechoPedido(PedidoPendienteServir pedido) async {
    final ids = _lineasSeleccionadas(pedido).toList();
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marca al menos un producto')),
      );
      return;
    }
    setState(() => _marcando = true);
    try {
      final n = await context.read<ApiService>().marcarLineasServidas(ids);
      if (!mounted) return;
      if (n <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se actualizó ninguna línea'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        _seleccion[_claveSeleccion(pedido)]?.clear();
      }
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red[900],
        ),
      );
    } finally {
      if (mounted) setState(() => _marcando = false);
    }
  }

  void _cerrarSesion() {
    context.read<ApiService>().clearToken();
    context.read<SesionProvider>().logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _cargando || _marcando ? null : _cargar,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Actualizar',
                  ),
                  IconButton(
                    onPressed: _deltaFuente <= _deltaFuenteMin
                        ? null
                        : () => setState(
                              () => _deltaFuente = (_deltaFuente - _pasoFuente)
                                  .clamp(_deltaFuenteMin, _deltaFuenteMax),
                            ),
                    tooltip: 'Reducir texto',
                    icon: const Text(
                      '−',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _deltaFuente >= _deltaFuenteMax
                        ? null
                        : () => setState(
                              () => _deltaFuente = (_deltaFuente + _pasoFuente)
                                  .clamp(_deltaFuenteMin, _deltaFuenteMax),
                            ),
                    tooltip: 'Aumentar texto',
                    icon: const Text(
                      '+',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _cerrarSesion,
                    icon: const Icon(Icons.logout),
                    tooltip: 'Salir',
                  ),
                ],
              ),
            ),
            Expanded(child: _buildCuerpo()),
          ],
        ),
      ),
    );
  }

  Widget _buildCuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: _fs(16)),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _cargar,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_pedidos.isEmpty) {
      return Center(
        child: Text(
          'No hay productos pendientes de servir',
          style: TextStyle(
            color: AppTheme.colorTextoGris,
            fontSize: _fs(16),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxAnchoTarjeta = constraints.maxWidth - 20;
        return RefreshIndicator(
          onRefresh: _cargar,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: _pedidos
                  .map(
                    (p) => ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: 140,
                        maxWidth: maxAnchoTarjeta,
                      ),
                      child: IntrinsicWidth(
                        child: _tarjetaPedido(p),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }

  String _horaCorta(String horaPedido) {
    if (horaPedido.length >= 16) {
      return horaPedido.substring(11, 16);
    }
    if (horaPedido.length >= 5) {
      return horaPedido.substring(horaPedido.length - 5);
    }
    return horaPedido;
  }

  Widget _tarjetaPedido(PedidoPendienteServir pedido) {
    final clave = _claveSeleccion(pedido);
    final sel = _lineasSeleccionadas(pedido);
    final cliente = pedido.nombreCliente.trim();
    final hora = pedido.horaPedido.trim();
    return Card(
      color: AppTheme.colorTarjeta,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: const Color(0xFF2A3344),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.colorPrimario,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Mesa ${pedido.idMesa}',
                        style: TextStyle(
                          fontSize: _fs(17),
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: _marcando || pedido.lineas.isEmpty
                          ? null
                          : () => _seleccionarTodo(pedido),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text('Todo', style: TextStyle(fontSize: _fs(13))),
                    ),
                  ],
                ),
                if (hora.isNotEmpty)
                  Text(
                    _horaCorta(hora),
                    style: TextStyle(
                      color: AppTheme.colorTextoGris,
                      fontSize: _fs(12),
                    ),
                  ),
                if (cliente.isNotEmpty)
                  Text(
                    cliente,
                    style: TextStyle(
                      color: AppTheme.colorTextoGris,
                      fontSize: _fs(13),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: pedido.lineas
                  .map((l) => _filaLinea(clave, l, sel))
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: FilledButton(
              onPressed: _marcando || sel.isEmpty
                  ? null
                  : () => _hechoPedido(pedido),
              child: Text('Hecho', style: TextStyle(fontSize: _fs(14))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaLinea(String clave, LineaPendienteServir l, Set<int> sel) {
    final checked = sel.contains(l.idLinea);
    final titulo = l.cantidad > 1 ? '${l.nombre}  ×${l.cantidad}' : l.nombre;
    final catalogo = context.read<CatalogoProvider>();
    final opciones = catalogo.loaded
        ? opcionesNoPredAMostrar(l.idProducto, l.opcionesElegidas, catalogo)
        : l.opcionesElegidas.values
            .where((o) => !o.predeterminado)
            .map((o) => o.nombre)
            .where((n) => n.isNotEmpty)
            .toList();
    final subtitulo = _subtituloLinea(l, opciones);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: checked,
            onChanged:
                _marcando ? null : (v) => _toggleLinea(clave, l.idLinea, v),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titulo,
                style: TextStyle(fontSize: _fs(15)),
              ),
              if (subtitulo != null) subtitulo,
            ],
          ),
        ],
      ),
    );
  }

  Widget? _subtituloLinea(LineaPendienteServir l, List<String> opciones) {
    final partes = <Widget>[];
    if (opciones.isNotEmpty) {
      partes.add(
        Wrap(
          spacing: 4,
          runSpacing: 2,
          children: opciones
              .map(
                (op) => Chip(
                  label: Text(op, style: TextStyle(fontSize: _fs(11))),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
              .toList(),
        ),
      );
    }
    if (l.comentario.trim().isNotEmpty) {
      partes.add(
        Text(
          l.comentario,
          style: TextStyle(
            fontSize: _fs(12),
            color: AppTheme.colorTextoGris,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    if (partes.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: partes,
    );
  }
}
