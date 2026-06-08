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
  /// Marca temporal 86 desde cocina/barra (distinto de [disponible] del admin).
  final bool agotado;
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
      this.agotado = false,
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
        agotado: j['agotado']?.toString() == '1',
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

/// Producto disponible en un grupo del menú del día (respuesta API).
class MenuDelDiaProductoItem {
  final int id;
  final String nombre;
  final bool agotado;

  MenuDelDiaProductoItem({
    required this.id,
    required this.nombre,
    this.agotado = false,
  });

  factory MenuDelDiaProductoItem.fromJson(Map<String, dynamic> j) =>
      MenuDelDiaProductoItem(
        id: int.parse(j['id_producto'].toString()),
        nombre: j['nombre_producto_pantalla']?.toString() ?? '',
        agotado: j['agotado'] == true || j['agotado']?.toString() == '1',
      );
}

/// Configuración del menú del día para una fecha.
class MenuDelDiaConfig {
  static const filtroProductoMenu = 'menu_dia';
  static const nombresGrupos = ['primero', 'segundo', 'bebida', 'postre'];

  final String fecha;
  final int? idProductoMenu;
  final bool activo;
  /// Descuento % sobre el PVP de carta si el cliente elige bebida fuera del menú.
  final double descuentoBebidaAlternativaPct;
  final String notas;
  final Map<String, List<MenuDelDiaProductoItem>> grupos;

  MenuDelDiaConfig({
    required this.fecha,
    required this.idProductoMenu,
    required this.activo,
    this.descuentoBebidaAlternativaPct = 0,
    this.notas = '',
    required this.grupos,
  });

  factory MenuDelDiaConfig.fromJson(Map<String, dynamic> j) {
    final rawGrupos = j['grupos'];
    final map = <String, List<MenuDelDiaProductoItem>>{};
    for (final g in nombresGrupos) {
      map[g] = [];
    }
    if (rawGrupos is Map) {
      rawGrupos.forEach((k, v) {
        final key = k.toString();
        if (!map.containsKey(key)) return;
        if (v is List) {
          map[key] = v
              .map((e) => MenuDelDiaProductoItem.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      });
    }
    final idRaw = j['id_producto_menu'];
    return MenuDelDiaConfig(
      fecha: j['fecha']?.toString() ?? '',
      idProductoMenu:
          idRaw == null ? null : int.tryParse(idRaw.toString()),
      activo: j['activo'] == true || j['activo']?.toString() == '1',
      descuentoBebidaAlternativaPct: double.tryParse(
              (j['descuento_bebida_alternativa_pct'] ?? 0).toString()) ??
          0,
      notas: j['notas']?.toString() ?? '',
      grupos: map,
    );
  }

  List<MenuDelDiaProductoItem> productosGrupo(String grupo) =>
      grupos[grupo] ?? const [];

  List<MenuDelDiaProductoItem> productosPediblesGrupo(String grupo) =>
      productosGrupo(grupo).where((p) => !p.agotado).toList();

  bool esProductoMenu(int idProducto) =>
      idProductoMenu != null && idProducto == idProductoMenu;

  bool esProductoMenuPorFiltro(String filtro) => filtro == filtroProductoMenu;
}

/// Selección del menú del día (solo en memoria, línea cabecera antes de guardar).
class MenuDelDiaSeleccion {
  final List<int> primeros;
  final List<int> segundos;
  final int? bebidaId;
  final bool bebidaDelMenu;
  final int? postreId;
  final String comentarioExtra;
  final bool dosPrimeros;
  final bool dosSegundos;

  const MenuDelDiaSeleccion({
    required this.primeros,
    required this.segundos,
    this.bebidaId,
    this.bebidaDelMenu = true,
    this.postreId,
    this.comentarioExtra = '',
    this.dosPrimeros = false,
    this.dosSegundos = false,
  });

  factory MenuDelDiaSeleccion.fromDialogResult(Map<String, dynamic> r) {
    final primeros = (r['primeros'] as List).cast<int>();
    final segundos = (r['segundos'] as List).cast<int>();
    return MenuDelDiaSeleccion(
      primeros: primeros,
      segundos: segundos,
      bebidaId: r['bebida_id'] as int?,
      bebidaDelMenu: r['bebida_del_menu'] == true,
      postreId: r['postre_id'] as int?,
      comentarioExtra: (r['comentario'] as String?)?.trim() ?? '',
      dosPrimeros: false,
      dosSegundos: false,
    );
  }

  Map<String, dynamic> toDialogResult() => {
        'primeros': primeros,
        'segundos': segundos,
        'bebida_id': bebidaId,
        'bebida_del_menu': bebidaDelMenu,
        'postre_id': postreId,
        'comentario': comentarioExtra,
        'dos_primeros': dosPrimeros,
        'dos_segundos': dosSegundos,
      };

  /// Resumen de cabecera: solo 1º / 2º (+ comentario libre opcional).
  static String comentarioCabecera({
    required List<int> primeros,
    required List<int> segundos,
    required String Function(int id) nombreDe,
    String comentarioExtra = '',
  }) {
    final partes = <String>[];
    if (primeros.isNotEmpty) {
      partes.add('1º ${primeros.map(nombreDe).join(', ')}');
    }
    if (segundos.isNotEmpty) {
      partes.add('2º ${segundos.map(nombreDe).join(', ')}');
    }
    var c = partes.join(' · ');
    final extra = comentarioExtra.trim();
    if (extra.isNotEmpty) {
      c = c.isEmpty ? extra : '$c · $extra';
    }
    return c;
  }

  /// Comentario en línea de detalle para cocina (1º / 2º del menú).
  static String comentarioDetalleCocina(String puesto) =>
      'Menú del día · $puesto';

  /// Texto visible en la línea del pedido (solo platos del menú).
  static String comentarioPlatosEnLinea(String comentario) {
    return comentario
        .split(' · ')
        .where((p) {
          final t = p.trim();
          return t.startsWith('1º') || t.startsWith('2º');
        })
        .join(' · ');
  }
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
  bool urgente;
  /// Línea incluida en menú del día (precio 0 en ticket; cocina sí imprime).
  bool sinCargo;
  /// Suplemento sin IVA añadido al precio base del producto.
  double suplementoSinIva;
  /// Descuento % sobre PVP de carta (bebida alternativa en menú del día).
  double descuentoMenuBebidaPct;
  /// PVP unitario (IVA incluido) almacenado en BD. Solo fiable para notas libres;
  /// para productos regulares se recalcula desde el catálogo.
  final double pvpAlmacenado;
  /// Agrupa cabecera y detalle de un menú del día (solo sesión local).
  final int? menuGrupoLocal;
  /// Solo en la línea cabecera del menú (producto menú del día).
  final MenuDelDiaSeleccion? menuDelDiaSeleccion;

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
    this.urgente = false,
    this.sinCargo = false,
    this.suplementoSinIva = 0,
    this.descuentoMenuBebidaPct = 0,
    this.pvpAlmacenado = 0.0,
    this.menuGrupoLocal,
    this.menuDelDiaSeleccion,
  });

  bool get esComponenteMenu => sinCargo;
  bool get perteneceMenuDelDia => menuGrupoLocal != null;
  bool get esCabeceraMenuDelDia =>
      menuGrupoLocal != null && menuDelDiaSeleccion != null;
  bool get esDetalleMenuDelDia =>
      (menuGrupoLocal != null && menuDelDiaSeleccion == null) ||
      comentarioEsDetalleMenuDelDia(comentario);

  static bool comentarioEsDetalleMenuDelDia(String comentario) =>
      comentario.startsWith('Menú del día');
  bool get esNuevo => idLinea == null;
  bool get esNotaLibre => idProducto == 0;
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
    final precioSinIva =
        double.tryParse((j['precio_sin_IVA'] ?? 0).toString()) ?? 0.0;
    final pctIva =
        double.tryParse((j['porcentaje_IVA'] ?? 0).toString()) ?? 0.0;
    final pvp = precioSinIva > 0
        ? double.parse(
            (precioSinIva * (1.0 + pctIva / 100.0)).toStringAsFixed(2))
        : 0.0;
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
      urgente: j['urgente'] == true ||
          j['urgente']?.toString() == '1',
      pvpAlmacenado: pvp,
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
    m['urgente'] = urgente;
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
      'urgente': urgente,
    };
    if (idLinea != null) m['id_linea'] = idLinea;
    if (moverAMesa != null) m['mover_a_mesa'] = moverAMesa;
    if (sinCargo) m['sin_cargo'] = true;
    if (suplementoSinIva > 0) m['suplemento_sin_iva'] = suplementoSinIva;
    if (descuentoMenuBebidaPct > 0) {
      m['descuento_menu_bebida_pct'] = descuentoMenuBebidaPct;
    }
    return m;
  }

  LineaPedido copyWith({
    int? cantidad,
    String? comentario,
    int? moverAMesa,
    Map<int, OpcionElegida>? opcionesElegidas,
    bool? editada,
    bool? urgente,
    bool? sinCargo,
    double? suplementoSinIva,
    double? descuentoMenuBebidaPct,
    int? menuGrupoLocal,
    MenuDelDiaSeleccion? menuDelDiaSeleccion,
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
        urgente: urgente ?? this.urgente,
        sinCargo: sinCargo ?? this.sinCargo,
        suplementoSinIva: suplementoSinIva ?? this.suplementoSinIva,
        descuentoMenuBebidaPct:
            descuentoMenuBebidaPct ?? this.descuentoMenuBebidaPct,
        pvpAlmacenado: pvpAlmacenado,
        menuGrupoLocal: menuGrupoLocal ?? this.menuGrupoLocal,
        menuDelDiaSeleccion: menuDelDiaSeleccion ?? this.menuDelDiaSeleccion,
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
  final double totalImporte;
  final bool bloqueoVigente;
  final bool bloqueadaPorMi;

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
    this.totalImporte = 0.0,
    this.bloqueoVigente = false,
    this.bloqueadaPorMi = false,
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
        totalImporte:
            double.tryParse((j['total_importe'] ?? 0).toString()) ?? 0.0,
        bloqueoVigente: j['bloqueo_vigente'] == true,
        bloqueadaPorMi: j['bloqueada_por_mi'] == true,
      );
}

// ── Historial de mesas cerradas ──────────────────────────────

class MesaHistorico {
  final int idPedido;
  final int idMesa;
  final String nombreCliente;
  final String? horaCreacion;
  final String? horaUltimaAccion;
  final double totalImporte;
  final int totalLineas;

  const MesaHistorico({
    required this.idPedido,
    required this.idMesa,
    required this.nombreCliente,
    this.horaCreacion,
    this.horaUltimaAccion,
    this.totalImporte = 0.0,
    this.totalLineas = 0,
  });

  factory MesaHistorico.fromJson(Map<String, dynamic> j) => MesaHistorico(
        idPedido: int.parse(j['id_pedido'].toString()),
        idMesa: int.parse(j['id_mesa'].toString()),
        nombreCliente: j['nombre_cliente']?.toString() ?? '',
        horaCreacion: j['hora_creacion']?.toString(),
        horaUltimaAccion: j['hora_ultima_accion']?.toString(),
        totalImporte:
            double.tryParse((j['total_importe'] ?? 0).toString()) ?? 0.0,
        totalLineas: int.parse((j['total_lineas'] ?? 0).toString()),
      );
}

class LineaHistorico {
  final int idLinea;
  final int idProducto;
  final int cantidad;
  final String comentario;
  final String nombreProducto;
  final Map<int, OpcionElegida> opcionesElegidas;
  final double pvpUnitario;

  const LineaHistorico({
    required this.idLinea,
    required this.idProducto,
    required this.cantidad,
    required this.comentario,
    required this.nombreProducto,
    this.opcionesElegidas = const {},
    this.pvpUnitario = 0.0,
  });

  factory LineaHistorico.fromJson(Map<String, dynamic> j) {
    final opRaw = j['opciones_elegidas'];
    final opciones = <int, OpcionElegida>{};
    if (opRaw is Map) {
      opRaw.forEach((k, v) {
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
    }
    return LineaHistorico(
      idLinea: int.parse(j['id_linea'].toString()),
      idProducto: int.parse((j['id_producto'] ?? 0).toString()),
      cantidad: int.parse((j['cantidad'] ?? 1).toString()),
      comentario: j['comentario']?.toString() ?? '',
      nombreProducto: j['nombre_producto_pantalla']?.toString() ?? '',
      opcionesElegidas: opciones,
      pvpUnitario:
          double.tryParse((j['pvp_unitario'] ?? 0).toString()) ?? 0.0,
    );
  }
}

/// Línea pendiente de servir en mesa (servido = 2000-01-01).
class LineaPendienteServir {
  final int idLinea;
  /// Todas las filas de pedido_detalles agrupadas en esta línea.
  final List<int> idsLinea;
  final int idProducto;
  final int cantidad;
  final String comentario;
  final String nombre;
  final Map<int, OpcionElegida> opcionesElegidas;
  /// Línea ya enviada a cocina y modificada después (cantidad/comentario).
  final bool modificado;
  final bool urgente;

  const LineaPendienteServir({
    required this.idLinea,
    required this.idsLinea,
    required this.idProducto,
    required this.cantidad,
    required this.comentario,
    required this.nombre,
    this.opcionesElegidas = const {},
    this.modificado = false,
    this.urgente = false,
  });

  factory LineaPendienteServir.fromJson(Map<String, dynamic> j) {
    final idsRaw = j['ids_linea'];
    final List<int> idsLinea;
    if (idsRaw is List && idsRaw.isNotEmpty) {
      idsLinea = idsRaw.map((e) => int.parse(e.toString())).toList();
    } else {
      final id = int.parse(j['id_linea'].toString());
      idsLinea = [id];
    }
    return LineaPendienteServir(
      idLinea: idsLinea.first,
      idsLinea: idsLinea,
      idProducto: int.parse((j['id_producto'] ?? 0).toString()),
      cantidad: int.parse((j['cantidad'] ?? 1).toString()),
      comentario: j['comentario']?.toString() ?? '',
      nombre: j['nombre_producto_pantalla']?.toString() ?? '',
      opcionesElegidas: _opcionesDesdeJson(j['opciones_elegidas']),
      modificado: j['modificado'] == true ||
          j['modificado']?.toString() == '1' ||
          j['modificado_servicio']?.toString() == '1',
      urgente: j['urgente'] == true || j['urgente']?.toString() == '1',
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
  /// Clave única del lote (id_pedido + hora_pedido del envío a cocina).
  final String idGrupo;
  final int idPedido;
  final String horaPedido;
  final int idMesa;
  final String nombreCliente;
  final List<LineaPendienteServir> lineas;

  const PedidoPendienteServir({
    required this.idGrupo,
    required this.idPedido,
    required this.horaPedido,
    required this.idMesa,
    required this.nombreCliente,
    required this.lineas,
  });

  bool get tieneUrgente => lineas.any((l) => l.urgente);

  factory PedidoPendienteServir.fromJson(Map<String, dynamic> j) {
    final idPedido = int.parse(j['id_pedido'].toString());
    final horaPedido = j['hora_pedido']?.toString() ?? '';
    final idGrupo = j['id_grupo']?.toString() ??
        (horaPedido.isNotEmpty ? '$idPedido|$horaPedido' : idPedido.toString());
    return PedidoPendienteServir(
      idGrupo: idGrupo,
      idPedido: idPedido,
      horaPedido: horaPedido,
      idMesa: int.parse(j['id_mesa'].toString()),
      nombreCliente: j['nombre_cliente']?.toString() ?? '',
      lineas: (j['lineas'] as List? ?? [])
          .map((e) =>
              LineaPendienteServir.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Entrada del historial de movimientos de una mesa (registro_cambios).
class MovimientoMesaItem {
  final String fechaHora;
  final String usuario;
  final String producto;
  final int cantidad;
  final int? mesaOrigen;
  final int? mesaDestino;

  const MovimientoMesaItem({
    required this.fechaHora,
    required this.usuario,
    required this.producto,
    required this.cantidad,
    this.mesaOrigen,
    this.mesaDestino,
  });

  factory MovimientoMesaItem.fromJson(Map<String, dynamic> j) {
    int? mesaOpt(dynamic v) {
      if (v == null) return null;
      final n = int.tryParse(v.toString());
      return n != null && n > 0 ? n : null;
    }

    return MovimientoMesaItem(
      fechaHora: j['fecha_hora']?.toString() ?? '',
      usuario: j['usuario']?.toString() ?? '',
      producto: j['producto']?.toString() ?? '—',
      cantidad: int.tryParse((j['cantidad'] ?? 1).toString()) ?? 1,
      mesaOrigen: mesaOpt(j['mesa_origen']),
      mesaDestino: mesaOpt(j['mesa_destino']),
    );
  }
}

class MesaMovimientos {
  final int idMesa;
  final int idPedido;
  final List<MovimientoMesaItem> nuevos;
  final List<MovimientoMesaItem> eliminados;
  final List<MovimientoMesaItem> enviados;
  final List<MovimientoMesaItem> recibidos;

  const MesaMovimientos({
    required this.idMesa,
    required this.idPedido,
    required this.nuevos,
    required this.eliminados,
    required this.enviados,
    required this.recibidos,
  });

  factory MesaMovimientos.fromJson(Map<String, dynamic> j) {
    List<MovimientoMesaItem> lista(dynamic raw) => (raw as List? ?? [])
        .map((e) =>
            MovimientoMesaItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return MesaMovimientos(
      idMesa: int.parse(j['id_mesa'].toString()),
      idPedido: int.parse(j['id_pedido'].toString()),
      nuevos: lista(j['nuevos']),
      eliminados: lista(j['eliminados']),
      enviados: lista(j['enviados']),
      recibidos: lista(j['recibidos']),
    );
  }
}
