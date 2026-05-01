// lib/services/catalogo_provider.dart
import 'package:flutter/foundation.dart';
import '../models/models.dart';

class CatalogoProvider extends ChangeNotifier {
  List<Categoria> categorias = [];
  List<Producto> productos = [];
  List<GrupoOpciones> grupos = [];
  List<OpcionProducto> opciones = [];
  List<Impresora> impresoras = [];

  bool get loaded => categorias.isNotEmpty;

  void cargar(Map<String, dynamic> data) {
    categorias = (data['categorias'] as List)
        .map((j) => Categoria.fromJson(j)).toList();
    productos = (data['productos'] as List)
        .map((j) => Producto.fromJson(j)).toList();
    grupos = (data['grupos'] as List)
        .map((j) => GrupoOpciones.fromJson(j)).toList();
    opciones = (data['opciones'] as List)
        .map((j) => OpcionProducto.fromJson(j)).toList();
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

  List<Producto> productosDeCategoria(int idCategoria) =>
      productos.where((p) => p.idCategoria == idCategoria && p.disponible).toList()
        ..sort((a, b) => a.orden.compareTo(b.orden));

  List<GrupoOpciones> gruposDeProducto(int idProducto) {
    final idsGrupo = opciones
        .where((o) => o.idProducto == idProducto && o.disponible)
        .map((o) => o.idGrupo)
        .toSet();
    return grupos.where((g) => idsGrupo.contains(g.id) && g.disponible).toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));
  }

  List<OpcionProducto> opcionesDeGrupo(int idProducto, int idGrupo) =>
      opciones.where((o) =>
          o.idProducto == idProducto && o.idGrupo == idGrupo && o.disponible).toList()
        ..sort((a, b) => a.orden.compareTo(b.orden));

  OpcionProducto? opcionPorNombre(int idProducto, int idGrupo, String nombre) {
    for (final o in opcionesDeGrupo(idProducto, idGrupo)) {
      if (o.nombre == nombre) return o;
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────

class SesionProvider extends ChangeNotifier {
  Usuario? _usuario;
  Usuario? get usuario => _usuario;
  bool get loggedIn => _usuario != null;

  bool get esSupervisor =>
      _usuario?.permisos == 'supervisor' || _usuario?.permisos == 'admin';
  bool get esAdmin => _usuario?.permisos == 'admin';

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
  List<LineaPedido> lineas = [];
  List<LineaPedido> _lineasOriginales = [];

  // Para rastrear borrados
  final List<int> _lineasBorradas = [];

  bool get tieneNuevas => lineas.any((l) => l.esNuevo);

  void cargar(int pedido, int mesa, Map<String, dynamic> data,
      {required bool tengoBloqueo, String? bloqueador}) {
    idPedido = pedido;
    idMesa = mesa;
    bloqueadoPorMi = tengoBloqueo;
    soloLectura = !tengoBloqueo;
    nombreBloqueador = bloqueador;
    _lineasBorradas.clear();

    final lista = (data['detalles'] as List? ?? [])
        .map((j) => LineaPedido.fromJson(j)).toList();
    lista.sort((a, b) => a.orden.compareTo(b.orden));
    lineas = lista;
    _lineasOriginales = lista.map((l) => l.copyWith()).toList();
    notifyListeners();
  }

  void agregarLinea(LineaPedido linea) {
    linea.orden = (lineas.isEmpty ? 0 : lineas.map((l) => l.orden).reduce((a, b) => a > b ? a : b)) + 1;
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

  void reset() {
    idPedido = null;
    idMesa = null;
    bloqueadoPorMi = false;
    soloLectura = false;
    nombreBloqueador = null;
    lineas.clear();
    _lineasOriginales.clear();
    _lineasBorradas.clear();
    notifyListeners();
  }
}
