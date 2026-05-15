// lib/screens/reparto_comensales_screen.dart
// Reparto del importe del pedido entre comensales (una fila por unidad).
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final suplementoTtc = pvpUnitarioDesdeBaseSinIva(
      baseSinIvaUnitaria: match.suplementoSinIva,
      porcentajeIva: producto.porcentajeIVA,
    );
    if (suplementoTtc <= 0) continue;
    final nombre = entry.value.nombre.trim();
    if (nombre.isEmpty) continue;
    out.add('$nombre +${suplementoTtc.toStringAsFixed(2)} €');
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
  static const _padPieH = EdgeInsets.fromLTRB(16, 6, 6, 10);
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
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
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
    final controller = TextEditingController(text: _nombresComensales[i]);
    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nombre comensal $c'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(
            hintText: 'Ej. Juan, María…',
            counterText: '',
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
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

  /// Coloca hijos centrados en las mismas X que los thumbs del slider.
  Widget _zonaPosicionesComensales({
    required List<Widget?> elementos,
    required double alto,
    double? anchoElemento,
    double factorAncho = 0.9,
  }) {
    assert(elementos.length == _numComensales + 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final hijos = <Widget>[];
        for (var c = 0; c < elementos.length; c++) {
          final el = elementos[c];
          if (el == null) continue;
          final center = _centroColumnaSlider(w, c);
          final ew = _anchoCeldaEnPosicion(
            w,
            c,
            anchoPreferido: anchoElemento,
            factor: factorAncho,
          );
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
        zonaCentral: SliderTheme(
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
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
              style: TextStyle(fontSize: 10, color: Colors.white54),
            )
          else
            InkWell(
              onTap: () => _editarNombreComensal(c),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Row(
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
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.edit_outlined,
                      size: 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          Text(
            fmtEuro(totCols[c]),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaTotales(List<double> totCols) {
    return _filaRejillaAsignacion(
      columnaIzquierda: const SizedBox.shrink(),
      zonaCentral: _zonaPosicionesComensales(
        alto: 54,
        elementos: [
          for (var c = 0; c <= _numComensales; c++)
            _celdaTotalComensal(c, totCols),
        ],
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
        const Text(
          'Comensales',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          onPressed:
              _numComensales > 2 ? () => _cambiarNumComensales(-1) : null,
          style: IconButton.styleFrom(
            backgroundColor: _numComensales == 2 ? Colors.grey.shade700 : null,
            foregroundColor: _numComensales == 2 ? Colors.white54 : null,
          ),
          icon: const Icon(Icons.remove),
          tooltip: 'Menos comensales',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '$_numComensales',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => _cambiarNumComensales(1),
          icon: const Icon(Icons.add),
          tooltip: 'Más comensales',
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
      child: FilledButton.icon(
        onPressed: (_imprimiendo || !_repartoCompleto) ? null : _imprimir,
        icon: _imprimiendo
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.print, size: 20),
        label: Text(_imprimiendo ? 'Enviando…' : 'Imprimir'),
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

    return CustomScrollView(slivers: slivers);
  }

  @override
  Widget build(BuildContext context) {
    final totCols = _totalesPorColumna();
    final pendiente = _importePendienteProductos();
    final hayFilas = _expansionCalculada && _filas.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reparto comensales'),
      ),
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
