import '../models/models.dart';
import '../services/catalogo_provider.dart';

/// Opciones elegidas que difieren del predeterminado del catálogo (misma regla que [LineasPanel]).
List<String> opcionesNoPredAMostrar(
  int idProducto,
  Map<int, OpcionElegida> opcionesElegidas,
  CatalogoProvider catalogo,
) {
  final out = <String>[];
  for (final entry in opcionesElegidas.entries) {
    final idGrupo = entry.key;
    final elegida = entry.value;
    final opts = catalogo.opcionesDeGrupo(idProducto, idGrupo);
    if (opts.isEmpty) {
      if (!elegida.predeterminado) out.add(elegida.nombre);
      continue;
    }
    OpcionProducto? predCatalogo;
    for (final o in opts) {
      if (o.predeterminado) {
        predCatalogo = o;
        break;
      }
    }
    predCatalogo ??= opts.first;
    if (predCatalogo.nombreOpcion != elegida.nombre) {
      out.add(elegida.nombre);
    }
  }
  return out;
}

Map<int, OpcionElegida> opcionesElegidasDesdeJson(dynamic raw) {
  final opciones = <int, OpcionElegida>{};
  if (raw is! Map) return opciones;
  raw.forEach((k, v) {
    final idGrupo = int.tryParse(k.toString());
    if (idGrupo == null) return;
    if (v is Map) {
      opciones[idGrupo] =
          OpcionElegida.fromJson(Map<String, dynamic>.from(v));
    } else if (v != null) {
      opciones[idGrupo] = OpcionElegida(nombre: v.toString(), predeterminado: false);
    }
  });
  return opciones;
}
