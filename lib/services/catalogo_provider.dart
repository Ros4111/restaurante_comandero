// lib/services/catalogo_provider.dart
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../utils/busqueda_texto.dart';

class CatalogoProvider extends ChangeNotifier {
  List<Categoria> categorias = [];
  List<Producto> productos = [];
  List<GrupoOpciones> grupos = [];
  List<OpcionProducto> opciones = [];
  List<Impresora> impresoras = [];

  bool get loaded => categorias.isNotEmpty;

  Map<int, Producto> _productoPorId = {};
  Map<int, String> _nombreNormPorId = {};
  Map<int, String> _filtroNormPorId = {};
  Map<int, List<Categoria>> _categoriasPorPadre = {};
  Map<int, List<Producto>> _productosPorCategoria = {};
  Map<int, List<GrupoOpciones>> _gruposPorProducto = {};
  Map<(int, int), List<OpcionProducto>> _opcionesPorProductoGrupo = {};
  Map<int, List<({OpcionProducto opcion, String nombreNorm})>>
      _opcionesNoPredPorProducto = {};

  Producto? productoPorId(int id) => _productoPorId[id];

  bool productoPedible(Producto p) => p.disponible && !p.agotado;

  void setAgotadoLocal(int idProducto, bool agotado) {
    final idx = productos.indexWhere((p) => p.id == idProducto);
    if (idx < 0) return;
    final p = productos[idx];
    productos[idx] = Producto(
      id: p.id,
      nombreProductoPantalla: p.nombreProductoPantalla,
      idCategoria: p.idCategoria,
      textoImprimirBarraCocina: p.textoImprimirBarraCocina,
      textoImprimirCliente: p.textoImprimirCliente,
      filtro: p.filtro,
      idImpresora: p.idImpresora,
      disponible: p.disponible,
      agotado: agotado,
      orden: p.orden,
      baseImponible: p.baseImponible,
      porcentajeIVA: p.porcentajeIVA,
    );
    _reconstruirIndices();
    notifyListeners();
  }

  void notificarCambios() {
    _reconstruirIndices();
    notifyListeners();
  }

  void cargar(Map<String, dynamic> data) {
    categorias =
        (data['categorias'] as List).map((j) => Categoria.fromJson(j)).toList();
    productos =
        (data['productos'] as List).map((j) => Producto.fromJson(j)).toList();
    grupos =
        (data['grupos'] as List).map((j) => GrupoOpciones.fromJson(j)).toList();
    opciones = (data['opciones'] as List)
        .map((j) => OpcionProducto.fromJson(j))
        .toList();
    final impRaw = data['impresoras'];
    impresoras = impRaw is List
        ? impRaw
            .map((j) => Impresora.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList()
        : [];
    _reconstruirIndices();
    notifyListeners();
  }

  void _reconstruirIndices() {
    _productoPorId = {};
    _nombreNormPorId = {};
    _filtroNormPorId = {};
    _categoriasPorPadre = {};
    _productosPorCategoria = {};
    _gruposPorProducto = {};
    _opcionesPorProductoGrupo = {};
    _opcionesNoPredPorProducto = {};

    for (final p in productos) {
      _productoPorId[p.id] = p;
      _nombreNormPorId[p.id] =
          normalizarTextoBusqueda(p.nombreProductoPantalla);
      _filtroNormPorId[p.id] = normalizarTextoBusqueda(p.filtro);
      if (p.disponible) {
        (_productosPorCategoria[p.idCategoria] ??= []).add(p);
      }
    }
    for (final lista in _productosPorCategoria.values) {
      lista.sort(_cmpProducto);
    }

    for (final c in categorias) {
      if (!c.disponible) continue;
      (_categoriasPorPadre[c.idPadre] ??= []).add(c);
    }
    for (final lista in _categoriasPorPadre.values) {
      lista.sort((a, b) => a.orden.compareTo(b.orden));
    }

    final gruposIdsPorProducto = <int, Set<int>>{};
    for (final o in opciones) {
      if (!o.disponible) continue;
      final key = (o.idProducto, o.idGrupo);
      (_opcionesPorProductoGrupo[key] ??= []).add(o);
      if (!o.predeterminado) {
        (_opcionesNoPredPorProducto[o.idProducto] ??= []).add(
          (
            opcion: o,
            nombreNorm: normalizarTextoBusqueda(o.nombreOpcion),
          ),
        );
      }
      (gruposIdsPorProducto[o.idProducto] ??= {}).add(o.idGrupo);
    }
    for (final lista in _opcionesPorProductoGrupo.values) {
      lista.sort(_cmpOpcion);
    }
    for (final lista in _opcionesNoPredPorProducto.values) {
      lista.sort((a, b) => _cmpOpcion(a.opcion, b.opcion));
    }
    for (final entry in gruposIdsPorProducto.entries) {
      final ids = entry.value;
      _gruposPorProducto[entry.key] = grupos
          .where((g) => ids.contains(g.id) && g.disponible)
          .toList()
        ..sort((a, b) => a.orden.compareTo(b.orden));
    }
  }

  static int _cmpProducto(Producto a, Producto b) {
    final co = a.orden.compareTo(b.orden);
    if (co != 0) return co;
    return a.nombreProductoPantalla
        .toLowerCase()
        .compareTo(b.nombreProductoPantalla.toLowerCase());
  }

  static int _cmpOpcion(OpcionProducto a, OpcionProducto b) {
    final co = a.orden.compareTo(b.orden);
    if (co != 0) return co;
    return a.nombreOpcion.toLowerCase().compareTo(b.nombreOpcion.toLowerCase());
  }

  List<Categoria> categoriasHijo(int idPadre) =>
      _categoriasPorPadre[idPadre] ?? const [];

  List<Producto> productosDeCategoria(int idCategoria) =>
      _productosPorCategoria[idCategoria] ?? const [];

  List<Producto> productosPorBusquedaNombre(String texto) {
    final n = normalizarTextoBusqueda(texto.trim());
    if (n.isEmpty) return const [];
    return _filtrarProductosPedido(
        (p) => (_nombreNormPorId[p.id] ?? '').contains(n));
  }

  List<Producto> productosPorBusquedaFiltro(String filtro) {
    final n = normalizarTextoBusqueda(filtro.trim());
    if (n.isEmpty) return const [];
    return _filtrarProductosPedido(
        (p) => (_filtroNormPorId[p.id] ?? '').contains(n));
  }

  /// `mm` + filtro + tokens: filtro y cada token en opción no predeterminada.
  List<Producto> productosPorBusquedaFiltroOpciones(
      String filtro, List<String> tokensOpcion) {
    final nf = normalizarTextoBusqueda(filtro.trim());
    final tokensNorm = tokensOpcion
        .map((t) => normalizarTextoBusqueda(t.trim()))
        .where((t) => t.isNotEmpty)
        .toList();
    if (nf.isEmpty || tokensNorm.isEmpty) return const [];
    return _filtrarProductosPedido((p) {
      if (!(_filtroNormPorId[p.id] ?? '').contains(nf)) return false;
      for (final token in tokensNorm) {
        if (!_productoTieneOpcionNoPredeterminada(p.id, token)) return false;
      }
      return true;
    });
  }

  bool _productoTieneOpcionNoPredeterminada(int idProducto, String tokenNorm) {
    final lista = _opcionesNoPredPorProducto[idProducto];
    if (lista == null) return false;
    for (final e in lista) {
      if (e.nombreNorm.contains(tokenNorm)) return true;
    }
    return false;
  }

  List<Producto> _filtrarProductosPedido(bool Function(Producto) coincide) {
    final out = <Producto>[];
    for (final p in productos) {
      if (!p.disponible) continue;
      if (!coincide(p)) continue;
      out.add(p);
    }
    out.sort(_cmpProducto);
    return out;
  }

  /// Predeterminados del producto, sustituyendo grupos que coincidan con [tokens].
  Map<int, OpcionElegida> opcionesElegidasConTokensBusqueda(
      Producto p, List<String> tokens) {
    final out = <int, OpcionElegida>{};
    for (final g in gruposDeProducto(p.id)) {
      final opts = opcionesDeGrupo(p.id, g.id);
      final def =
          opts.where((o) => o.predeterminado).firstOrNull ?? opts.firstOrNull;
      if (def != null) {
        out[g.id] = OpcionElegida(
          nombre: def.nombreOpcion,
          predeterminado: def.predeterminado,
        );
      }
    }

    final candidatasIndex = _opcionesNoPredPorProducto[p.id] ?? const [];
    final gruposUsados = <int>{};
    for (final raw in tokens) {
      final n = normalizarTextoBusqueda(raw.trim());
      if (n.isEmpty) continue;
      final candidatas = candidatasIndex
          .where((e) => e.nombreNorm.contains(n))
          .map((e) => e.opcion)
          .toList();
      if (candidatas.isEmpty) continue;

      OpcionProducto? elegida;
      for (final c in candidatas) {
        if (!gruposUsados.contains(c.idGrupo)) {
          elegida = c;
          break;
        }
      }
      elegida ??= candidatas.first;
      gruposUsados.add(elegida.idGrupo);
      out[elegida.idGrupo] = OpcionElegida(
        nombre: elegida.nombreOpcion,
        predeterminado: elegida.predeterminado,
      );
    }
    return out;
  }

  List<GrupoOpciones> gruposDeProducto(int idProducto) =>
      _gruposPorProducto[idProducto] ?? const [];

  List<OpcionProducto> opcionesDeGrupo(int idProducto, int idGrupo) =>
      _opcionesPorProductoGrupo[(idProducto, idGrupo)] ?? const [];

  OpcionProducto? opcionPorNombre(int idProducto, int idGrupo, String nombre) {
    for (final o in opcionesDeGrupo(idProducto, idGrupo)) {
      if (o.nombreOpcion == nombre) return o;
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────

class SesionProvider extends ChangeNotifier {
  Usuario? _usuario;
  List<Usuario> usuarios = [];

  Usuario? get usuario => _usuario;
  bool get loggedIn => _usuario != null;

  bool get esSupervisor =>
      _usuario?.permisos == 'supervisor' || _usuario?.permisos == 'admin';
  bool get esAdmin => _usuario?.permisos == 'admin';

  /// Solo el usuario id 1 gestiona el CRUD de usuarios.
  bool get esUsuarioPrincipal => _usuario?.id == 1;

  bool get esServicio => _usuario?.permisos == 'servicio';

  bool get esPantallaPendientesServir {
    if ((_usuario?.impresora ?? 0) > 0) return true;
    final p = _usuario?.permisos;
    return p == 'servicio' || p == 'cocina' || p == 'barra';
  }

  String get tituloPendientesServir {
    switch (_usuario?.permisos) {
      case 'cocina':
        return 'Cocina — pendientes';
      case 'barra':
        return 'Barra — pendientes';
      default:
        return 'Pendientes de servir';
    }
  }

  String? nombreUsuario(int? idUsuario) {
    if (idUsuario == null) return null;
    try {
      return usuarios.firstWhere((u) => u.id == idUsuario).nombre;
    } catch (_) {
      return null;
    }
  }

  void setUsuarios(List<Usuario> lista) {
    usuarios = lista;
    notifyListeners();
  }

  void login(Usuario u) {
    _usuario = u;
    notifyListeners();
  }

  void logout() {
    _usuario = null;
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────

class MesaProvider extends ChangeNotifier {
  int? idPedido;
  int? idMesa;
  bool bloqueadoPorMi = false;
  bool soloLectura = false;
  String? nombreBloqueador;
  String nombreCliente = '';
  /// Copia de `hora_ultima_accion` del servidor al cargar (control de concurrencia).
  String? horaUltimaAccionRef;
  List<LineaPedido> lineas = [];
  List<LineaPedido> _lineasOriginales = [];

  // Para rastrear borrados
  final List<int> _lineasBorradas = [];

  bool get tieneNuevas => lineas.any((l) => l.esNuevo);

  bool get hayCambiosSinGuardar =>
      _lineasBorradas.isNotEmpty ||
      lineas.any((l) => l.esNuevo || l.editada || l.moverAMesa != null);

  void cargar(int pedido, int mesa, Map<String, dynamic> data,
      {required bool tengoBloqueo, String? bloqueador}) {
    idPedido = pedido;
    idMesa = mesa;
    bloqueadoPorMi = tengoBloqueo;
    soloLectura = !tengoBloqueo;
    nombreBloqueador = bloqueador;
    final cabecera = data['cabecera'];
    nombreCliente = (cabecera is Map && cabecera['nombre_cliente'] != null)
        ? cabecera['nombre_cliente'].toString()
        : '';
    horaUltimaAccionRef = (cabecera is Map)
        ? cabecera['hora_ultima_accion']?.toString()
        : null;
    _lineasBorradas.clear();

    final lista = (data['detalles'] as List? ?? [])
        .map((j) => LineaPedido.fromJson(j))
        .toList();
    lista.sort((a, b) => a.orden.compareTo(b.orden));
    lineas = lista;
    _lineasOriginales = lista.map((l) => l.copyWith()).toList();
    notifyListeners();
  }

  void setNombreCliente(String v) {
    final nuevo = v;
    if (nuevo == nombreCliente) return;
    nombreCliente = nuevo;
    notifyListeners();
  }

  void agregarLinea(LineaPedido linea) {
    linea.orden = (lineas.isEmpty
            ? 0
            : lineas.map((l) => l.orden).reduce((a, b) => a > b ? a : b)) +
        1;
    lineas.add(linea);
    notifyListeners();
  }

  void insertarLineaDespues(LineaPedido referencia, LineaPedido linea) {
    final idx = lineas.indexOf(referencia);
    if (idx < 0) {
      agregarLinea(linea);
      return;
    }
    final ordenRef = lineas[idx].orden;
    linea.orden = ordenRef + 1;
    for (var i = idx + 1; i < lineas.length; i++) {
      if (lineas[i].orden <= ordenRef) continue;
      lineas[i].orden++;
    }
    lineas.insert(idx + 1, linea);
    notifyListeners();
  }

  void eliminarLinea(LineaPedido linea) {
    if (linea.idLinea != null) {
      _lineasBorradas.add(linea.idLinea!);
    }
    lineas.remove(linea);
    notifyListeners();
  }

  void modificarLinea(
    LineaPedido linea, {
    int? cantidad,
    String? comentario,
    int? moverAMesa,
    Map<int, OpcionElegida>? opcionesElegidas,
    bool? urgente,
    bool marcarEditada = false,
  }) {
    final idx = lineas.indexOf(linea);
    if (idx < 0) return;
    lineas[idx] = linea.copyWith(
      cantidad: cantidad,
      comentario: comentario,
      moverAMesa: moverAMesa,
      opcionesElegidas: opcionesElegidas,
      urgente: urgente,
      editada: marcarEditada ? true : linea.editada,
    );
    notifyListeners();
  }

  // Construye la lista a enviar al servidor (incluye los originales borrados como ausentes)
  List<LineaPedido> lineasParaEnviar() {
    // Las líneas borradas simplemente no se incluyen — el servidor detecta los faltantes
    // Las líneas originales no modificadas se incluyen con su id_linea
    return lineas;
  }

  void forzarSoloLectura({String? bloqueador}) {
    bloqueadoPorMi = false;
    soloLectura = true;
    nombreBloqueador = bloqueador;
    notifyListeners();
  }

  void reset() {
    idPedido = null;
    idMesa = null;
    bloqueadoPorMi = false;
    soloLectura = false;
    nombreBloqueador = null;
    nombreCliente = '';
    horaUltimaAccionRef = null;
    lineas.clear();
    _lineasOriginales.clear();
    _lineasBorradas.clear();
    notifyListeners();
  }
}
