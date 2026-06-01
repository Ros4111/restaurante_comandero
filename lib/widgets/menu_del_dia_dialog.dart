// lib/widgets/menu_del_dia_dialog.dart
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/catalogo_provider.dart';
import '../utils/precio_redondeo.dart';
import '../utils/theme.dart';

/// Pantalla completa para componer un Menú del Día.
class MenuDelDiaDialog extends StatefulWidget {
  final Producto productoMenu;
  final MenuDelDiaConfig config;
  final CatalogoProvider catalogo;
  final MenuDelDiaSeleccion? seleccionInicial;
  final bool modoEdicion;

  const MenuDelDiaDialog({
    super.key,
    required this.productoMenu,
    required this.config,
    required this.catalogo,
    this.seleccionInicial,
    this.modoEdicion = false,
  });

  @override
  State<MenuDelDiaDialog> createState() => _MenuDelDiaDialogState();
}

class _MenuDelDiaDialogState extends State<MenuDelDiaDialog> {
  bool _dosPrimeros = false;
  bool _dosSegundos = false;
  final Set<int> _primeros = {};
  final Set<int> _segundos = {};
  int? _bebidaMenuId;
  int? _bebidaAlternativaId;
  int? _postreId;
  bool _sinPostre = true;
  final TextEditingController _comentCtrl = TextEditingController();
  final TextEditingController _busqBebidaCtrl = TextEditingController();
  String _busqBebida = '';

  @override
  void initState() {
    super.initState();
    final ini = widget.seleccionInicial;
    if (ini == null) return;
    _dosPrimeros = ini.dosPrimeros;
    _dosSegundos = ini.dosSegundos;
    _primeros.addAll(ini.primeros);
    _segundos.addAll(ini.segundos);
    if (ini.bebidaId != null) {
      if (ini.bebidaDelMenu) {
        _bebidaMenuId = ini.bebidaId;
      } else {
        _bebidaAlternativaId = ini.bebidaId;
      }
    }
    if (ini.postreId != null) {
      _sinPostre = false;
      _postreId = ini.postreId;
    }
    _comentCtrl.text = ini.comentarioExtra;
  }

  @override
  void dispose() {
    _comentCtrl.dispose();
    _busqBebidaCtrl.dispose();
    super.dispose();
  }

  List<MenuDelDiaProductoItem> get _primerosLista =>
      widget.config.productosGrupo('primero');
  List<MenuDelDiaProductoItem> get _segundosLista =>
      widget.config.productosGrupo('segundo');
  List<MenuDelDiaProductoItem> get _bebidasMenu =>
      widget.config.productosGrupo('bebida');
  List<MenuDelDiaProductoItem> get _postresLista =>
      widget.config.productosGrupo('postre');

  bool get _primerosBloqueados => _dosSegundos;
  bool get _segundosBloqueados => _dosPrimeros;

  int get _limitePrimeros => _dosPrimeros ? 2 : (_dosSegundos ? 0 : 1);
  int get _limiteSegundos => _dosSegundos ? 2 : (_dosPrimeros ? 0 : 1);

  bool _esBebidaCatalogo(Producto p) {
    if (p.filtro == MenuDelDiaConfig.filtroProductoMenu) return false;
    final cat = widget.catalogo.categorias
        .where((c) => c.id == p.idCategoria)
        .firstOrNull;
    if (cat == null) return false;
    final n = cat.nombre.toLowerCase();
    const claves = [
      'café',
      'cafe',
      'cerveza',
      'refresco',
      'cubata',
      'vino',
      'espirituosa',
      'infusion',
      'zumo',
    ];
    return claves.any((k) => n.contains(k));
  }

  List<Producto> get _bebidasCatalogo {
    final q = _busqBebida.trim().toLowerCase();
    final out = widget.catalogo.productos.where((p) {
      if (!p.disponible) return false;
      if (!_esBebidaCatalogo(p)) return false;
      if (q.isEmpty) return true;
      return p.nombreProductoPantalla.toLowerCase().contains(q) ||
          p.filtro.toLowerCase().contains(q);
    }).toList();
    out.sort((a, b) =>
        a.nombreProductoPantalla.compareTo(b.nombreProductoPantalla));
    return out;
  }

  double _pvpProducto(Producto p) => pvpUnitarioDesdeBaseSinIva(
        baseSinIvaUnitaria: p.baseImponible,
        porcentajeIva: p.porcentajeIVA,
      );

  double _pvpBebidaAlternativa(Producto p) {
    final pvp = _pvpProducto(p);
    final d = widget.config.descuentoBebidaAlternativaPct;
    if (d <= 0) return pvp;
    return redondearMoneda(pvp * (1.0 - d / 100.0));
  }

  double get _pvpEstimado {
    var total = pvpUnitarioDesdeBaseSinIva(
      baseSinIvaUnitaria: widget.productoMenu.baseImponible,
      porcentajeIva: widget.productoMenu.porcentajeIVA,
    );
    if (_bebidaAlternativaId != null) {
      final p = widget.catalogo.productoPorId(_bebidaAlternativaId!);
      if (p != null) total += _pvpBebidaAlternativa(p);
    }
    return total;
  }

  void _activarDosPrimeros(bool v) {
    setState(() {
      _dosPrimeros = v;
      if (v) {
        _dosSegundos = false;
        _segundos.clear();
      }
      if (!v && _primeros.length > 2) {
        final lista = _primeros.toList()..sort();
        _primeros
          ..clear()
          ..addAll(lista.take(2));
      }
    });
  }

  void _activarDosSegundos(bool v) {
    setState(() {
      _dosSegundos = v;
      if (v) {
        _dosPrimeros = false;
        _primeros.clear();
      }
      if (!v && _segundos.length > 2) {
        final lista = _segundos.toList()..sort();
        _segundos
          ..clear()
          ..addAll(lista.take(2));
      }
    });
  }

  void _toggleSeleccion(Set<int> set, int id, int limite, bool habilitado) {
    if (!habilitado || limite <= 0) return;
    setState(() {
      if (set.contains(id)) {
        set.remove(id);
      } else if (set.length < limite) {
        set.add(id);
      } else if (limite == 1) {
        set
          ..clear()
          ..add(id);
      } else {
        final first = set.first;
        set
          ..clear()
          ..add(first == id ? set.last : first)
          ..add(id);
      }
    });
  }

  void _seleccionarBebidaMenu(int id) {
    setState(() {
      _bebidaMenuId = id;
      _bebidaAlternativaId = null;
    });
  }

  void _seleccionarBebidaAlternativa(int id) {
    setState(() {
      _bebidaAlternativaId = id;
      _bebidaMenuId = null;
    });
  }

  String? _validar() {
    if (_dosPrimeros) {
      if (_primeros.length != 2) return 'Elige 2 primeros platos';
    } else if (_dosSegundos) {
      if (_segundos.length != 2) return 'Elige 2 segundos platos';
    } else {
      if (_primeros.length != 1) return 'Elige un primer plato';
      if (_segundos.length != 1) return 'Elige un segundo plato';
    }
    if (_bebidaMenuId == null && _bebidaAlternativaId == null) {
      return 'Elige una bebida';
    }
    if (!_sinPostre && _postreId == null) {
      return 'Elige un postre o marca «Sin postre»';
    }
    return null;
  }

  void _confirmar() {
    final err = _validar();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppTheme.colorAgotado),
      );
      return;
    }
    final bebidaId = _bebidaMenuId ?? _bebidaAlternativaId;
    Navigator.pop(context, {
      'primeros': _primeros.toList(),
      'segundos': _segundos.toList(),
      'bebida_id': bebidaId,
      'bebida_del_menu': _bebidaMenuId != null,
      'postre_id': _sinPostre ? null : _postreId,
      'comentario': _comentCtrl.text.trim(),
      'dos_primeros': _dosPrimeros,
      'dos_segundos': _dosSegundos,
    });
  }

  Widget _tituloSeccion(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          t,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: AppTheme.colorPrimario,
          ),
        ),
      );

  Widget _opcionMulti(
    MenuDelDiaProductoItem item,
    Set<int> seleccion,
    int limite,
    bool habilitado,
  ) {
    final sel = seleccion.contains(item.id);
    return CheckboxListTile(
      dense: true,
      value: sel,
      onChanged: habilitado && !item.agotado
          ? (_) => _toggleSeleccion(seleccion, item.id, limite, habilitado)
          : null,
      title: Text(
        item.nombre,
        style: TextStyle(
          fontSize: 16,
          color: item.agotado || !habilitado
              ? AppTheme.colorTextoGris
              : AppTheme.colorTexto,
          decoration: item.agotado ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: item.agotado
          ? const Text('AGOTADO', style: TextStyle(color: AppTheme.colorAgotado))
          : null,
      activeColor: AppTheme.colorPrimario,
    );
  }

  Widget _opcionBebidaMenu(MenuDelDiaProductoItem item) {
    final sel = _bebidaMenuId == item.id;
    return ListTile(
      dense: true,
      enabled: !item.agotado,
      leading: Icon(
        sel ? Icons.radio_button_checked : Icons.radio_button_off,
        color: sel ? AppTheme.colorPrimario : AppTheme.colorTextoGris,
      ),
      title: Text(
        item.nombre,
        style: TextStyle(
          color: item.agotado ? AppTheme.colorTextoGris : AppTheme.colorTexto,
          decoration: item.agotado ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: item.agotado
          ? const Text('AGOTADO', style: TextStyle(color: AppTheme.colorAgotado))
          : const Text('Incluida en el menú'),
      onTap: item.agotado ? null : () => _seleccionarBebidaMenu(item.id),
    );
  }

  Widget _opcionBebidaCatalogo(Producto p) {
    final sel = _bebidaAlternativaId == p.id;
    final pvp = _pvpBebidaAlternativa(p);
    final desc = widget.config.descuentoBebidaAlternativaPct;
    return ListTile(
      dense: true,
      enabled: !p.agotado,
      leading: Icon(
        sel ? Icons.radio_button_checked : Icons.radio_button_off,
        color: sel ? AppTheme.colorPrimario : AppTheme.colorTextoGris,
      ),
      title: Text(
        p.nombreProductoPantalla,
        style: TextStyle(
          color: p.agotado ? AppTheme.colorTextoGris : AppTheme.colorTexto,
        ),
      ),
      subtitle: Text(
        p.agotado
            ? 'AGOTADO'
            : desc > 0
                ? '${pvp.toStringAsFixed(2)} € (desc. ${desc.toStringAsFixed(0)}%)'
                : '${pvp.toStringAsFixed(2)} € · precio carta',
        style: const TextStyle(fontSize: 12),
      ),
      onTap: p.agotado ? null : () => _seleccionarBebidaAlternativa(p.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.colorFondo,
      appBar: AppBar(
        title: Text(widget.productoMenu.nombreProductoPantalla),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.modoEdicion)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Quitar menú del pedido',
              onPressed: () => Navigator.pop(context, {'eliminar': true}),
            ),
          TextButton(
            onPressed: _confirmar,
            child: Text(
              widget.modoEdicion ? 'Guardar' : 'Añadir',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'PVP menú estimado: ${_pvpEstimado.toStringAsFixed(2)} €',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.colorTextoGris,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                _tituloSeccion('Primeros platos'),
                if (_primerosBloqueados)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'No aplica: has elegido 2 segundos',
                      style: TextStyle(color: AppTheme.colorTextoGris),
                    ),
                  )
                else ...[
                  CheckboxListTile(
                    dense: true,
                    value: _dosPrimeros,
                    onChanged: (v) => _activarDosPrimeros(v ?? false),
                    title: const Text('2 primeros (sin segundo)'),
                    subtitle: const Text(
                      'Sustituye el segundo por otro primero',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (_primerosLista.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'No hay primeros configurados hoy',
                        style: TextStyle(color: AppTheme.colorAgotado),
                      ),
                    )
                  else
                    ..._primerosLista.map(
                      (p) => _opcionMulti(
                        p,
                        _primeros,
                        _limitePrimeros,
                        !_primerosBloqueados,
                      ),
                    ),
                ],
                _tituloSeccion('Segundos platos'),
                if (_segundosBloqueados)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'No aplica: has elegido 2 primeros',
                      style: TextStyle(color: AppTheme.colorTextoGris),
                    ),
                  )
                else ...[
                  CheckboxListTile(
                    dense: true,
                    value: _dosSegundos,
                    onChanged: (v) => _activarDosSegundos(v ?? false),
                    title: const Text('2 segundos (sin primero)'),
                  ),
                  if (_segundosLista.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'No hay segundos configurados hoy',
                        style: TextStyle(color: AppTheme.colorAgotado),
                      ),
                    )
                  else
                    ..._segundosLista.map(
                      (p) => _opcionMulti(
                        p,
                        _segundos,
                        _limiteSegundos,
                        !_segundosBloqueados,
                      ),
                    ),
                ],
                _tituloSeccion('Bebida del menú'),
                if (_bebidasMenu.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'No hay bebidas en el menú de hoy',
                      style: TextStyle(color: AppTheme.colorTextoGris),
                    ),
                  )
                else
                  ..._bebidasMenu.map(_opcionBebidaMenu),
                _tituloSeccion('Otra bebida (precio carta)'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    widget.config.descuentoBebidaAlternativaPct > 0
                        ? 'Se cobra a precio de carta con ${widget.config.descuentoBebidaAlternativaPct.toStringAsFixed(0)}% de descuento.'
                        : 'Se cobra a precio normal de carta.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.colorTextoGris,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _busqBebidaCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Buscar bebida en carta…',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _busqBebida = v),
                  ),
                ),
                if (_bebidasCatalogo.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'No hay bebidas en carta que coincidan',
                      style: TextStyle(color: AppTheme.colorTextoGris),
                    ),
                  )
                else
                  ..._bebidasCatalogo.map(_opcionBebidaCatalogo),
                _tituloSeccion('Postre (opcional)'),
                RadioGroup<bool>(
                  groupValue: _sinPostre,
                  onChanged: (v) {
                    if (v == null) return;
                    if (!v && _postresLista.isEmpty) return;
                    setState(() {
                      _sinPostre = v;
                      if (v) _postreId = null;
                    });
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RadioListTile<bool>(
                        dense: true,
                        value: true,
                        title: const Text('Sin postre (elegir después)'),
                        activeColor: AppTheme.colorPrimario,
                      ),
                      RadioListTile<bool>(
                        dense: true,
                        value: false,
                        title: Text(
                          'Elegir postre ahora',
                          style: TextStyle(
                            color: _postresLista.isEmpty
                                ? AppTheme.colorTextoGris
                                : null,
                          ),
                        ),
                        activeColor: AppTheme.colorPrimario,
                      ),
                    ],
                  ),
                ),
                if (!_sinPostre)
                  ..._postresLista.map((p) {
                    final sel = _postreId == p.id;
                    return ListTile(
                      dense: true,
                      enabled: !p.agotado,
                      leading: Icon(
                        sel
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color:
                            sel ? AppTheme.colorPrimario : AppTheme.colorTextoGris,
                      ),
                      title: Text(p.nombre),
                      onTap: p.agotado
                          ? null
                          : () => setState(() => _postreId = p.id),
                    );
                  }),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _comentCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Comentario (opcional)',
                    ),
                    maxLines: 2,
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
