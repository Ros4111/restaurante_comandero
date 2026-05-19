// lib/screens/reparto_comensales_screen.dart
// Reparto del importe del pedido entre comensales (una fila por unidad).
import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../models/models.dart';
import '../services/catalogo_provider.dart';
import '../services/sunmi_service.dart';
import '../utils/precio_redondeo.dart';
import '../utils/theme.dart';

class _UnidadFila {
  final String nombre;
  final double importeUnitarioTtc;
  final List<String> opcionesConSuplemento;

  const _UnidadFila({
    required this.nombre,
    required this.importeUnitarioTtc,
    this.opcionesConSuplemento = const [],
  });
}

/// Opciones elegidas no predeterminadas con suplemento que sube el PVP unitario.
List<String> _opcionesQueIncrementanPrecio(
  LineaPedido linea,
  CatalogoProvider catalogo,
  Producto producto,
) {
  final out = <String>[];
  for (final entry in linea.opcionesElegidas.entries) {
    if (entry.value.predeterminado) continue;
    final match = catalogo.opcionPorNombre(
      producto.id,
      entry.key,
      entry.value.nombre,
    );
    if (match == null || match.suplementoSinIva <= 0) continue;
    final nombre = entry.value.nombre.trim();
    if (nombre.isEmpty) continue;
    out.add(nombre);
  }
  return out;
}

double _pvpUnidadLinea(
  LineaPedido linea,
  CatalogoProvider catalogo,
  Map<int, Producto> productosPorId,
) {
  final producto = productosPorId[linea.idProducto];
  if (producto == null) return 0;
  final supl = <double>[];
  for (final entry in linea.opcionesElegidas.entries) {
    if (entry.value.predeterminado) continue;
    final match = catalogo.opcionPorNombre(
      producto.id,
      entry.key,
      entry.value.nombre,
    );
    if (match != null) supl.add(match.suplementoSinIva);
  }
  final baseUnit = baseImponibleUnitariaProductoLinea(
    baseImponibleProducto: producto.baseImponible,
    suplementosSinIvaNoPredeterminados: supl,
  );
  return pvpUnitarioDesdeBaseSinIva(
    baseSinIvaUnitaria: baseUnit,
    porcentajeIva: producto.porcentajeIVA,
  );
}

List<_UnidadFila> _expandirUnidades(
  List<LineaPedido> lineas,
  CatalogoProvider catalogo,
) {
  final productosPorId = {for (final p in catalogo.productos) p.id: p};
  final out = <_UnidadFila>[];
  for (final linea in lineas) {
    if (linea.cantidad <= 0) continue;
    final pvp = _pvpUnidadLinea(linea, catalogo, productosPorId);
    if (pvp <= 0) continue;
    final producto = productosPorId[linea.idProducto];
    final nombre = linea.nombreProducto.trim().isEmpty
        ? 'Producto #${linea.idProducto}'
        : linea.nombreProducto;
    final opciones = producto != null
        ? _opcionesQueIncrementanPrecio(linea, catalogo, producto)
        : <String>[];
    for (var i = 0; i < linea.cantidad; i++) {
      out.add(_UnidadFila(
        nombre: nombre,
        importeUnitarioTtc: pvp,
        opcionesConSuplemento: opciones,
      ));
    }
  }
  return out;
}

/// Pantalla de reparto: columna izquierda productos (1 fila/unidad), asignación por comensal.
class RepartoComensalesScreen extends StatefulWidget {
  final int idMesa;
  final List<LineaPedido> lineasPedido;

  const RepartoComensalesScreen({
    super.key,
    required this.idMesa,
    required this.lineasPedido,
  });

  @override
  State<RepartoComensalesScreen> createState() =>
      _RepartoComensalesScreenState();
}

class _RepartoComensalesScreenState extends State<RepartoComensalesScreen> {
  static const _padListaH = EdgeInsets.fromLTRB(16, 8, 6, 8);
  static const _padPieH = EdgeInsets.fromLTRB(16, 4, 6, 6);
  static const _anchoColNombre = 120.0;
  static const _anchoColPrecio = 50.0;

  /// Radio del thumb del slider; las columnas se alinean con su recorrido.
  static const _sliderThumbRadius = 12.0;

  List<_UnidadFila> _filas = [];
  List<int> _asignacion = [];
  bool _expansionCalculada = false;
  int _numComensales = 2;
  final List<String> _nombresComensales = ['Comensal 1', 'Comensal 2'];
  final List<bool> _restoComensal = [false, false];
  bool _impresorasSolicitadas = false;
  final List<DropdownMenuItem<String?>> _itemsImpresora = [
    const DropdownMenuItem<String?>(
      value: null,
      child: Text('Impresora de tickets…'),
    ),
  ];
  String? _destinoImpresora;
  bool _imprimiendo = false;

  final ScrollController _scrollLista = ScrollController();
  final GlobalKey _keyTutorialComensales = GlobalKey();
  final GlobalKey _keyTutorialComensal1 = GlobalKey();
  final GlobalKey _keyTutorialProducto = GlobalKey();
  final GlobalKey _keyTutorialResto = GlobalKey();
  final GlobalKey _keyTutorialTotales = GlobalKey();
  bool _tutorialScrolledForResto = false;

  @override
  void initState() {
    super.initState();
    // Esta pantalla se usa mejor en apaisado en móvil.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _inicializarContenido());
  }

  @override
  void dispose() {
    _scrollLista.dispose();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  Future<void> _scrollListaAlFinal() async {
    if (!_scrollLista.hasClients) return;
    await _scrollLista.animateTo(
      _scrollLista.position.maxScrollExtent,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
  }

  void _resetTutorialReparto() {
    _tutorialScrolledForResto = false;
  }

  Widget _bloqueTextoTutorial(String titulo, String cuerpo) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          cuerpo,
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
      ],
    );
  }

  List<TargetFocus> _targetsTutorialReparto() {
    final targets = <TargetFocus>[
      TargetFocus(
        identify: 'reparto_comensales',
        keyTarget: _keyTutorialComensales,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (_, __) => _bloqueTextoTutorial(
              'Número de comensales',
              'Pulsa − y + para ajustar cuántas personas hay en la mesa.',
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'reparto_nombre_comensal',
        keyTarget: _keyTutorialComensal1,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (_, __) => _bloqueTextoTutorial(
              'Nombre del comensal',
              'Toca el botón de cada comensal (por ejemplo Comensal 1) '
                  'para poner su nombre y reconocerlo mejor en el reparto.',
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'reparto_producto',
        keyTarget: _keyTutorialProducto,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (_, __) => _bloqueTextoTutorial(
              'Asignar en exclusiva',
              'En cada producto, arrastra el control hasta el comensal '
                  'que lo consumió. Si queda en «Sin asignar», sigue pendiente.',
            ),
          ),
        ],
      ),
    ];

    if (!_todoAsignadoAComensal) {
      targets.add(
        TargetFocus(
          identify: 'reparto_resto',
          keyTarget: _keyTutorialResto,
          shape: ShapeLightFocus.RRect,
          radius: 8,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (_, __) {
                if (!_tutorialScrolledForResto) {
                  _tutorialScrolledForResto = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollListaAlFinal();
                  });
                }
                return _bloqueTextoTutorial(
                  'Repartir el resto a medias',
                  'Desplázate hasta aquí cuando queden productos sin asignar. '
                      'Marca uno o varios comensales para repartir el importe '
                      'pendiente entre ellos a partes iguales.',
                );
              },
            ),
          ],
        ),
      );
    }

    targets.add(
      TargetFocus(
        identify: 'reparto_totales',
        keyTarget: _keyTutorialTotales,
        shape: ShapeLightFocus.RRect,
        radius: 8,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (_, __) => _bloqueTextoTutorial(
              'Totales por comensal',
              'Aquí ves lo pendiente y el importe asignado a cada comensal. '
                  'Cuando todo esté repartido, podrás imprimir el ticket.',
            ),
          ),
        ],
      ),
    );

    return targets;
  }

  void _iniciarTutorialReparto() {
    if (!_expansionCalculada || _filas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Necesitas productos en el pedido para ver el tutorial',
          ),
        ),
      );
      return;
    }
    _resetTutorialReparto();
    TutorialCoachMark(
      targets: _targetsTutorialReparto(),
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      paddingFocus: 8,
      textSkip: 'Omitir',
      onFinish: _resetTutorialReparto,
      onSkip: () {
        _resetTutorialReparto();
        return true;
      },
    ).show(context: context);
  }

  void _inicializarContenido() {
    if (!mounted || _expansionCalculada) return;
    final catalogo = context.read<CatalogoProvider>();
    final filas = _expandirUnidades(widget.lineasPedido, catalogo);
    setState(() {
      _filas = filas;
      _asignacion = List<int>.filled(filas.length, 0);
      _expansionCalculada = true;
    });
    if (!_impresorasSolicitadas) {
      _impresorasSolicitadas = true;
      _cargarOpcionesImpresora();
    }
  }

  Future<void> _cargarOpcionesImpresora() async {
    final catalogo = context.read<CatalogoProvider>();
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString('bt_printer_mac') ?? '';
    final nombreBt = prefs.getString('bt_printer_name') ?? '';

    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Impresora de tickets…'),
      ),
    ];

    if (mac.isNotEmpty) {
      final label = nombreBt.isNotEmpty ? 'Bluetooth ($nombreBt)' : 'Bluetooth';
      items.add(DropdownMenuItem<String?>(value: 'bt', child: Text(label)));
    }

    final sunmi = await SunmiService.dispositivoTieneImpresoraSunmiIntegrada();
    if (sunmi && mounted) {
      items.add(
        const DropdownMenuItem<String?>(
          value: 'sunmi',
          child: Text('SUNMI (integrada)'),
        ),
      );
    }

    for (final imp in catalogo.impresoras) {
      final ip = imp.ip?.trim().toLowerCase() ?? '';
      if (ip.isEmpty || ip == 'bluetooth') continue;
      if (imp.puerto <= 0) continue;
      final id = 'tcp:$ip:${imp.puerto}';
      items.add(
        DropdownMenuItem<String?>(
          value: id,
          child: Text('${imp.nombre} ($ip:${imp.puerto})'),
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _itemsImpresora
        ..clear()
        ..addAll(items);
      if (_destinoImpresora != null &&
          !_itemsImpresora.any((e) => e.value == _destinoImpresora)) {
        _destinoImpresora = null;
      }
    });
  }

  void _cambiarNumComensales(int delta) {
    final nuevo = _numComensales + delta;
    if (nuevo < 2) return;
    setState(() {
      if (nuevo < _numComensales) {
        for (var i = 0; i < _asignacion.length; i++) {
          if (_asignacion[i] > nuevo) {
            _asignacion[i] = 0;
          }
        }
        if (_nombresComensales.length > nuevo) {
          _nombresComensales.removeRange(nuevo, _nombresComensales.length);
        }
        if (_restoComensal.length > nuevo) {
          _restoComensal.removeRange(nuevo, _restoComensal.length);
        }
      } else if (nuevo > _numComensales) {
        for (var n = _nombresComensales.length + 1; n <= nuevo; n++) {
          _nombresComensales.add('Comensal $n');
          _restoComensal.add(false);
        }
      }
      _numComensales = nuevo;
    });
  }

  String _nombreComensal(int c) {
    if (c <= 0) return '—';
    final i = c - 1;
    if (i < _nombresComensales.length) {
      final nombre = _nombresComensales[i].trim();
      if (nombre.isNotEmpty) return nombre;
    }
    return 'Comensal $c';
  }

  Future<void> _editarNombreComensal(int c) async {
    final i = c - 1;
    if (i < 0 || i >= _nombresComensales.length) return;
    final ancho = MediaQuery.sizeOf(context).width;
    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => _DialogEditarNombreComensal(
        nombreInicial: _nombresComensales[i],
        ancho: ancho,
      ),
    );
    if (!mounted || nuevo == null) return;
    setState(() {
      _nombresComensales[i] = nuevo.isEmpty ? 'Comensal $c' : nuevo;
    });
  }

  double _importePendienteProductos() {
    var sum = 0.0;
    for (var i = 0; i < _filas.length; i++) {
      if (_asignacion[i] == 0) {
        sum = redondearMoneda(sum + _filas[i].importeUnitarioTtc);
      }
    }
    return sum;
  }

  List<int> _comensalesRestoSeleccionados() {
    final out = <int>[];
    for (var c = 1; c <= _numComensales; c++) {
      final i = c - 1;
      if (i < _restoComensal.length && _restoComensal[i]) out.add(c);
    }
    return out;
  }

  void _limpiarRestoSiNoAplica() {
    if (!_todoAsignadoAComensal) return;
    for (var i = 0; i < _restoComensal.length; i++) {
      _restoComensal[i] = false;
    }
  }

  List<double> _totalesPorColumna() {
    final cols = _numComensales + 1;
    final tot = List<double>.filled(cols, 0);
    for (var i = 0; i < _filas.length; i++) {
      final col = _asignacion[i].clamp(0, _numComensales);
      tot[col] = redondearMoneda(tot[col] + _filas[i].importeUnitarioTtc);
    }
    final pendiente = tot[0];
    final seleccionados = _comensalesRestoSeleccionados();
    if (pendiente > 0 && seleccionados.isNotEmpty) {
      final n = seleccionados.length;
      var acumulado = 0.0;
      for (var i = 0; i < n; i++) {
        final c = seleccionados[i];
        final parte = i == n - 1
            ? redondearMoneda(pendiente - acumulado)
            : redondearMoneda(pendiente / n);
        tot[c] = redondearMoneda(tot[c] + parte);
        acumulado = redondearMoneda(acumulado + parte);
      }
      tot[0] = 0;
    }
    return tot;
  }

  bool get _todoAsignadoAComensal =>
      _filas.isNotEmpty &&
      _asignacion.length == _filas.length &&
      _asignacion.every((a) => a >= 1);

  bool get _repartoCompleto {
    if (_filas.isEmpty) return false;
    return _totalesPorColumna()[0] < 0.005;
  }

  String get _tooltipImprimir {
    if (_imprimiendo) return 'Enviando al ticket…';
    if (_filas.isEmpty) return 'No hay productos en el pedido';
    if (!_repartoCompleto) {
      return 'Asigna todos los productos o reparte el resto pendiente';
    }
    return 'Imprimir ticket de reparto';
  }

  List<String> _lineasParaTicket() {
    final buf = <String>[];
    final fecha = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    buf.add('REPARTO COMENSALES');
    buf.add('Mesa ${widget.idMesa}  $fecha');
    buf.add('=' * 32);
    final tot = _totalesPorColumna();
    buf.add('Sin asignar:     ${tot[0].toStringAsFixed(2)} Eur');
    for (var c = 1; c <= _numComensales; c++) {
      buf.add('${_nombreComensal(c)}:     ${tot[c].toStringAsFixed(2)} Eur');
    }
    buf.add('-' * 32);
    for (var i = 0; i < _filas.length; i++) {
      final a = _asignacion[i];
      final etiqueta = a == 0 ? '—' : _nombreComensal(a);
      final f = _filas[i];
      var detalle = f.nombre;
      if (f.opcionesConSuplemento.isNotEmpty) {
        detalle = '$detalle (${f.opcionesConSuplemento.join(', ')})';
      }
      buf.add(
        '$detalle  ${f.importeUnitarioTtc.toStringAsFixed(2)} Eur  -> $etiqueta',
      );
    }
    final pendiente = _importePendienteProductos();
    final restoSel = _comensalesRestoSeleccionados();
    if (pendiente > 0 && restoSel.isNotEmpty) {
      final nombres = restoSel.map(_nombreComensal).join(', ');
      buf.add(
        'Resto  ${pendiente.toStringAsFixed(2)} Eur  -> $nombres (igual)',
      );
    }
    buf.add('=' * 32);
    return buf;
  }

  Future<void> _imprimir() async {
    final destino = _destinoImpresora;
    if (destino == null || destino.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una impresora de tickets')),
      );
      return;
    }
    if (_filas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay líneas para imprimir')),
      );
      return;
    }
    if (!_repartoCompleto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Asigna cada producto o reparte el resto entre comensales',
          ),
        ),
      );
      return;
    }
    setState(() => _imprimiendo = true);
    final msg = await SunmiService.imprimirTextoTicket(
      lineas: _lineasParaTicket(),
      destino: destino,
    );
    if (!mounted) return;
    setState(() => _imprimiendo = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.isEmpty ? 'Ticket enviado' : msg),
        backgroundColor: msg.isEmpty ? Colors.green[800] : Colors.red[900],
      ),
    );
  }

  /// Misma rejilla que el slider: nombre | N+1 columnas | precio.
  Widget _filaRejillaAsignacion({
    required Widget columnaIzquierda,
    required Widget zonaCentral,
    Widget? columnaPrecio,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
  }) {
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        SizedBox(width: _anchoColNombre, child: columnaIzquierda),
        Expanded(child: zonaCentral),
        SizedBox(
          width: _anchoColPrecio,
          child: columnaPrecio ?? const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Posición horizontal del centro de cada valor del slider (0…N).
  double _centroColumnaSlider(double anchoZona, int indice) {
    const trackLeft = _sliderThumbRadius;
    final trackWidth = anchoZona - 2 * _sliderThumbRadius;
    return trackLeft + trackWidth * (indice / _numComensales);
  }

  /// Hueco hasta el vecino o el borde de la zona (para centrar sin desplazar).
  double _huecoHastaVecino(double anchoZona, int indice) {
    final center = _centroColumnaSlider(anchoZona, indice);
    final espacioIzq = indice > 0
        ? center - _centroColumnaSlider(anchoZona, indice - 1)
        : center;
    final espacioDer = indice < _numComensales
        ? _centroColumnaSlider(anchoZona, indice + 1) - center
        : anchoZona - center;
    return min(espacioIzq, espacioDer);
  }

  /// Ancho máximo para que el centro de la celda coincida con el thumb.
  double _anchoCeldaEnPosicion(
    double anchoZona,
    int indice, {
    double? anchoPreferido,
    double factor = 0.9,
  }) {
    final maxCentrado = 2 * _huecoHastaVecino(anchoZona, indice);
    if (anchoPreferido != null) {
      return min(anchoPreferido, maxCentrado);
    }
    return (maxCentrado * factor).clamp(32.0, 88.0);
  }

  /// Ancho mínimo de cada celda de totales (más ancha que el checkbox): igual que
  /// el paso entre divisiones del slider, para que "Pendiente" y el último
  /// comensal no queden más estrechos que el centro.
  double _anchoMinimoCeldaTotales(double anchoZona) {
    final trackWidth = anchoZona - 2 * _sliderThumbRadius;
    if (_numComensales <= 0) return trackWidth.clamp(56.0, 96.0);
    final paso = trackWidth / _numComensales;
    return paso.clamp(52.0, 92.0);
  }

  /// Coloca hijos centrados en las mismas X que los thumbs del slider.
  Widget _zonaPosicionesComensales({
    required List<Widget?> elementos,
    required double alto,
    double? anchoElemento,
    double factorAncho = 0.9,
    bool anchuraAmpliaTotales = false,
  }) {
    assert(elementos.length == _numComensales + 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final minTotales =
            anchuraAmpliaTotales ? _anchoMinimoCeldaTotales(w) : null;
        final hijos = <Widget>[];
        for (var c = 0; c < elementos.length; c++) {
          final el = elementos[c];
          if (el == null) continue;
          final center = _centroColumnaSlider(w, c);
          var ew = _anchoCeldaEnPosicion(
            w,
            c,
            anchoPreferido: anchoElemento,
            factor: factorAncho,
          );
          if (minTotales != null) {
            ew = max(ew, minTotales);
          }
          hijos.add(
            Positioned(
              left: center - ew / 2,
              width: ew,
              top: 0,
              bottom: 0,
              child: Center(child: el),
            ),
          );
        }
        return SizedBox(
          height: alto,
          width: w,
          child: Stack(
            clipBehavior: Clip.none,
            children: hijos,
          ),
        );
      },
    );
  }

  SliderThemeData _temaSliderAsignacion() {
    return SliderTheme.of(context).copyWith(
      trackHeight: 8,
      trackShape: const RoundedRectSliderTrackShape(),
      activeTrackColor: const Color(0xFF3D3D3D),
      inactiveTrackColor: const Color(0xFF3D3D3D),
      secondaryActiveTrackColor: const Color(0xFF3D3D3D),
      activeTickMarkColor: const Color(0xFF3D3D3D),
      inactiveTickMarkColor: const Color(0xFF3D3D3D),
      thumbColor: AppTheme.colorPrimario,
      overlayColor: Colors.transparent,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: _sliderThumbRadius,
      ),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    );
  }

  Widget _filaUnidad(int i) {
    String fmtEuro(double v) => '${v.toStringAsFixed(2)} €';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _filaRejillaAsignacion(
        crossAxisAlignment: CrossAxisAlignment.center,
        columnaIzquierda: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _filas[i].nombre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            ..._filas[i].opcionesConSuplemento.map(
                  (op) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '▸ $op',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.colorTextoGris,
                      ),
                    ),
                  ),
                ),
          ],
        ),
        zonaCentral: KeyedSubtree(
          key: i == 0 ? _keyTutorialProducto : null,
          child: SliderTheme(
            data: _temaSliderAsignacion(),
            child: Slider(
              padding: EdgeInsets.zero,
              value:
                  _asignacion[i].toDouble().clamp(0, _numComensales.toDouble()),
              min: 0,
              max: _numComensales.toDouble(),
              divisions: _numComensales,
              label: _etiquetaAsignacion(_asignacion[i]),
              onChanged: (v) {
                setState(() {
                  _asignacion[i] = v.round();
                  _limpiarRestoSiNoAplica();
                });
              },
            ),
          ),
        ),
        columnaPrecio: Text(
          fmtEuro(_filas[i].importeUnitarioTtc),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _filaResto(double pendiente) {
    String fmtEuro(double v) => '${v.toStringAsFixed(2)} €';
    final habilitado = !_todoAsignadoAComensal && pendiente > 0;

    final elementos = <Widget?>[
      null,
      for (var c = 1; c <= _numComensales; c++)
        Checkbox(
          value: c - 1 < _restoComensal.length ? _restoComensal[c - 1] : false,
          onChanged: habilitado
              ? (v) {
                  setState(() {
                    _restoComensal[c - 1] = v ?? false;
                  });
                }
              : null,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
    ];

    return Padding(
      key: _keyTutorialResto,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Opacity(
        opacity: habilitado ? 1 : 0.35,
        child: _filaRejillaAsignacion(
          columnaIzquierda: Text(
            'Resto a medias',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: habilitado ? Colors.white : Colors.white38,
            ),
          ),
          zonaCentral: _zonaPosicionesComensales(
            elementos: elementos,
            alto: 40,
            anchoElemento: 24,
          ),
          columnaPrecio: Text(
            fmtEuro(pendiente),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: habilitado ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }

  Widget _celdaTotalComensal(int c, List<double> totCols) {
    String fmtEuro(double v) => '${v.toStringAsFixed(2)} €';
    final celda = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
      decoration: BoxDecoration(
        color: c == 0
            ? Colors.grey[800]
            : AppTheme.colorPrimario.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c == 0)
            const Text(
              'Pendiente',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _nombreComensal(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ],
            ),
          Text(
            fmtEuro(totCols[c]),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );

    if (c == 0) return celda;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _editarNombreComensal(c),
        borderRadius: BorderRadius.circular(6),
        child: celda,
      ),
    );
  }

  Widget _filaTotales(List<double> totCols) {
    return KeyedSubtree(
      key: _keyTutorialTotales,
      child: _filaRejillaAsignacion(
        columnaIzquierda: const SizedBox.shrink(),
        zonaCentral: _zonaPosicionesComensales(
          alto: 50,
          anchuraAmpliaTotales: true,
          elementos: [
            for (var c = 0; c <= _numComensales; c++)
              if (c == 1)
                KeyedSubtree(
                  key: _keyTutorialComensal1,
                  child: _celdaTotalComensal(c, totCols),
                )
              else
                _celdaTotalComensal(c, totCols),
          ],
        ),
      ),
    );
  }

  Widget _pieFijo(List<double> totCols) {
    return Material(
      elevation: 8,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          Padding(
            padding: _padPieH,
            child: _filaTotales(totCols),
          ),
        ],
      ),
    );
  }

  int get _itemCountListaProductos {
    if (_filas.isEmpty) return 0;
    return _filas.length + (_todoAsignadoAComensal ? 0 : 1);
  }

  Widget _buildControlesSuperiores(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final estrecho = ancho < 560;

    final filaComensales = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _iniciarTutorialReparto,
          tooltip: 'Cómo usar el reparto',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Text(
            '?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Text(
          'Comensales',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(width: 12),
        KeyedSubtree(
          key: _keyTutorialComensales,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                onPressed:
                    _numComensales > 2 ? () => _cambiarNumComensales(-1) : null,
                style: IconButton.styleFrom(
                  backgroundColor:
                      _numComensales == 2 ? Colors.grey.shade700 : null,
                  foregroundColor: _numComensales == 2 ? Colors.white54 : null,
                ),
                icon: const Icon(Icons.remove),
                tooltip: 'Menos comensales',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$_numComensales',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => _cambiarNumComensales(1),
                icon: const Icon(Icons.add),
                tooltip: 'Más comensales',
              ),
            ],
          ),
        ),
      ],
    );

    final dropdown = DropdownButtonFormField<String?>(
      isExpanded: true,
      initialValue: _destinoImpresora,
      decoration: const InputDecoration(
        labelText: 'Impresora',
        isDense: true,
      ),
      items: _itemsImpresora,
      onChanged:
          _imprimiendo ? null : (v) => setState(() => _destinoImpresora = v),
    );

    final botonImprimir = Tooltip(
      message: _tooltipImprimir,
      child: FilledButton(
        onPressed: (_imprimiendo || !_repartoCompleto) ? null : _imprimir,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.all(12),
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: _imprimiendo
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.print, size: 26),
      ),
    );

    if (estrecho) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filaComensales,
          const SizedBox(height: 12),
          dropdown,
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: botonImprimir),
        ],
      );
    }

    return Row(
      children: [
        filaComensales,
        const Spacer(),
        SizedBox(width: 220, child: dropdown),
        const SizedBox(width: 8),
        botonImprimir,
      ],
    );
  }

  Widget _contenidoScrollable(double pendiente) {
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _buildControlesSuperiores(context),
            ),
            const Divider(height: 1),
          ],
        ),
      ),
    ];

    if (!_expansionCalculada) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (_filas.isEmpty) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'No hay productos en el pedido',
              style: TextStyle(color: AppTheme.colorTextoGris),
            ),
          ),
        ),
      );
    } else {
      slivers.add(
        SliverPadding(
          padding: _padListaH,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index < _filas.length) return _filaUnidad(index);
                return _filaResto(pendiente);
              },
              childCount: _itemCountListaProductos,
            ),
          ),
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollLista,
      slivers: slivers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totCols = _totalesPorColumna();
    final pendiente = _importePendienteProductos();
    final hayFilas = _expansionCalculada && _filas.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _contenidoScrollable(pendiente)),
            if (hayFilas) _pieFijo(totCols),
          ],
        ),
      ),
    );
  }

  String _etiquetaAsignacion(int a) {
    if (a <= 0) return 'Sin asignar';
    return _nombreComensal(a);
  }
}

class _DialogEditarNombreComensal extends StatefulWidget {
  final String nombreInicial;
  final double ancho;

  const _DialogEditarNombreComensal({
    required this.nombreInicial,
    required this.ancho,
  });

  @override
  State<_DialogEditarNombreComensal> createState() =>
      _DialogEditarNombreComensalState();
}

class _DialogEditarNombreComensalState
    extends State<_DialogEditarNombreComensal> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final texto = widget.nombreInicial;
    _controller = TextEditingController.fromValue(
      TextEditingValue(
        text: texto,
        selection: TextSelection(baseOffset: 0, extentOffset: texto.length),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final len = _controller.text.length;
      _controller.value = _controller.value.copyWith(
        selection: TextSelection(baseOffset: 0, extentOffset: len),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _guardar() {
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.colorTarjeta,
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: SizedBox(
          width: widget.ancho - 48,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    hintText: 'Ej. Juan, María…',
                    counterText: '',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _guardar(),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: _guardar,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
