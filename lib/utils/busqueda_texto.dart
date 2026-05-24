/// Normalización para búsquedas por texto (minúsculas, acentos comunes → ASCII).
String normalizarTextoBusqueda(String raw) {
  var t = raw.toLowerCase().trim();
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuuunc';
  for (var i = 0; i < from.length; i++) {
    t = t.replaceAll(from[i], to[i]);
  }
  return t;
}

/// Modo del buscador de catálogo en pantalla de pedido.
enum ModoBusquedaCatalogoPedido {
  inactiva,
  /// Sin `mm`: [Producto.nombreProductoPantalla].
  porNombre,
  /// `mm` + código: [Producto.filtro].
  porFiltro,
  /// `mm` + código + tokens: filtro y opciones no predeterminadas.
  porFiltroOpciones,
}

/// Resultado de interpretar el campo de búsqueda del catálogo.
typedef BusquedaCatalogoPedido = ({
  bool activa,
  ModoBusquedaCatalogoPedido modo,
  /// Texto para modo [ModoBusquedaCatalogoPedido.porNombre].
  String terminoNombre,
  /// Código de filtro (modos `mm`).
  String filtro,
  /// Tokens tras el filtro (modo [ModoBusquedaCatalogoPedido.porFiltroOpciones]).
  List<String> tokensOpcion,
});

const kBusquedaCatalogoPedidoInactiva = (
  activa: false,
  modo: ModoBusquedaCatalogoPedido.inactiva,
  terminoNombre: '',
  filtro: '',
  tokensOpcion: <String>[],
);

BusquedaCatalogoPedido interpretarCampoBusquedaCatalogoMm(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return kBusquedaCatalogoPedidoInactiva;

  if (t.length >= 2 && t.substring(0, 2).toLowerCase() == 'mm') {
    final rest = t.substring(2).trim();
    if (rest.isEmpty) {
      return (
        activa: true,
        modo: ModoBusquedaCatalogoPedido.porFiltro,
        terminoNombre: '',
        filtro: '',
        tokensOpcion: <String>[],
      );
    }
    final partes = rest.split(RegExp(r'\s+'));
    final filtro = partes.first;
    final tokens =
        partes.length > 1 ? partes.sublist(1) : const <String>[];
    if (tokens.isEmpty) {
      return (
        activa: true,
        modo: ModoBusquedaCatalogoPedido.porFiltro,
        terminoNombre: '',
        filtro: filtro,
        tokensOpcion: <String>[],
      );
    }
    return (
      activa: true,
      modo: ModoBusquedaCatalogoPedido.porFiltroOpciones,
      terminoNombre: '',
      filtro: filtro,
      tokensOpcion: tokens,
    );
  }

  return (
    activa: true,
    modo: ModoBusquedaCatalogoPedido.porNombre,
    terminoNombre: t,
    filtro: '',
    tokensOpcion: <String>[],
  );
}
