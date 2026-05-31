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
  StreamSubscription<void>? _servicioStreamSub;
  StreamSubscription<void>? _catalogoStreamSub;
  Timer? _fallbackRefreshTimer;
  bool _actualizando = false;
  bool _cargaInicialHecha = false;
  Set<int> _lineasConocidas = {};
  Set<String> _gruposConocidos = {};
  Set<int> _lineasUrgentesConocidas = {};
  AudioPlayer? _avisoPlayer;

  double _fs(double base) => (base + _deltaFuente).clamp(9.0, 36.0).toDouble();

  /// Clave de selección única por tarjeta (evita colisión si varios lotes comparten idGrupo).
  String _claveSeleccion(PedidoPendienteServir p) {
    if (p.lineas.isEmpty) return p.idGrupo;
    final ids = p.lineas.expand((l) => l.idsLinea).toList()..sort();
    return '${p.idGrupo}#${ids.join('-')}';
  }

  Set<int> _lineasSeleccionadas(PedidoPendienteServir p) {
    final sel = _seleccion[_claveSeleccion(p)];
    if (sel == null || sel.isEmpty) return {};
    final idsTarjeta = p.lineas.expand((l) => l.idsLinea).toSet();
    return sel.where(idsTarjeta.contains).toSet();
  }

  @override
  void initState() {
    super.initState();
    _avisoPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _cargar();
    _iniciarSincronizacionTiempoReal();
  }

  void _iniciarSincronizacionTiempoReal() {
    final api = context.read<ApiService>();
    _servicioStreamSub?.cancel();
    _servicioStreamSub = api.subscribeServicioPendientesUpdates().listen((_) {
      if (!_marcando && mounted) _cargar(silencioso: true);
    });
    _catalogoStreamSub?.cancel();
    _catalogoStreamSub = api.subscribeCatalogoUpdates().listen((_) {
      if (mounted) _refrescarCatalogoSilencioso();
    });
    // Respaldo si SSE no está disponible (proxy, timeout, etc.)
    _fallbackRefreshTimer?.cancel();
    _fallbackRefreshTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) {
        if (!_marcando && mounted) _cargar(silencioso: true);
      },
    );
  }

  Future<void> _refrescarCatalogoSilencioso() async {
    try {
      final data = await context.read<ApiService>().getCatalogo();
      if (mounted) context.read<CatalogoProvider>().cargar(data);
    } catch (_) {}
  }

  @override
  void dispose() {
    _servicioStreamSub?.cancel();
    _catalogoStreamSub?.cancel();
    _fallbackRefreshTimer?.cancel();
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

      lista.sort((a, b) {
        if (a.tieneUrgente != b.tieneUrgente) {
          return a.tieneUrgente ? -1 : 1;
        }
        return a.horaPedido.compareTo(b.horaPedido);
      });
      for (final p in lista) {
        p.lineas.sort((a, b) {
          if (a.urgente != b.urgente) return a.urgente ? -1 : 1;
          return a.nombre.compareTo(b.nombre);
        });
      }

      final lineasActuales = {
        for (final p in lista)
          for (final l in p.lineas)
            for (final id in l.idsLinea)
              id,
      };
      final urgentesActuales = {
        for (final p in lista)
          for (final l in p.lineas)
            if (l.urgente) ...l.idsLinea,
      };
      final gruposActuales = lista.map((p) => p.idGrupo).toSet();
      final lineasNuevas = lineasActuales.difference(_lineasConocidas);
      final gruposNuevos = gruposActuales.difference(_gruposConocidos);
      final urgentesNuevos =
          urgentesActuales.difference(_lineasUrgentesConocidas);
      final hayNovedad = _cargaInicialHecha &&
          (lineasNuevas.isNotEmpty || gruposNuevos.isNotEmpty);
      final hayUrgenteNuevo =
          _cargaInicialHecha && urgentesNuevos.isNotEmpty;

      setState(() {
        _pedidos = lista;
        _lineasConocidas = lineasActuales;
        _gruposConocidos = gruposActuales;
        _lineasUrgentesConocidas = urgentesActuales;
        _cargaInicialHecha = true;
        _seleccion.removeWhere(
          (clave, _) => !lista.any((p) => _claveSeleccion(p) == clave),
        );
        for (final p in lista) {
          final vigentes =
              p.lineas.expand((l) => l.idsLinea).toSet();
          _seleccion
              .putIfAbsent(_claveSeleccion(p), () => {})
              .removeWhere((id) => !vigentes.contains(id));
        }
        if (!silencioso) _cargando = false;
      });

      if (hayNovedad || hayUrgenteNuevo) {
        debugPrint(
          '[pendientes_servir] Novedad: ${lineasNuevas.length} línea(s), '
          '${gruposNuevos.length} lote(s), '
          '${urgentesNuevos.length} urgente(s)',
        );
        unawaited(_sonidoPedidoNuevo(repetir: hayUrgenteNuevo));
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

  Future<void> _preguntarAgotado(LineaPendienteServir l) async {
    if (l.idProducto <= 0 || _marcando) return;
    final catalogo = context.read<CatalogoProvider>();
    final prod = catalogo.productoPorId(l.idProducto);
    final nombre = prod?.nombreProductoPantalla ?? l.nombre;
    final yaAgotado = prod?.agotado ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.colorTarjeta,
        title: Text(
          yaAgotado ? 'Quitar 86' : 'Marcar 86',
          style: const TextStyle(color: AppTheme.colorTexto),
        ),
        content: Text(
          yaAgotado
              ? '¿Volver a ofrecer «$nombre»?'
              : '¿Marcar «$nombre» como AGOTADO (86)?\n'
                  'Los camareros no podrán pedirlo.',
          style: const TextStyle(color: AppTheme.colorTextoGris),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              yaAgotado ? 'Disponible' : '86',
              style: TextStyle(
                color: yaAgotado ? AppTheme.colorPrimario : AppTheme.colorAgotado,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context
          .read<ApiService>()
          .marcarProductoAgotado(l.idProducto, !yaAgotado);
      catalogo.setAgotadoLocal(l.idProducto, !yaAgotado);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            yaAgotado ? 'Disponible: $nombre' : '86 — AGOTADO: $nombre',
          ),
          backgroundColor:
              yaAgotado ? AppTheme.colorPrimario : AppTheme.colorAgotado,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red[800],
        ),
      );
    }
  }

  Future<void> _sonidoPedidoNuevo({bool repetir = false}) async {
    Future<void> playOnce() async {
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

    await playOnce();
    if (repetir) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await playOnce();
    }
  }

  void _toggleLinea(String clave, LineaPendienteServir l, bool? v) {
    setState(() {
      final set = _seleccion.putIfAbsent(clave, () => {});
      if (v == true) {
        set.addAll(l.idsLinea);
      } else {
        set.removeAll(l.idsLinea);
      }
    });
  }

  void _seleccionarTodo(PedidoPendienteServir pedido) {
    final clave = _claveSeleccion(pedido);
    setState(() {
      _seleccion
          .putIfAbsent(clave, () => {})
          .addAll(pedido.lineas.expand((l) => l.idsLinea));
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
    final tieneModificadas =
        pedido.lineas.any((l) => l.modificado);
    final esUrgente = pedido.tieneUrgente;
    return Card(
      color: tieneModificadas
          ? const Color(0xFF1E3324)
          : (esUrgente ? const Color(0xFF2A2218) : AppTheme.colorTarjeta),
      clipBehavior: Clip.antiAlias,
      shape: esUrgente
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.colorUrgente, width: 2),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: tieneModificadas
                ? const Color(0xFF2A4030)
                : (esUrgente
                    ? const Color(0xFF3D2E18)
                    : const Color(0xFF2A3344)),
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
                        color: esUrgente
                            ? AppTheme.colorUrgente
                            : AppTheme.colorPrimario,
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
                    if (esUrgente) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.colorUrgente.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.colorUrgente),
                        ),
                        child: Text(
                          'URGENTE',
                          style: TextStyle(
                            color: AppTheme.colorUrgente,
                            fontSize: _fs(11),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
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
                if (tieneModificadas)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Pedido modificado',
                      style: TextStyle(
                        color: AppTheme.colorLineasModificadas,
                        fontSize: _fs(12),
                        fontWeight: FontWeight.w600,
                      ),
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
    final checked =
        l.idsLinea.isNotEmpty && l.idsLinea.every((id) => sel.contains(id));
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
    final prodAgotado = catalogo.productoPorId(l.idProducto)?.agotado ?? false;
    final colorLinea = l.modificado
        ? AppTheme.colorLineasModificadas
        : (l.urgente
            ? AppTheme.colorUrgente
            : (prodAgotado ? AppTheme.colorAgotado : AppTheme.colorTexto));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: DecoratedBox(
        decoration: l.modificado
            ? BoxDecoration(
                color: const Color(0xFF66BB6A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppTheme.colorLineasModificadas.withValues(alpha: 0.5),
                ),
              )
            : l.urgente
                ? BoxDecoration(
                    color: AppTheme.colorUrgente.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppTheme.colorUrgente.withValues(alpha: 0.55),
                    ),
                  )
                : prodAgotado
                    ? BoxDecoration(
                        color: AppTheme.colorAgotado.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppTheme.colorAgotado.withValues(alpha: 0.45),
                        ),
                      )
                    : const BoxDecoration(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal:
                l.modificado || l.urgente || prodAgotado ? 6 : 0,
            vertical: l.modificado || l.urgente || prodAgotado ? 4 : 0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: checked,
                onChanged:
                    _marcando ? null : (v) => _toggleLinea(clave, l, v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                activeColor: l.modificado
                    ? AppTheme.colorLineasModificadas
                    : (l.urgente ? AppTheme.colorUrgente : null),
              ),
              Expanded(
                child: GestureDetector(
                  onLongPress: l.idProducto > 0 && !_marcando
                      ? () => _preguntarAgotado(l)
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (l.urgente) ...[
                            Icon(Icons.priority_high,
                                size: _fs(16), color: AppTheme.colorUrgente),
                            const SizedBox(width: 2),
                          ],
                          if (prodAgotado) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.colorAgotado
                                    .withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(3),
                                border:
                                    Border.all(color: AppTheme.colorAgotado),
                              ),
                              child: Text(
                                '86',
                                style: TextStyle(
                                  fontSize: _fs(11),
                                  color: AppTheme.colorAgotado,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          Expanded(
                            child: Text(
                              titulo,
                              style: TextStyle(
                                fontSize: _fs(15),
                                color: colorLinea,
                                fontWeight: l.modificado ||
                                        l.urgente ||
                                        prodAgotado
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (subtitulo != null) subtitulo,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
            color: l.modificado
                ? AppTheme.colorLineasModificadas.withValues(alpha: 0.85)
                : AppTheme.colorTextoGris,
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
