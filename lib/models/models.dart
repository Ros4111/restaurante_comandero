// lib/models/models.dart
// Todos los modelos de datos del proyecto

class Usuario {
  final int id;
  final String nombre;
  final String permisos;
  final int orden;
  /// 0 = ninguna; >0 = id_impresora para pantalla de servicio en mesa.
  final int impresora;

  Usuario({
    required this.id,
    required this.nombre,
    required this.permisos,
    required this.orden,
    this.impresora = 0,
  });

  factory Usuario.fromJson(Map<String, dynamic> j) => Usuario(
        id: int.parse(j['id_usuario'].toString()),
        nombre: j['nombre_usuario'] ?? '',
        permisos: j['permisos'] ?? 'camarero',
        orden: int.parse((j['orden'] ?? 0).toString()),
        impresora: int.tryParse((j['impresora'] ?? 0).toString()) ?? 0,
      );
}

class Categoria {
  final int id;
  final int idPadre;
  final String nombre;
  final String? nombreImagen;
  final bool disponible;
  final int orden;

  Categoria(
      {required this.id,
      required this.idPadre,
      required this.nombre,
      this.nombreImagen,
      required this.disponible,
      required this.orden});

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

  GrupoOpciones(
      {required this.id,
      required this.nombre,
      required this.disponible,
      required this.orden});

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
  final String nombreOpcion;
  final bool predeterminado;
  final bool disponible;
  final int orden;
  final double suplementoSinIva;

  OpcionProducto(
      {required this.id,
      required this.idProducto,
      required this.idGrupo,
      required this.nombreOpcion,
      required this.predeterminado,
      required this.disponible,
      required this.orden,
      this.suplementoSinIva = 0.0});

  factory OpcionProducto.fromJson(Map<String, dynamic> j) => OpcionProducto(
        id: int.parse(j['id_opcion'].toString()),
        idProducto: int.parse(j['id_producto'].toString()),
        idGrupo: int.parse(j['id_grupo_opciones'].toString()),
        nombreOpcion: j['nombre_opcion'] ?? '',
        predeterminado: j['predeterminado'].toString() == '1',
        disponible: j['disponible'].toString() == '1',
        orden: int.parse((j['orden'] ?? 0).toString()),
        suplementoSinIva:
            double.tryParse((j['suplemento_sin_iva'] ?? 0).toString()) ?? 0.0,
      );
}

class Producto {
  final int id;
  final String nombreProductoPantalla;
  final int idCategoria;
  final String textoImprimirBarraCocina;
  final String textoImprimirCliente;
  /// Atajos para búsqueda TPV (ej. "CL" para Café leche). Viene de MySQL `productos.filtro`.
  final String filtro;
  final int idImpresora;
  final bool disponible;
  final int orden;
  final double baseImponible;
  final double porcentajeIVA;

  Producto(
      {required this.id,
      required this.nombreProductoPantalla,
      required this.idCategoria,
      required this.textoImprimirBarraCocina,
      this.textoImprimirCliente = '',
      this.filtro = '',
      required this.idImpresora,
      required this.disponible,
      required this.orden,
      this.baseImponible = 0.0,
      this.porcentajeIVA = 0.0});

  factory Producto.fromJson(Map<String, dynamic> j) => Producto(
        id: int.parse(j['id_producto'].toString()),
        nombreProductoPantalla: j['nombre_producto_pantalla'] ?? '',
        idCategoria: int.parse(j['id_categoria'].toString()),
        textoImprimirBarraCocina: j['texto_imprimir_cocina'] ?? '',
        textoImprimirCliente: j['texto_imprimir_cliente']?.toString() ?? '',
        filtro: j['filtro']?.toString() ?? '',
        idImpresora: int.parse((j['id_impresora'] ?? 0).toString()),
        disponible: j['disponible'].toString() == '1',
        orden: int.parse((j['orden'] ?? 0).toString()),
        baseImponible:
            double.tryParse((j['base_imponible'] ?? 0).toString()) ?? 0.0,
        porcentajeIVA:
            double.tryParse((j['porcentaje_IVA'] ?? 0).toString()) ?? 0.0,
      );
}

class Impresora {
  final int id;
  final String nombre;
  final String? ip;
  final int puerto;
  final String tablaCodigos;

  Impresora({
    required this.id,
    required this.nombre,
    this.ip,
    required this.puerto,
    this.tablaCodigos = 'CP1252',
  });

  factory Impresora.fromJson(Map<String, dynamic> j) => Impresora(
        id: int.parse(j['id_impresora'].toString()),
        nombre: j['nombre']?.toString() ?? '',
        ip: j['ip']?.toString(),
        puerto: int.parse((j['puerto'] ?? 0).toString()),
        tablaCodigos:
            (j['tabla_codigos']?.toString().trim().isNotEmpty ?? false)
                ? j['tabla_codigos'].toString().trim().toUpperCase()
                : 'CP1252',
      );
}

class LineaPedido {
  int? idLinea; // null = nueva línea (no guardada aún)
  final int idProducto;
  int cantidad;
  String comentario;
  final String nombreProducto;
  Map<int, OpcionElegida> opcionesElegidas; // idGrupo -> opción elegida
  final String textoImprimirBarraCocina;
  int orden;
  bool impreso;
  int? moverAMesa; // si != null, mover esta línea a otra mesa
  bool editada;

  LineaPedido({
    this.idLinea,
    required this.idProducto,
    required this.cantidad,
    this.comentario = '',
    required this.nombreProducto,
    required this.opcionesElegidas,
    required this.textoImprimirBarraCocina,
    required this.orden,
    this.impreso = false,
    this.moverAMesa,
    this.editada = false,
  });

  bool get esNuevo => idLinea == null;
  List<String> get opcionesNoPredeterminadas => opcionesElegidas.values
      .where((o) => !o.predeterminado)
      .map((o) => o.nombre)
      .toList();
  List<String> get opcionesNombres =>
      opcionesElegidas.values.map((o) => o.nombre).toList();

  factory LineaPedido.fromJson(Map<String, dynamic> j) {
    final opRaw = j['opciones_elegidas'];
    Map<int, OpcionElegida> opciones = {};
    if (opRaw is Map) {
      opRaw.forEach((k, v) {
        final idGrupo = int.parse(k.toString());
        if (v is Map) {
          opciones[idGrupo] =
              OpcionElegida.fromJson(Map<String, dynamic>.from(v));
        } else {
          // Compatibilidad con formato antiguo: solo nombre
          opciones[idGrupo] =
              OpcionElegida(nombre: v.toString(), predeterminado: false);
        }
      });
    }
    return LineaPedido(
      idLinea:
          j['id_linea'] != null ? int.parse(j['id_linea'].toString()) : null,
      idProducto: int.parse(j['id_producto'].toString()),
      cantidad: int.parse(j['cantidad'].toString()),
      comentario: j['comentario'] ?? '',
      nombreProducto: j['nombre_producto_pantalla'] ?? '',
      opcionesElegidas: opciones,
      textoImprimirBarraCocina: j['texto_imprimir_cocina'] ?? '',
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
      'nombre_producto_pantalla': nombreProducto,
      'opciones_elegidas':
          opcionesElegidas.map((k, v) => MapEntry(k.toString(), v.toJson())),
      'texto_imprimir_cocina': textoImprimirBarraCocina,
    };
    if (idLinea != null) m['id_linea'] = idLinea;
    if (moverAMesa != null) m['mover_a_mesa'] = moverAMesa;
    return m;
  }

  /// Payload para POST /pedidos/.../guardar: solo referencia de producto, cantidad,
  /// comentario y opciones. Los textos y precios los resuelve el servidor.
  Map<String, dynamic> toJsonParaGuardarPedido() {
    final Map<String, dynamic> m = {
      'id_producto': idProducto,
      'cantidad': cantidad,
      'comentario': comentario,
      'opciones_elegidas':
          opcionesElegidas.map((k, v) => MapEntry(k.toString(), v.toJson())),
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
  }) =>
      LineaPedido(
        idLinea: idLinea,
        idProducto: idProducto,
        cantidad: cantidad ?? this.cantidad,
        comentario: comentario ?? this.comentario,
        nombreProducto: nombreProducto,
        opcionesElegidas: Map<int, OpcionElegida>.from(
            opcionesElegidas ?? this.opcionesElegidas),
        textoImprimirBarraCocina: textoImprimirBarraCocina,
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
        predeterminado: j['predeterminado'].toString() == '1' ||
            j['predeterminado'] == true,
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
  final String? terminalSerieBloqueo;
  final String? nombreCliente;
  final String? horaCreacion;
  final String? horaUltimaAccion;
  final int totalLineas;

  MesaResumen({
    required this.idPedido,
    required this.idMesa,
    required this.estado,
    this.idUsuarioBloqueo,
    this.nombreUsuarioBloqueo,
    this.horaBloqueo,
    this.terminalSerieBloqueo,
    this.nombreCliente,
    this.horaCreacion,
    this.horaUltimaAccion,
    required this.totalLineas,
  });

  factory MesaResumen.fromJson(Map<String, dynamic> j) => MesaResumen(
        idPedido: int.parse(j['id_pedido'].toString()),
        idMesa: int.parse(j['id_mesa'].toString()),
        estado: j['estado_mesa'] ?? 'abierta',
        idUsuarioBloqueo: j['id_usuario_bloqueo'] != null
            ? int.parse(j['id_usuario_bloqueo'].toString())
            : null,
        nombreUsuarioBloqueo: null, // Se asignará después de mapear usuarios
        horaBloqueo: j['hora_bloqueo'],
        terminalSerieBloqueo: j['terminal_serie_bloqueo']?.toString(),
        nombreCliente: j['nombre_cliente']?.toString(),
        horaCreacion: j['hora_creacion']?.toString(),
        horaUltimaAccion: j['hora_ultima_accion']?.toString(),
        totalLineas: int.parse((j['total_lineas'] ?? 0).toString()),
      );
}

/// Línea pendiente de servir en mesa (servido = 2000-01-01).
class LineaPendienteServir {
  final int idLinea;
  final int idProducto;
  final int cantidad;
  final String comentario;
  final String nombre;
  final Map<int, OpcionElegida> opcionesElegidas;

  const LineaPendienteServir({
    required this.idLinea,
    required this.idProducto,
    required this.cantidad,
    required this.comentario,
    required this.nombre,
    this.opcionesElegidas = const {},
  });

  factory LineaPendienteServir.fromJson(Map<String, dynamic> j) {
    return LineaPendienteServir(
      idLinea: int.parse(j['id_linea'].toString()),
      idProducto: int.parse((j['id_producto'] ?? 0).toString()),
      cantidad: int.parse((j['cantidad'] ?? 1).toString()),
      comentario: j['comentario']?.toString() ?? '',
      nombre: j['nombre_producto_pantalla']?.toString() ?? '',
      opcionesElegidas: _opcionesDesdeJson(j['opciones_elegidas']),
    );
  }

  static Map<int, OpcionElegida> _opcionesDesdeJson(dynamic raw) {
    final opciones = <int, OpcionElegida>{};
    if (raw is! Map) return opciones;
    raw.forEach((k, v) {
      final idGrupo = int.tryParse(k.toString());
      if (idGrupo == null) return;
      if (v is Map) {
        opciones[idGrupo] =
            OpcionElegida.fromJson(Map<String, dynamic>.from(v));
      } else if (v != null) {
        opciones[idGrupo] =
            OpcionElegida(nombre: v.toString(), predeterminado: false);
      }
    });
    return opciones;
  }
}

class PedidoPendienteServir {
  final int idPedido;
  final int idMesa;
  final String nombreCliente;
  final List<LineaPendienteServir> lineas;

  const PedidoPendienteServir({
    required this.idPedido,
    required this.idMesa,
    required this.nombreCliente,
    required this.lineas,
  });

  factory PedidoPendienteServir.fromJson(Map<String, dynamic> j) =>
      PedidoPendienteServir(
        idPedido: int.parse(j['id_pedido'].toString()),
        idMesa: int.parse(j['id_mesa'].toString()),
        nombreCliente: j['nombre_cliente']?.toString() ?? '',
        lineas: (j['lineas'] as List? ?? [])
            .map((e) =>
                LineaPendienteServir.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
