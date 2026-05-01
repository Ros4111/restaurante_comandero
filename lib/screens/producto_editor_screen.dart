// lib/screens/producto_editor_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';

/// Fila editable ligada a [id_grupo_opciones] (catálogo) → se persiste en productos_opciones.
class _FilaOpcionEdit {
  _FilaOpcionEdit({
    this.idOpcion,
    required this.idGrupo,
    String nombre = '',
    String orden = '',
    this.predeterminado = false,
    this.disponible = true,
  })  : nombre = TextEditingController(text: nombre),
        orden = TextEditingController(text: orden);

  final int? idOpcion;
  int idGrupo;
  final TextEditingController nombre;
  final TextEditingController orden;
  bool predeterminado;
  bool disponible;

  void dispose() {
    nombre.dispose();
    orden.dispose();
  }

  Map<String, dynamic> toJsonBody() => {
        'id_grupo_opciones': idGrupo,
        'nombre_opcion': nombre.text.trim(),
        'predeterminado': predeterminado,
        'disponible': disponible,
        'orden': int.tryParse(orden.text.trim()) ?? 0,
      };
}

class ProductoEditorScreen extends StatefulWidget {
  const ProductoEditorScreen({super.key});

  @override
  State<ProductoEditorScreen> createState() => _ProductoEditorScreenState();
}

class _ProductoEditorScreenState extends State<ProductoEditorScreen> {
  final _nombreCtrl = TextEditingController();
  final _textoImprimirCtrl = TextEditingController();
  final _ordenCtrl = TextEditingController();
  final _buscarCtrl = TextEditingController();

  int? _id;
  int? _idCategoria;
  int? _idImpresora;
  bool _disponible = true;

  final List<_FilaOpcionEdit> _filasOpciones = [];
  int? _grupoParaNuevaFila;

  List<Map<String, dynamic>> _listaBusqueda = [];
  Timer? _debounceBuscar;
  bool _cargandoLista = false;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _aplicarDefaultsCatalogo();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _refrescarListaBusqueda(''));
  }

  void _aplicarDefaultsCatalogo() {
    final cat = context.read<CatalogoProvider>();
    final cats = cat.categorias.toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));
    if (cats.isNotEmpty) {
      _idCategoria ??= cats.first.id;
    }
    if (cat.impresoras.isNotEmpty) {
      _idImpresora ??= cat.impresoras.first.id;
    } else {
      _idImpresora ??= 0;
    }
    final grupos = cat.grupos.where((g) => g.disponible).toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));
    _grupoParaNuevaFila ??= grupos.isNotEmpty ? grupos.first.id : null;
  }

  void _disposeFilasOpciones() {
    for (final f in _filasOpciones) {
      f.dispose();
    }
    _filasOpciones.clear();
  }

  @override
  void dispose() {
    _debounceBuscar?.cancel();
    _disposeFilasOpciones();
    _nombreCtrl.dispose();
    _textoImprimirCtrl.dispose();
    _ordenCtrl.dispose();
    _buscarCtrl.dispose();
    super.dispose();
  }

  void _nuevoProducto() {
    _disposeFilasOpciones();
    setState(() {
      _id = null;
      _nombreCtrl.clear();
      _textoImprimirCtrl.clear();
      _ordenCtrl.clear();
      _disponible = true;
      _error = null;
    });
    _aplicarDefaultsCatalogo();
    setState(() {});
  }

  void _cargarOpcionesDesdeApi(dynamic raw, CatalogoProvider catalogo) {
    _disposeFilasOpciones();
    if (raw is! List) return;
    final idsValidos = _gruposDisponibles(catalogo).map((g) => g.id).toSet();
    final idGrupoDefecto =
        idsValidos.isEmpty ? null : _gruposDisponibles(catalogo).first.id;

    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      var idG = int.tryParse(m['id_grupo_opciones'].toString());
      if (idG == null || idG <= 0) continue;
      if (idGrupoDefecto != null && !idsValidos.contains(idG)) {
        idG = idGrupoDefecto;
      }
      _filasOpciones.add(_FilaOpcionEdit(
        idOpcion: m['id_opcion'] != null
            ? int.tryParse(m['id_opcion'].toString())
            : null,
        idGrupo: idG,
        nombre: m['nombre_opcion']?.toString() ?? '',
        orden: (m['orden'] ?? '').toString(),
        predeterminado: m['predeterminado'].toString() == '1',
        disponible: m['disponible'].toString() == '1',
      ));
    }
  }

  Future<void> _refrescarListaBusqueda(String q) async {
    setState(() {
      _cargandoLista = true;
      _error = null;
    });
    final api = context.read<ApiService>();
    try {
      final rows = await api.getProductosLista(q: q.isEmpty ? null : q);
      if (!mounted) return;
      setState(() {
        _listaBusqueda = rows;
        _cargandoLista = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoLista = false;
        _error = e.toString();
      });
    }
  }

  void _onBuscarChanged(String v) {
    _debounceBuscar?.cancel();
    _debounceBuscar = Timer(const Duration(milliseconds: 350), () {
      _refrescarListaBusqueda(v.trim());
    });
  }

  Future<void> _cargarProducto(int id) async {
    setState(() => _error = null);
    final api = context.read<ApiService>();
    try {
      final j = await api.getProductoDetalle(id);
      if (!mounted) return;
      final cat = context.read<CatalogoProvider>();
      _cargarOpcionesDesdeApi(j['opciones'], cat);
      setState(() {
        _id = id;
        _nombreCtrl.text = j['nombre_producto']?.toString() ?? '';
        _textoImprimirCtrl.text = j['texto_imprimir']?.toString() ?? '';
        _ordenCtrl.text = (j['orden'] ?? '').toString();
        _idCategoria = int.tryParse(j['id_categoria'].toString());
        _idImpresora = int.tryParse((j['id_impresora'] ?? 0).toString());
        _disponible = j['disponible'].toString() == '1';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  List<GrupoOpciones> _gruposDisponibles(CatalogoProvider cat) {
    final g = cat.grupos.where((x) => x.disponible).toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));
    return g;
  }

  void _anadirFilaOpcion() {
    final cat = context.read<CatalogoProvider>();
    final grupos = _gruposDisponibles(cat);
    if (grupos.isEmpty) {
      setState(() => _error = 'No hay grupos en grupos_opciones (catálogo)');
      return;
    }
    final gid = _grupoParaNuevaFila != null &&
            grupos.any((g) => g.id == _grupoParaNuevaFila)
        ? _grupoParaNuevaFila!
        : grupos.first.id;
    setState(() {
      _filasOpciones.add(_FilaOpcionEdit(idGrupo: gid));
      _error = null;
    });
  }

  void _quitarFila(_FilaOpcionEdit f) {
    setState(() {
      f.dispose();
      _filasOpciones.remove(f);
    });
  }

  void _setPredeterminadoSoloEnGrupo(_FilaOpcionEdit fila, bool value) {
    setState(() {
      if (value) {
        for (final o in _filasOpciones) {
          o.predeterminado = o.idGrupo == fila.idGrupo && identical(o, fila);
        }
      } else {
        fila.predeterminado = false;
      }
    });
  }

  void _onGrupoFilaCambiado(_FilaOpcionEdit fila, int nuevoGrupo) {
    setState(() {
      fila.idGrupo = nuevoGrupo;
      fila.predeterminado = false;
    });
  }

  Map<String, dynamic> _bodyParaApi() {
    final orden = int.tryParse(_ordenCtrl.text.trim());
    final opciones = _filasOpciones
        .map((f) => f.toJsonBody())
        .where((m) => (m['nombre_opcion'] as String).isNotEmpty)
        .toList();
    return {
      'nombre_producto': _nombreCtrl.text.trim(),
      'id_categoria': _idCategoria ?? 0,
      'texto_imprimir': _textoImprimirCtrl.text.trim().isEmpty
          ? _nombreCtrl.text.trim()
          : _textoImprimirCtrl.text.trim(),
      'id_impresora': _idImpresora ?? 0,
      'disponible': _disponible,
      if (orden != null && orden > 0) 'orden': orden,
      'opciones': opciones,
    };
  }

  Future<void> _recargarCatalogo() async {
    final api = context.read<ApiService>();
    final cat = context.read<CatalogoProvider>();
    final data = await api.getCatalogo();
    if (mounted) cat.cargar(data);
  }

  Future<void> _guardar() async {
    if (_nombreCtrl.text.trim().isEmpty || (_idCategoria ?? 0) <= 0) {
      setState(() => _error = 'Indica nombre y categoría');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final api = context.read<ApiService>();
    try {
      if (_id == null) {
        final nuevoId = await api.crearProducto(_bodyParaApi());
        if (mounted) {
          setState(() => _id = nuevoId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Producto creado (id $nuevoId)'),
              backgroundColor: Colors.green[800],
            ),
          );
        }
        await _cargarProducto(nuevoId);
      } else {
        await api.actualizarProducto(_id!, _bodyParaApi());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Producto ${_id!} actualizado'),
              backgroundColor: Colors.green[800],
            ),
          );
        }
        await _cargarProducto(_id!);
      }
      await _recargarCatalogo();
      await _refrescarListaBusqueda(_buscarCtrl.text.trim());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    if (_id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.colorTarjeta,
        title: const Text('Eliminar producto'),
        content: Text(
            '¿Eliminar definitivamente el producto #${_id!} — ${_nombreCtrl.text}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final api = context.read<ApiService>();
    try {
      await api.eliminarProducto(_id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Producto #${_id!} eliminado'),
          backgroundColor: Colors.green[800],
        ),
      );
      _nuevoProducto();
      await _recargarCatalogo();
      await _refrescarListaBusqueda(_buscarCtrl.text.trim());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _copiarProducto(int idOrigen, String nombreDefault) async {
    final nombreCtrl = TextEditingController(text: nombreDefault);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.colorTarjeta,
        title: const Text('Copiar producto'),
        content: TextField(
          controller: nombreCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre del nuevo producto',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Copiar'),
          ),
        ],
      ),
    );
    final nombreCopia = nombreCtrl.text.trim();
    nombreCtrl.dispose();
    if (ok != true || !mounted) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final api = context.read<ApiService>();
    try {
      final nuevoId = await api.copiarProducto(
        idOrigen: idOrigen,
        nombreProducto: nombreCopia.isEmpty ? null : nombreCopia,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copia creada (id $nuevoId)'),
          backgroundColor: Colors.green[800],
        ),
      );
      await _recargarCatalogo();
      await _refrescarListaBusqueda(_buscarCtrl.text.trim());
      await _cargarProducto(nuevoId);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _buildSeccionOpciones(CatalogoProvider catalogo) {
    final grupos = _gruposDisponibles(catalogo);
    if (grupos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'No hay grupos en grupos_opciones. Añádalos en la base de datos.',
          style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 14),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Opciones (grupos_opciones → productos_opciones)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Cada fila es una opción del producto enlazada a un grupo del catálogo. '
          'Solo puede haber una opción predeterminada por grupo.',
          style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _grupoParaNuevaFila != null &&
                        grupos.any((g) => g.id == _grupoParaNuevaFila)
                    ? _grupoParaNuevaFila
                    : grupos.first.id,
                decoration: const InputDecoration(
                  labelText: 'Grupo para nueva fila',
                  filled: true,
                  fillColor: AppTheme.colorSuperficie,
                ),
                items: grupos
                    .map((g) => DropdownMenuItem(
                          value: g.id,
                          child: Text(
                            g.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _grupoParaNuevaFila = v ?? grupos.first.id),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _guardando ? null : _anadirFilaOpcion,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Añadir'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._filasOpciones.map((f) => _tarjetaFilaOpcion(f, grupos)),
      ],
    );
  }

  Widget _tarjetaFilaOpcion(_FilaOpcionEdit f, List<GrupoOpciones> grupos) {
    final gid =
        grupos.any((g) => g.id == f.idGrupo) ? f.idGrupo : grupos.first.id;
    return Card(
      color: AppTheme.colorSuperficie,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    initialValue: gid,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Grupo (grupos_opciones)',
                      isDense: true,
                    ),
                    items: grupos
                        .map((g) => DropdownMenuItem(
                              value: g.id,
                              child: Text(
                                g.nombre,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: _guardando
                        ? null
                        : (v) {
                            if (v != null) _onGrupoFilaCambiado(f, v);
                          },
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar fila',
                  onPressed: _guardando ? null : () => _quitarFila(f),
                  icon: const Icon(Icons.close, color: AppTheme.colorAcento),
                ),
              ],
            ),
            TextField(
              controller: f.nombre,
              enabled: !_guardando,
              decoration: const InputDecoration(
                labelText: 'Nombre opción (productos_opciones)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 88,
                  child: TextField(
                    controller: f.orden,
                    enabled: !_guardando,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Orden',
                      isDense: true,
                    ),
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    title: const Text('Predeterminada',
                        style: TextStyle(fontSize: 14)),
                    dense: true,
                    value: f.predeterminado,
                    onChanged: _guardando
                        ? null
                        : (v) => _setPredeterminadoSoloEnGrupo(f, v ?? false),
                  ),
                ),
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Disponible',
                        style: TextStyle(fontSize: 14)),
                    dense: true,
                    value: f.disponible,
                    onChanged: _guardando
                        ? null
                        : (v) => setState(() => f.disponible = v),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = context.watch<CatalogoProvider>();
    final cats = catalogo.categorias.toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));
    final imps = catalogo.impresoras.toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));

    return Scaffold(
      appBar: AppBar(
        title: Text(_id == null ? 'Nuevo producto' : 'Producto #$_id'),
        actions: [
          TextButton.icon(
            onPressed: _guardando ? null : _nuevoProducto,
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            label: const Text('Nuevo', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _buscarCtrl,
              decoration: const InputDecoration(
                labelText: 'Buscar producto (nombre o id)',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: AppTheme.colorSuperficie,
              ),
              onChanged: _onBuscarChanged,
            ),
          ),
          SizedBox(
            height: 160,
            child: _cargandoLista
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _listaBusqueda.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final r = _listaBusqueda[i];
                      final idP =
                          int.tryParse(r['id_producto'].toString()) ?? 0;
                      final nom = r['nombre_producto']?.toString() ?? '';
                      return ListTile(
                        dense: true,
                        title: Text(nom,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('id $idP · cat ${r['id_categoria']}'),
                        onTap: () => _cargarProducto(idP),
                        trailing: IconButton(
                          tooltip: 'Copiar como nuevo',
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: _guardando
                              ? null
                              : () => _copiarProducto(idP, '$nom (copia)'),
                        ),
                      );
                    },
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_error!,
                  style: const TextStyle(color: AppTheme.colorAcento)),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                TextField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del producto',
                    filled: true,
                    fillColor: AppTheme.colorSuperficie,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _idCategoria != null &&
                          cats.any((c) => c.id == _idCategoria)
                      ? _idCategoria
                      : (cats.isNotEmpty ? cats.first.id : null),
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    filled: true,
                    fillColor: AppTheme.colorSuperficie,
                  ),
                  items: cats
                      .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.nombre,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _idCategoria = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _textoImprimirCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Texto ticket / cocina',
                    hintText: 'Si vacío, se usa el nombre',
                    filled: true,
                    fillColor: AppTheme.colorSuperficie,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _idImpresora,
                  decoration: const InputDecoration(
                    labelText: 'Impresora',
                    filled: true,
                    fillColor: AppTheme.colorSuperficie,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('Sin impresora (0)'),
                    ),
                    ...imps.map((imp) => DropdownMenuItem(
                          value: imp.id,
                          child: Text(
                            imp.nombre.isEmpty ? 'Imp. ${imp.id}' : imp.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: (v) => setState(() => _idImpresora = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ordenCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Orden (opcional; vacío = automático al crear)',
                    filled: true,
                    fillColor: AppTheme.colorSuperficie,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Disponible en carta'),
                  value: _disponible,
                  onChanged: (v) => setState(() => _disponible = v),
                ),
                _buildSeccionOpciones(catalogo),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                if (_id != null)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[900],
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _guardando ? null : _eliminar,
                    child: const Icon(Icons.delete_outline),
                  ),
                if (_id != null) const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _guardando ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_id == null ? 'Crear' : 'Guardar cambios'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
