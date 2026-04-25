// lib/models/models.dart
// Todos los modelos de datos del proyecto

class Usuario {
  final int id;
  final String nombre;
  final String permisos;
  final int orden;

  Usuario({required this.id, required this.nombre, required this.permisos, required this.orden});

  factory Usuario.fromJson(Map<String, dynamic> j) => Usuario(
    id: int.parse(j['id_usuario'].toString()),
    nombre: j['nombre_usuario'] ?? '',
    permisos: j['permisos'] ?? 'camarero',
    orden: int.parse((j['orden'] ?? 0).toString()),
  );
}

class Categoria {
  final int id;
  final int idPadre;
  final String nombre;
  final String? nombreImagen;
  final bool disponible;
  final int orden;

  Categoria({required this.id, required this.idPadre, required this.nombre,
    this.nombreImagen, required this.disponible, required this.orden});

  factory Categoria.fromJson(Map<String, dynamic> j) => Categoria(
    id: int.parse(j['id_categoria'].toString()),
    idPadre: int.parse((j['id_categoria_padre'] ?? 0).toString()),
    nombre: j['nombre_categoria'] ?? '',
    nombreImagen: j['nombre_imagen'],
    disponible: (j['disponible'].toString()) == '1',
    orden: int.parse((j['orden'] ?? 0).toString()),
  );
}

class GrupoOpciones {
  final int id;
  final String nombre;
  final bool disponible;
  final int orden;

  GrupoOpciones({required this.id, required this.nombre,
    required this.disponible, required this.orden});

  factory GrupoOpciones.fromJson(Map<String, dynamic> j) => GrupoOpciones(
    id: int.parse(j['id_grupo_opciones'].toString()),
    nombre: j['nombre_grupo'] ?? '',
    disponible: j['disponible'].toString() == '1',
    orden: int.parse((j['orden'] ?? 0).toString()),
  );
}

class OpcionProducto {
  final int id;
  final int idProducto;
  final int idGrupo;
  final String nombre;
  final bool predeterminado;
  final bool disponible;
  final int orden;

  OpcionProducto({required this.id, required this.idProducto, required this.idGrupo,
    required this.nombre, required this.predeterminado,
    required this.disponible, required this.orden});

  factory OpcionProducto.fromJson(Map<String, dynamic> j) => OpcionProducto(
    id: int.parse(j['id_opcion'].toString()),
    idProducto: int.parse(j['id_producto'].toString()),
    idGrupo: int.parse(j['id_grupo_opciones'].toString()),
    nombre: j['nombre_opcion'] ?? '',
    predeterminado: j['predeterminado'].toString() == '1',
    disponible: j['disponible'].toString() == '1',
    orden: int.parse((j['orden'] ?? 0).toString()),
  );
}

class Producto {
  final int id;
  final String nombre;
  final int idCategoria;
  final String textoImprimir;
  final int idImpresora;
  final bool disponible;
  final bool personalizable;
  final int orden;

  Producto({required this.id, required this.nombre, required this.idCategoria,
    required this.textoImprimir, required this.idImpresora,
    required this.disponible, required this.personalizable, required this.orden});

  factory Producto.fromJson(Map<String, dynamic> j) => Producto(
    id: int.parse(j['id_producto'].toString()),
    nombre: j['nombre_producto'] ?? '',
    idCategoria: int.parse(j['id_categoria'].toString()),
    textoImprimir: j['texto_imprimir'] ?? '',
    idImpresora: int.parse((j['id_impresora'] ?? 0).toString()),
    disponible: j['disponible'].toString() == '1',
    personalizable: j['personalizable'].toString() == '1',
    orden: int.parse((j['orden'] ?? 0).toString()),
  );
}

class LineaPedido {
  int? idLinea;           // null = nueva línea (no guardada aún)
  final int idProducto;
  int cantidad;
  String comentario;
  final String nombreProducto;
  Map<int, OpcionElegida> opcionesElegidas; // idGrupo -> opción elegida
  final String textoImprimir;
  int orden;
  bool impreso;
  int? moverAMesa;        // si != null, mover esta línea a otra mesa
  bool editada;

  LineaPedido({
    this.idLinea,
    required this.idProducto,
    required this.cantidad,
    this.comentario = '',
    required this.nombreProducto,
    required this.opcionesElegidas,
    required this.textoImprimir,
    required this.orden,
    this.impreso = false,
    this.moverAMesa,
    this.editada = false,
  });

  bool get esNuevo => idLinea == null;
  List<String> get opcionesNoPredeterminadas =>
      opcionesElegidas.values.where((o) => !o.predeterminado).map((o) => o.nombre).toList();
  List<String> get opcionesNombres =>
      opcionesElegidas.values.map((o) => o.nombre).toList();

  factory LineaPedido.fromJson(Map<String, dynamic> j) {
    final opRaw = j['opciones_elegidas'];
    Map<int, OpcionElegida> opciones = {};
    if (opRaw is Map) {
      opRaw.forEach((k, v) {
        final idGrupo = int.parse(k.toString());
        if (v is Map) {
          opciones[idGrupo] = OpcionElegida.fromJson(Map<String, dynamic>.from(v));
        } else {
          // Compatibilidad con formato antiguo: solo nombre
          opciones[idGrupo] = OpcionElegida(nombre: v.toString(), predeterminado: false);
        }
      });
    }
    return LineaPedido(
      idLinea: j['id_linea'] != null ? int.parse(j['id_linea'].toString()) : null,
      idProducto: int.parse(j['id_producto'].toString()),
      cantidad: int.parse(j['cantidad'].toString()),
      comentario: j['comentario'] ?? '',
      nombreProducto: j['nombre_producto'] ?? '',
      opcionesElegidas: opciones,
      textoImprimir: j['texto_imprimir'] ?? '',
      orden: int.parse((j['orden'] ?? 0).toString()),
      impreso: j['impreso'].toString() == '1',
      editada: false,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = {
      'id_producto': idProducto,
      'cantidad': cantidad,
      'comentario': comentario,
      'nombre_producto': nombreProducto,
      'opciones_elegidas': opcionesElegidas.map((k, v) => MapEntry(k.toString(), v.toJson())),
      'texto_imprimir': textoImprimir,
    };
    if (idLinea != null) m['id_linea'] = idLinea;
    if (moverAMesa != null) m['mover_a_mesa'] = moverAMesa;
    return m;
  }

  LineaPedido copyWith({
    int? cantidad,
    String? comentario,
    int? moverAMesa,
    Map<int, OpcionElegida>? opcionesElegidas,
    bool? editada,
  }) => LineaPedido(
    idLinea: idLinea,
    idProducto: idProducto,
    cantidad: cantidad ?? this.cantidad,
    comentario: comentario ?? this.comentario,
    nombreProducto: nombreProducto,
    opcionesElegidas: Map<int, OpcionElegida>.from(opcionesElegidas ?? this.opcionesElegidas),
    textoImprimir: textoImprimir,
    orden: orden,
    impreso: impreso,
    moverAMesa: moverAMesa ?? this.moverAMesa,
    editada: editada ?? this.editada,
  );
}

class OpcionElegida {
  final String nombre;
  final bool predeterminado;

  OpcionElegida({
    required this.nombre,
    required this.predeterminado,
  });

  factory OpcionElegida.fromJson(Map<String, dynamic> j) => OpcionElegida(
    nombre: j['nombre']?.toString() ?? '',
    predeterminado: j['predeterminado'].toString() == '1' || j['predeterminado'] == true,
  );

  Map<String, dynamic> toJson() => {
    'nombre': nombre,
    'predeterminado': predeterminado,
  };
}

class MesaResumen {
  final int idPedido;
  final int idMesa;
  final String estado;
  final int? idUsuarioBloqueo;
  final String? nombreUsuarioBloqueo;
  final String? horaBloqueo;
  final String? horaCreacion;
  final String? horaUltimaAccion;
  final int totalLineas;

  MesaResumen({
    required this.idPedido, required this.idMesa, required this.estado,
    this.idUsuarioBloqueo, this.nombreUsuarioBloqueo, this.horaBloqueo,
    this.horaCreacion, this.horaUltimaAccion,
    required this.totalLineas,
  });

  factory MesaResumen.fromJson(Map<String, dynamic> j) => MesaResumen(
    idPedido: int.parse(j['id_pedido'].toString()),
    idMesa: int.parse(j['id_mesa'].toString()),
    estado: j['estado_mesa'] ?? 'abierta',
    idUsuarioBloqueo: j['id_usuario_bloqueo'] != null
        ? int.parse(j['id_usuario_bloqueo'].toString()) : null,
    nombreUsuarioBloqueo: j['nombre_usuario_bloqueo'],
    horaBloqueo: j['hora_bloqueo'],
    horaCreacion: j['hora_creacion']?.toString(),
    horaUltimaAccion: j['hora_ultima_accion']?.toString(),
    totalLineas: int.parse((j['total_lineas'] ?? 0).toString()),
  );
}
