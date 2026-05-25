// lib/screens/hacer_pedido_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/cashlogy_service.dart';
import '../services/catalogo_provider.dart';
import '../utils/busqueda_texto.dart';
import '../utils/mesa_bloqueo.dart';
import '../utils/precio_redondeo.dart';
import '../utils/theme.dart';
import '../widgets/catalogo_panel.dart';
import '../widgets/lineas_panel.dart';
import '../widgets/producto_opciones_dialog.dart';
import 'package:restaurante_tpv/screens/reparto_comensales_screen.dart';
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
  late final ApiService _api;
  Timer? _pingTimer;
  bool _guardando = false;
  bool _offline = false;
  bool _cargandoPedido = true;
  bool _pantallaLista = false;
  /// Bloqueo expirado (3 min) u otro terminal con la mesa.
  bool _bloqueoPerdido = false;
  /// Solo desbloquear en servidor al pulsar Salir (no en dispose).
  bool _salidaExplicita = false;
  /// Marca la primera pulsacion de la flecha atras en el nivel raiz del catalogo.
  DateTime? _primeraPresionFlechaAtras;
  final GlobalKey<CatalogoPanelState> _catalogoKey =
      GlobalKey<CatalogoPanelState>();
  final TextEditingController _clienteCtrl = TextEditingController();
  Timer? _debounceCliente;

  @override
  void initState() {
    super.initState();
    _api = context.read<ApiService>();
    _clienteCtrl.clear();
    _inicializarSesionMesa();
  }

  Future<void> _inicializarSesionMesa() async {
    if (widget.bloqueadoPorMi) {
      _bloqueoPerdido = false;
      // El bloqueo ya se hizo en mesas_screen; aquí solo renovamos el ping.
      try {
        await _ping(soloRenovar: true);
      } on ApiException catch (_) {
        try {
          await _api.bloquearMesa(widget.idPedido);
          await _ping(soloRenovar: true);
        } catch (_) {
          // No pasar a solo lectura al entrar: confiar en el bloqueo de mesas_screen.
        }
      } catch (_) {}
      _pingTimer =
          Timer.periodic(const Duration(seconds: 60), (_) => _ping());
    }
    await _cargarPedido();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _debounceCliente?.cancel();
    _syncNombreCliente();
    if (widget.bloqueadoPorMi && _salidaExplicita) {
      _api.desbloquearMesa(widget.idPedido).ignore();
    }
    _clienteCtrl.dispose();
    super.dispose();
  }

  void _syncNombreCliente() {
    _debounceCliente?.cancel();
    _debounceCliente = null;
    if (!mounted) return;
    context.read<MesaProvider>().setNombreCliente(_clienteCtrl.text);
  }

  void _onClienteChanged(String v) {
    _debounceCliente?.cancel();
    _debounceCliente = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _syncNombreCliente();
    });
  }

  /// [salirSiNoExiste]: si false (p. ej. tras guardar), no hace pop al 404;
  /// lo gestiona quien llamó para evitar doble Navigator.pop.
  Future<void> _cargarPedido({bool salirSiNoExiste = true}) async {
    final api = context.read<ApiService>();
    final mesaPv = context.read<MesaProvider>();
    if (mounted) setState(() => _cargandoPedido = true);

    try {
      final miTerminal = await api.terminalSerie();
      final data = await api.getPedido(widget.idPedido);
      _aplicarDatosPedido(data, mesaPv, miTerminal: miTerminal);
      if (_clienteCtrl.text != mesaPv.nombreCliente) {
        _clienteCtrl.text = mesaPv.nombreCliente;
      }
      setState(() {
        _offline = false;
        _cargandoPedido = false;
        _pantallaLista = true;
      });
    } on ApiException catch (e) {
      if (_esMesaNoEncontrada(e)) {
        if (salirSiNoExiste) {
          await _salirPorMesaNoEncontrada(e.message);
        } else if (mounted) {
          setState(() {
            _cargandoPedido = false;
            _pantallaLista = true;
          });
        }
        return;
      }
      setState(() {
        _offline = true;
        _cargandoPedido = false;
        _pantallaLista = true;
      });
      Future.delayed(const Duration(seconds: 5), _cargarPedido);
    } catch (_) {
      setState(() {
        _offline = true;
        _cargandoPedido = false;
        _pantallaLista = true;
      });
      Future.delayed(const Duration(seconds: 5), _cargarPedido);
    }
  }

  bool _esMesaNoEncontrada(ApiException e) =>
      e.statusCode == 404 &&
      e.message.toLowerCase().contains('mesa no encontrada');

  bool _puedeEditar(MesaProvider mesaPv) =>
      mesaPv.bloqueadoPorMi && !mesaPv.soloLectura && !_bloqueoPerdido;

  void _aplicarDatosPedido(
    Map<String, dynamic> data,
    MesaProvider mesaPv, {
    required String miTerminal,
  }) {
    String? bloqueador = widget.bloqueador;
    // Si entramos con bloqueo concedido en mesas_screen, editar por defecto.
    var tengoBloqueo = widget.bloqueadoPorMi;
    _bloqueoPerdido = false;

    final bloqueo = data['bloqueo'];
    if (bloqueo is Map) {
      final vigente = bloqueo['vigente'] == true;
      final tengo = bloqueo['tengo_bloqueo'] == true;

      if (widget.bloqueadoPorMi) {
        if (vigente && !tengo) {
          tengoBloqueo = false;
          _bloqueoPerdido = true;
        } else if (vigente && tengo) {
          tengoBloqueo = true;
        } else {
          tengoBloqueo = true;
        }
      } else {
        tengoBloqueo = false;
      }
    } else if (!widget.bloqueadoPorMi) {
      tengoBloqueo = false;
    }

    if (!widget.bloqueadoPorMi) {
      tengoBloqueo = false;
      bloqueador = null;
      _bloqueoPerdido = false;
    }

    mesaPv.cargar(
      widget.idPedido,
      widget.idMesa,
      data,
      tengoBloqueo: tengoBloqueo,
      bloqueador: bloqueador,
    );
    if (_bloqueoPerdido || !tengoBloqueo) {
      mesaPv.forzarSoloLectura(bloqueador: bloqueador);
    }
  }

  void _onFlechaAtrasPressed() {
    final mesaPv = context.read<MesaProvider>();

    // En modo solo lectura, salir directamente.
    if (mesaPv.soloLectura || _bloqueoPerdido) {
      _salirMesa();
      return;
    }

    // Si estamos en una subcategoria, subir un nivel.
    final subioPorCategoria =
        _catalogoKey.currentState?.volverCategoriaSuperior() ?? false;
    if (subioPorCategoria) {
      _primeraPresionFlechaAtras = null;
      return;
    }

    // Nivel raiz: logica de doble pulsacion.
    final ahora = DateTime.now();
    if (_primeraPresionFlechaAtras != null &&
        ahora.difference(_primeraPresionFlechaAtras!).inSeconds < 3) {
      _primeraPresionFlechaAtras = null;
      if (mesaPv.hayCambiosSinGuardar) {
        _confirmarSalirSinGuardar();
      } else {
        _salirMesa();
      }
    } else {
      _primeraPresionFlechaAtras = ahora;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Pulsa de nuevo para salir'),
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  Future<void> _confirmarSalirSinGuardar() async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.colorTarjeta,
        title: const Text('Salir sin guardar?'),
        content: const Text(
            'Hay cambios sin guardar. Si sales ahora se perderan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange),
            child: const Text('Salir sin guardar'),
          ),
        ],
      ),
    );
    if (salir == true) _salirMesa();
  }

  Future<void> _salirMesa({String? aviso}) async {
    if (!mounted) return;
    _salidaExplicita = true;
    _pingTimer?.cancel();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (widget.bloqueadoPorMi && !_bloqueoPerdido) {
      try {
        await _api.desbloquearMesa(widget.idPedido);
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _cargandoPedido = false);
      context.read<MesaProvider>().reset();
    }
    if (!navigator.canPop()) return;
    navigator.pop();
    if (aviso != null && messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(aviso),
          backgroundColor: Colors.orange[900],
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _salirPorMesaNoEncontrada(String mensaje) async {
    if (!mounted) return;
    if (_cargandoPedido) {
      setState(() => _cargandoPedido = false);
    }
    await _salirMesa(
      aviso: mensaje.isNotEmpty
          ? mensaje
          : 'La mesa ya no está activa (cerrada o cobrada).',
    );
  }

  Future<void> _marcarBloqueoPerdido({String? mensaje}) async {
    if (!mounted) return;
    setState(() => _bloqueoPerdido = true);
    context
        .read<MesaProvider>()
        .forzarSoloLectura(bloqueador: 'Otro usuario / sesión expirada');
    await _cargarPedido();
    if (mensaje != null && mensaje.isNotEmpty) {
      _showError(mensaje);
    }
  }

  Future<void> _ping({bool soloRenovar = false}) async {
    final api = context.read<ApiService>();
    try {
      await api.pingMesa(widget.idPedido);
      if (_offline) setState(() => _offline = false);
    } on ApiException catch (e) {
      if (_esMesaNoEncontrada(e)) {
        await _salirPorMesaNoEncontrada(e.message);
        return;
      }
      if (e.statusCode == 409 && !soloRenovar) {
        await _marcarBloqueoPerdido(
          mensaje:
              'Ya no tienes esta mesa. Otro usuario puede haberla tomado o cobrado.',
        );
        return;
      }
      if (e.statusCode == null) {
        setState(() => _offline = true);
      }
    } catch (_) {
      setState(() => _offline = true);
    }
  }

  Future<bool> _guardar({bool imprimir = true}) async {
    if (_guardando) return false;
    _syncNombreCliente();
    final api = context.read<ApiService>();
    final catalogo = context.read<CatalogoProvider>();
    final mesaPv = context.read<MesaProvider>();
    final sesion = context.read<SesionProvider>();

    if (!_puedeEditar(mesaPv)) {
      _showError(
        _bloqueoPerdido
            ? 'No puedes guardar: la mesa la usa otro usuario o ya fue cobrada.'
            : kMesaBloqueadaSoloVer,
      );
      return false;
    }

    setState(() => _guardando = true);

    final lineasNuevas = mesaPv.lineas.where((l) => l.esNuevo).toList();
    final lineasEliminadas = <LineaPedido>[];
    final lineasMovidas =
        mesaPv.lineas.where((l) => l.moverAMesa != null).toList();

    try {
      await api.guardarPedido(
        widget.idPedido,
        mesaPv.lineasParaEnviar(),
        nombreCliente: mesaPv.nombreCliente,
        horaUltimaAccionRef: mesaPv.horaUltimaAccionRef,
      );

      final impresoraPorProducto = <int, int>{
        for (final p in catalogo.productos) p.id: p.idImpresora,
      };
      final impresorasPorId = <int, Impresora>{
        for (final imp in catalogo.impresoras) imp.id: imp,
      };

      if (imprimir) {
        final nuevasImp =
            SunmiService.agruparLineasIgualdadImpresion(lineasNuevas);
        final elimImp =
            SunmiService.agruparLineasIgualdadImpresion(lineasEliminadas);
        final movImp =
            SunmiService.agruparLineasIgualdadImpresion(lineasMovidas);
        await SunmiService.imprimirConfirmacion(
          idMesa: widget.idMesa,
          camarero: sesion.usuario?.nombre ?? '',
          lineasNuevas: nuevasImp,
          lineasEliminadas: elimImp,
          lineasMovidas: movImp,
          impresoraPorProducto: impresoraPorProducto,
          impresorasPorId: impresorasPorId,
        );
      }

      final pedidoBorrado = mesaPv.lineas.isEmpty;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                pedidoBorrado ? '✓ Pedido borrado' : '✓ Pedido guardado'),
            backgroundColor: Colors.green));
      }

      // Sin líneas el servidor elimina pedido_cabecera; no recargar (salida: botón guardar).
      if (pedidoBorrado) {
        return true;
      }

      if (mounted) setState(() => _bloqueoPerdido = false);
      await _cargarPedido(salirSiNoExiste: false);
      return true;
    } on ApiException catch (e) {
      if (_esMesaNoEncontrada(e)) {
        await _salirPorMesaNoEncontrada(e.message);
        return false;
      } else if (e.statusCode == 409) {
        await _marcarBloqueoPerdido(mensaje: e.message);
        return false;
      } else if (e.statusCode == null) {
        setState(() => _offline = true);
        _showError('Sin conexión. Los cambios se guardarán al reconectar.');
        _scheduleRetryGuardar();
      } else {
        _showError(e.message);
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

  Future<void> _guardarConDialogoImpresion() async {
    final noImprimir = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.colorTarjeta,
        title: const Text('Guardar pedido'),
        content: const Text('¿Quieres imprimir los cambios?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('No Imprimir'),
          ),
        ],
      ),
    );

    if (noImprimir != true) return;
    final guardadoOk = await _guardar(imprimir: false);
    if (guardadoOk && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _cerrarMesa() async {
    final mesaPv = context.read<MesaProvider>();
    if (!_puedeEditar(mesaPv)) {
      _showError(
        _bloqueoPerdido
            ? 'No puedes cobrar/cerrar: usa Salir y vuelve a entrar si la mesa sigue abierta.'
            : kMesaBloqueadaSoloVer,
      );
      return;
    }
    final api = context.read<ApiService>();
    final cashlogyOn = await CashlogyService.isEnabled();
    if (!mounted) return;
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
                Text(
                  cashlogyOn
                      ? 'Escribe "Cerrar" para confirmar el cierre de la mesa ${widget.idMesa}. '
                          'Después se cobrará el total en Cashlogy antes de cerrar en el servidor.'
                      : 'Escribe "Cerrar" para confirmar el cierre de la mesa ${widget.idMesa}.',
                ),
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
    final guardadoOk = await _guardar();
    if (!guardadoOk || !mounted) return;

    final catalogo = context.read<CatalogoProvider>();
    final totales = _calcularTotales(mesaPv.lineas, catalogo);
    if (cashlogyOn && totales.total > 0) {
      final cobrado = await _cobrarEnCashlogy(totales.total);
      if (!cobrado || !mounted) return;
    }

    try {
      await api.cerrarMesa(widget.idPedido);
      if (mounted) {
        context.read<MesaProvider>().reset();
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      if (_esMesaNoEncontrada(e)) {
        await _salirPorMesaNoEncontrada(
          'La mesa ya no está activa (posiblemente cerrada).',
        );
      } else {
        _showError(e.message);
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<bool> _cobrarEnCashlogy(double totalEuros) async {
    final centimos = CashlogyService.eurosACentimos(totalEuros);
    if (centimos <= 0) return true;

    if (!mounted) return false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppTheme.colorTarjeta,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Cobrando ${totalEuros.toStringAsFixed(2)} € en Cashlogy…\n'
                'Introduce el efectivo en la máquina.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final resultado = await CashlogyService().cobrar(
        importeCentimos: centimos,
        numeroOperacion: 'M${widget.idMesa}P${widget.idPedido}',
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!resultado.ok) {
        _showError(resultado.message ?? 'Cobro no completado en Cashlogy');
        return false;
      }
      if (mounted &&
          resultado.message != null &&
          resultado.message!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resultado.message!)),
        );
      }
      return true;
    } on CashlogyException catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _showError(e.message);
      return false;
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _showError(e.toString());
      return false;
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red[800]));
  }

  // ── Añadir producto ────────────────────────────────────────
  void onProductoTap(Producto p, BusquedaCatalogoPedido busq) {
    final catalogo = context.read<CatalogoProvider>();
    final opciones =
        busq.modo == ModoBusquedaCatalogoPedido.porFiltroOpciones &&
                busq.tokensOpcion.isNotEmpty
            ? catalogo.opcionesElegidasConTokensBusqueda(
                p, busq.tokensOpcion)
            : _defaultOpciones(p);
    _addProducto(p, cantidad: 1, comentario: '', opciones: opciones);
  }

  void onProductoLongPress(Producto p) async {
    final catalogo = context.read<CatalogoProvider>();
    final grupos = catalogo.gruposDeProducto(p.id);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProductoOpcionesDialog(
          producto: p, grupos: grupos, catalogo: catalogo),
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
    final grupos = catalogo.gruposDeProducto(p.id);
    final Map<int, OpcionElegida> defaults = {};
    for (final g in grupos) {
      final opts = catalogo.opcionesDeGrupo(p.id, g.id);
      final def =
          opts.where((o) => o.predeterminado).firstOrNull ?? opts.firstOrNull;
      if (def != null) {
        defaults[g.id] = OpcionElegida(
          nombre: def.nombreOpcion,
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
      nombreProducto: p.nombreProductoPantalla,
      opcionesElegidas: opciones,
      textoImprimirBarraCocina: p.textoImprimirBarraCocina,
      orden: 0,
    ));
  }

  // ── Nota / Artículo libre ────────────────────────────────────

  Future<void> _abrirNotaLibre() async {
    final catalogo = context.read<CatalogoProvider>();
    final api = context.read<ApiService>();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NotaLibreDialog(impresoras: catalogo.impresoras),
    );
    if (!mounted || result == null) return;
    if (result['accion'] == 'guardar') {
      try {
        await api.crearNotaLibre(
          idPedido: widget.idPedido,
          texto: result['texto'] as String,
          pvpConIva: result['pvp_con_iva'] as double,
          idImpresora: result['id_impresora'] as int,
        );
        await _cargarPedido();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nota añadida'), backgroundColor: Colors.green));
        }
      } catch (e) {
        _showError(e.toString());
      }
    }
  }

  Future<void> _editarNotaLibre(LineaPedido linea) async {
    final catalogo = context.read<CatalogoProvider>();
    final mesaPv = context.read<MesaProvider>();
    final api = context.read<ApiService>();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NotaLibreDialog(
        impresoras: catalogo.impresoras,
        textoInicial: linea.nombreProducto,
        pvpInicial: linea.pvpAlmacenado,
        modoEdicion: true,
      ),
    );
    if (!mounted || result == null) return;
    if (result['accion'] == 'eliminar') {
      mesaPv.eliminarLinea(linea);
      return;
    }
    if (result['accion'] == 'guardar') {
      try {
        await api.editarNotaLibre(
          idPedido: widget.idPedido,
          idLinea: linea.idLinea!,
          texto: result['texto'] as String,
          pvpConIva: result['pvp_con_iva'] as double,
        );
        await _cargarPedido();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nota actualizada'),
              backgroundColor: Colors.green));
        }
      } catch (e) {
        _showError(e.toString());
      }
    }
  }

  void onLineaTap(LineaPedido linea) async {
    final mesaPv = context.read<MesaProvider>();
    if (mesaPv.soloLectura) return;

    // Nota libre: editor especial
    if (linea.esNotaLibre) {
      _editarNotaLibre(linea);
      return;
    }

    final catalogo = context.read<CatalogoProvider>();
    final producto =
        catalogo.productos.where((p) => p.id == linea.idProducto).firstOrNull;
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

  // ── Totales: PVP unitario a 2 dec., igual que pedidos.php (evita 2×2,50 → 4,99) ─
  ({double base, double iva, double total}) _calcularTotales(
      List<LineaPedido> lineas, CatalogoProvider catalogo) {
    double base = 0;
    double iva = 0;
    double totalTtc = 0;
    for (final linea in lineas) {
      final producto = catalogo.productoPorId(linea.idProducto);
      if (producto == null) continue;
      final supl = <double>[];
      for (final entry in linea.opcionesElegidas.entries) {
        if (entry.value.predeterminado) continue;
        final opts = catalogo.opcionesDeGrupo(producto.id, entry.key);
        final match =
            opts.where((o) => o.nombreOpcion == entry.value.nombre).firstOrNull;
        if (match != null) supl.add(match.suplementoSinIva);
      }
      final baseUnit = baseImponibleUnitariaProductoLinea(
        baseImponibleProducto: producto.baseImponible,
        suplementosSinIvaNoPredeterminados: supl,
      );
      final pvpUnit = pvpUnitarioDesdeBaseSinIva(
        baseSinIvaUnitaria: baseUnit,
        porcentajeIva: producto.porcentajeIVA,
      );
      final lineTtc = importeTtcLinea(
        pvpUnitario: pvpUnit,
        cantidad: linea.cantidad,
      );
      final desglose = baseEIvaDesdeTtcLinea(
        importeTtc: lineTtc,
        porcentajeIva: producto.porcentajeIVA,
      );
      base += desglose.base;
      iva += desglose.iva;
      totalTtc += lineTtc;
    }
    return (
      base: redondearMoneda(base),
      iva: redondearMoneda(iva),
      total: redondearMoneda(totalTtc),
    );
  }

  Widget _buildTotalesStrip(
      List<LineaPedido> lineas, CatalogoProvider catalogo) {
    final t = _calcularTotales(lineas, catalogo);
    String fmt(double v) => '${v.toStringAsFixed(2)} €';
    return Container(
      color: const Color(0xFF1A2030),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _TotalChip(label: 'Base', valor: fmt(t.base)),
          const SizedBox(width: 10),
          _TotalChip(label: 'IVA', valor: fmt(t.iva)),
          const SizedBox(width: 10),
          _TotalChip(
              label: 'Total', valor: fmt(t.total), destacado: true),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_pantallaLista) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final mesaPv = context.watch<MesaProvider>();
    final sesion = context.read<SesionProvider>();
    final offline = _offline || !context.select<ApiService, bool>((a) => a.serverReachable);

    final puedeSalir = mesaPv.soloLectura || _bloqueoPerdido;

    return PopScope(
      canPop: puedeSalir,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (puedeSalir) {
          _salirMesa();
          return;
        }
        _catalogoKey.currentState?.volverCategoriaSuperior();
      },
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 32,
          titleSpacing: 4,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 22),
            tooltip: 'Volver / Salir',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _onFlechaAtrasPressed,
          ),
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              Text('${widget.idMesa}'),
              const SizedBox(width: 12),
              SizedBox(
                width: 126,
                height: 36,
                child: TextField(
                  controller: _clienteCtrl,
                  enabled: _puedeEditar(mesaPv),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  cursorColor: Colors.white,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 120,
                  onChanged: _onClienteChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: 'Cliente',
                    hintStyle: const TextStyle(color: Colors.white54),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                    filled: true,
                    fillColor: Colors.white12,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (mesaPv.soloLectura || _bloqueoPerdido)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _salirMesa(),
                child: Chip(
                  label: Text(
                    _bloqueoPerdido
                        ? 'Sin edición · pulsa para salir'
                        : kMesaBloqueadaSoloVer,
                  ),
                  backgroundColor: Colors.orange[800],
                ),
              )
            else ...[
              IconButton(
                onPressed: _guardando
                    ? null
                    : () async {
                        final guardadoOk = await _guardar();
                        if (guardadoOk && mounted) _salirMesa();
                      },
                onLongPress: _guardando ? null : _guardarConDialogoImpresion,
                icon: Icon(
                  Icons.save,
                  color: _guardando ? Colors.red : Colors.white,
                  size: 20,
                ),
              ),
              if (sesion.esSupervisor)
                IconButton(
                  onPressed: _cerrarMesa,
                  onLongPress: () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => RepartoComensalesScreen(
                          idMesa: widget.idMesa,
                          lineasPedido:
                              List<LineaPedido>.from(mesaPv.lineas),
                        ),
                      ),
                    );
                  },
                  tooltip: 'Cerrar mesa · mantén pulsado: reparto comensales',
                  icon: const Icon(Icons.euro, color: Colors.green, size: 22),
                ),
            ],
          ],
          bottom: offline
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_offline || !context.read<ApiService>().serverReachable)
                        Container(
                          color: Colors.red[900],
                          width: double.infinity,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wifi_off,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text(
                                'SERVIDOR INACCESIBLE — cambios pendientes de sincronizar',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              : null,
        ),
        body: _cargandoPedido
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Selector<MesaProvider, List<LineaPedido>>(
                    selector: (_, m) => m.lineas,
                    builder: (context, lineas, _) => _buildTotalesStrip(
                      lineas,
                      context.read<CatalogoProvider>(),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        // ── Columna izquierda: catálogo ──────────────
                        Expanded(
                          flex: 1,
                          child: mesaPv.soloLectura
                              ? const Center(
                                  child: Text(kMesaBloqueadaSoloVer,
                                      style: TextStyle(
                                          color: AppTheme.colorTextoGris,
                                          fontSize: 18)))
                              : _ColumnaCatalogoPedido(
                                  catalogoKey: _catalogoKey,
                                  onProductoTap: onProductoTap,
                                  onProductoLongPress: onProductoLongPress,
                                  onManual: _abrirNotaLibre,
                                ),
                        ),
                        const VerticalDivider(
                            width: 1, color: Color(0xFF333333)),
                        // ── Columna derecha: líneas del pedido ────────
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
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Columna catálogo: búsqueda aislada (no rebuild de toda la pantalla) ───────

class _ColumnaCatalogoPedido extends StatefulWidget {
  final GlobalKey<CatalogoPanelState> catalogoKey;
  final void Function(Producto p, BusquedaCatalogoPedido busq) onProductoTap;
  final void Function(Producto p) onProductoLongPress;
  final VoidCallback onManual;

  const _ColumnaCatalogoPedido({
    required this.catalogoKey,
    required this.onProductoTap,
    required this.onProductoLongPress,
    required this.onManual,
  });

  @override
  State<_ColumnaCatalogoPedido> createState() => _ColumnaCatalogoPedidoState();
}

class _ColumnaCatalogoPedidoState extends State<_ColumnaCatalogoPedido> {
  final TextEditingController _buscarCtrl = TextEditingController();
  Timer? _debounceBuscar;
  BusquedaCatalogoPedido _busqUi = kBusquedaCatalogoPedidoInactiva;
  BusquedaCatalogoPedido _busqFiltrado = kBusquedaCatalogoPedidoInactiva;

  @override
  void dispose() {
    _debounceBuscar?.cancel();
    _buscarCtrl.dispose();
    super.dispose();
  }

  void _onBuscarChanged(String raw) {
    setState(() => _busqUi = interpretarCampoBusquedaCatalogoMm(raw));
    _debounceBuscar?.cancel();
    _debounceBuscar = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _busqFiltrado =
            interpretarCampoBusquedaCatalogoMm(_buscarCtrl.text);
      });
    });
  }

  void _limpiarBusqueda() {
    _debounceBuscar?.cancel();
    _buscarCtrl.clear();
    setState(() {
      _busqUi = kBusquedaCatalogoPedidoInactiva;
      _busqFiltrado = kBusquedaCatalogoPedidoInactiva;
    });
  }

  @override
  Widget build(BuildContext context) {
    final busq = _busqUi;
    final busqLista = _busqFiltrado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: TextField(
            controller: _buscarCtrl,
            onChanged: _onBuscarChanged,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.2,
            ),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              hintText: 'Nombre · mm+código · mm+código opción…',
              hintStyle: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
                height: 1.2,
              ),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              prefixIcon: Icon(
                busq.modo == ModoBusquedaCatalogoPedido.porFiltroOpciones
                    ? Icons.tune
                    : busq.modo == ModoBusquedaCatalogoPedido.porFiltro
                        ? Icons.tag
                        : Icons.search,
                size: 20,
                color: busq.modo == ModoBusquedaCatalogoPedido.porFiltro ||
                        busq.modo == ModoBusquedaCatalogoPedido.porFiltroOpciones
                    ? AppTheme.colorPrimario
                    : Colors.white54,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              suffixIcon: busq.activa
                  ? IconButton(
                      tooltip: 'Limpiar',
                      icon: const Icon(Icons.clear, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                      onPressed: _limpiarBusqueda,
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
            ),
          ),
        ),
        Expanded(
          child: CatalogoPanel(
            key: widget.catalogoKey,
            onTap: (p) => widget.onProductoTap(p, busqLista),
            onLongPress: widget.onProductoLongPress,
            busquedaActiva: busqLista.activa,
            busqueda: busqLista,
            onManual: widget.onManual,
          ),
        ),
      ],
    );
  }
}

// ── Diálogo: Nota / Artículo libre ───────────────────────────────────────────

class _NotaLibreDialog extends StatefulWidget {
  final List<Impresora> impresoras;
  final String? textoInicial;
  final double pvpInicial;
  final bool modoEdicion;

  const _NotaLibreDialog({
    required this.impresoras,
    this.textoInicial,
    this.pvpInicial = 0.0,
    this.modoEdicion = false,
  });

  @override
  State<_NotaLibreDialog> createState() => _NotaLibreDialogState();
}

class _NotaLibreDialogState extends State<_NotaLibreDialog> {
  final _textoCtrl = TextEditingController();
  final _pvpCtrl = TextEditingController();
  int? _idImpresora;

  @override
  void initState() {
    super.initState();
    _textoCtrl.text = widget.textoInicial ?? '';
    if (widget.pvpInicial > 0) {
      _pvpCtrl.text = widget.pvpInicial.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _textoCtrl.dispose();
    _pvpCtrl.dispose();
    super.dispose();
  }

  bool get _valido => _textoCtrl.text.trim().isNotEmpty;

  double get _pvp =>
      double.tryParse(_pvpCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;

  void _confirmar() {
    Navigator.pop(context, {
      'accion': 'guardar',
      'texto': _textoCtrl.text.trim(),
      'pvp_con_iva': _pvp,
      'id_impresora': _idImpresora ?? 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = (screenWidth - 32).clamp(0.0, 480.0);
    final hInset = ((screenWidth - dialogWidth) / 2).clamp(0.0, double.infinity);

    return AlertDialog(
      backgroundColor: AppTheme.colorTarjeta,
      insetPadding: EdgeInsets.symmetric(horizontal: hInset, vertical: 24),
      title: Row(
        children: [
          Icon(Icons.edit_note, color: Colors.amber[300]),
          const SizedBox(width: 8),
          Text(widget.modoEdicion ? 'Editar nota' : 'Nota / Artículo libre'),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Descripción ──────────────────────────────────
            TextField(
              controller: _textoCtrl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 200,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Descripción *',
                hintText: 'Ej: Vino de la casa, Servilletero...',
                hintStyle:
                    const TextStyle(color: Colors.white38, fontSize: 14),
                filled: true,
                fillColor: AppTheme.colorSuperficie,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                counterStyle:
                    const TextStyle(color: AppTheme.colorTextoGris),
              ),
            ),
            const SizedBox(height: 12),
            // ── PVP con IVA 10 % ─────────────────────────────
            TextField(
              controller: _pvpCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'PVP con IVA 10 % incluido',
                hintText: '0.00',
                prefixText: '€  ',
                prefixStyle: const TextStyle(
                    color: AppTheme.colorPrimario,
                    fontWeight: FontWeight.bold),
                helperText: 'Dejar vacío o 0 si es gratuito',
                helperStyle:
                    const TextStyle(color: AppTheme.colorTextoGris),
                filled: true,
                fillColor: AppTheme.colorSuperficie,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            // ── Impresora (solo al crear) ─────────────────────
            if (!widget.modoEdicion && widget.impresoras.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _idImpresora,
                dropdownColor: AppTheme.colorTarjeta,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'Enviar a impresora',
                  helperText: 'Opcional — para imprimir en cocina/barra',
                  helperStyle:
                      const TextStyle(color: AppTheme.colorTextoGris),
                  filled: true,
                  fillColor: AppTheme.colorSuperficie,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Sin impresora'),
                  ),
                  for (final imp in widget.impresoras)
                    DropdownMenuItem<int?>(
                      value: imp.id,
                      child: Text(imp.nombre),
                    ),
                ],
                onChanged: (v) => setState(() => _idImpresora = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.modoEdicion)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, {'accion': 'eliminar'}),
            style: TextButton.styleFrom(
                foregroundColor: AppTheme.colorAcento),
            child: const Text('Eliminar'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _valido ? _confirmar : null,
          icon: Icon(widget.modoEdicion ? Icons.save : Icons.add, size: 18),
          label: Text(widget.modoEdicion ? 'Guardar' : 'Añadir'),
        ),
      ],
    );
  }
}

// ── Widget auxiliar: chip de valor para la barra de totales ──────────────────

class _TotalChip extends StatelessWidget {
  final String label;
  final String valor;
  final bool destacado;

  const _TotalChip({
    required this.label,
    required this.valor,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: destacado ? Colors.white70 : Colors.white54,
            ),
          ),
          TextSpan(
            text: valor,
            style: TextStyle(
              fontSize: destacado ? 15 : 13,
              fontWeight:
                  destacado ? FontWeight.bold : FontWeight.normal,
              color: destacado ? AppTheme.colorPrimario : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
