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

  void notificarCambios() => notifyListeners();

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
    notifyListeners();
  }

  List<Categoria> categoriasHijo(int idPadre) =>
      categorias.where((c) => c.idPadre == idPadre && c.disponible).toList()
        ..sort((a, b) => a.orden.compareTo(b.orden));

  List<Producto> productosDeCategoria(int idCategoria) => productos
      .where((p) => p.idCategoria == idCategoria && p.disponible)
      .toList()
    ..sort((a, b) => a.orden.compareTo(b.orden));

  /// Búsqueda en pantalla de pedido: [enFiltro] usa `Producto.filtro`; si no, nombre/id.
  List<Producto> productosPorBusquedaPedido(String texto,
      {required bool enFiltro}) {
    final needle = texto.trim();
    if (needle.isEmpty) return [];
    final n = normalizarTextoBusqueda(needle);
    if (n.isEmpty) return [];
    final out = <Producto>[];
    for (final p in productos) {
      if (!p.disponible) continue;
      if (enFiltro) {
        final f = normalizarTextoBusqueda(p.filtro);
        if (!f.contains(n)) continue;
      } else {
        final nm = normalizarTextoBusqueda(p.nombreProductoPantalla);
        if (!nm.contains(n) && !p.id.toString().contains(needle)) continue;
      }
      out.add(p);
    }
    out.sort((a, b) {
      final co = a.orden.compareTo(b.orden);
      if (co != 0) return co;
      return a.nombreProductoPantalla
          .toLowerCase()
          .compareTo(b.nombreProductoPantalla.toLowerCase());
    });
    return out;
  }

  List<GrupoOpciones> gruposDeProducto(int idProducto) {
    final idsGrupo = opciones
        .where((o) => o.idProducto == idProducto && o.disponible)
        .map((o) => o.idGrupo)
        .toSet();
    return grupos.where((g) => idsGrupo.contains(g.id) && g.disponible).toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));
  }

  List<OpcionProducto> opcionesDeGrupo(int idProducto, int idGrupo) => opciones
      .where((o) =>
          o.idProducto == idProducto && o.idGrupo == idGrupo && o.disponible)
      .toList()
    ..sort((a, b) => a.orden.compareTo(b.orden));

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
    bool marcarEditada = false,
  }) {
    final idx = lineas.indexOf(linea);
    if (idx < 0) return;
    lineas[idx] = linea.copyWith(
      cantidad: cantidad,
      comentario: comentario,
      moverAMesa: moverAMesa,
      opcionesElegidas: opcionesElegidas,
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
