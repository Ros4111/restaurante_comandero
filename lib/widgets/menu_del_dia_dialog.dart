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
  /// Tras guardar el pedido: solo elegir postre (una vez).
  final bool soloPostre;
  final String? comentarioCabecera;

  const MenuDelDiaDialog({
    super.key,
    required this.productoMenu,
    required this.config,
    required this.catalogo,
    this.seleccionInicial,
    this.modoEdicion = false,
    this.soloPostre = false,
    this.comentarioCabecera,
  });

  @override
  State<MenuDelDiaDialog> createState() => _MenuDelDiaDialogState();
}

class _MenuDelDiaDialogState extends State<MenuDelDiaDialog> {
  /// Orden de elección: el 1.º tocado es primero, el 2.º es segundo (FIFO si hay 3.º).
  final List<int> _ordenPlatos = [];
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
    if (ini == null) {
      if (widget.soloPostre) _sinPostre = false;
      return;
    }
    _ordenPlatos.addAll(ini.primeros);
    _ordenPlatos.addAll(ini.segundos);
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

  List<int> get _primerosDesdeOrden =>
      _ordenPlatos.isEmpty ? const [] : [_ordenPlatos.first];

  List<int> get _segundosDesdeOrden =>
      _ordenPlatos.length < 2 ? const [] : [_ordenPlatos[1]];

  int? get _idAnclaPrimero =>
      _ordenPlatos.isEmpty ? null : _ordenPlatos.first;

  bool _esPrimero(int id) =>
      _ordenPlatos.isNotEmpty && _ordenPlatos[0] == id;

  bool _esSegundo(int id) =>
      _ordenPlatos.length >= 2 && _ordenPlatos[1] == id;

  bool _mismoPlatoDosVeces(int id) =>
      _ordenPlatos.length == 2 &&
      _ordenPlatos[0] == id &&
      _ordenPlatos[1] == id;

  /// Dos casillas (1º y 2º) solo en el plato elegido primero (o repetido 2×).
  bool _mostrarDosCheckboxes(int id) {
    final ancla = _idAnclaPrimero;
    if (ancla == null || ancla != id) return false;
    return _ordenPlatos.length == 1 || _mismoPlatoDosVeces(id);
  }

  String? _etiquetaPuesto(int id) {
    if (_esPrimero(id) && _esSegundo(id)) return '1º y 2º';
    if (_esPrimero(id)) return '1º';
    if (_esSegundo(id)) return '2º';
    return null;
  }

  String _nombrePlato(int id) {
    final p = widget.catalogo.productoPorId(id);
    if (p != null) return p.nombreProductoPantalla;
    for (final item in [
      ..._primerosLista,
      ..._segundosLista,
      ..._bebidasMenu,
      ..._postresLista,
    ]) {
      if (item.id == id) return item.nombre;
    }
    return '#$id';
  }

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

  bool get _buscandoBebidaCatalogo => _busqBebida.trim().isNotEmpty;

  static const _alturaFilaBebidaBusqueda = 48.0;

  List<Producto> get _bebidasCatalogo {
    final q = _busqBebida.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = widget.catalogo.productos.where((p) {
      if (!p.disponible) return false;
      if (!_esBebidaCatalogo(p)) return false;
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

  void _togglePrimero(int id, bool value) {
    setState(() {
      if (!value) {
        _ordenPlatos.clear();
        return;
      }
      if (_ordenPlatos.isEmpty) {
        _ordenPlatos.add(id);
        return;
      }
      if (_ordenPlatos.length == 1) {
        if (_ordenPlatos[0] == id) return;
        _ordenPlatos[0] = id;
        return;
      }
      _ordenPlatos
        ..removeAt(0)
        ..insert(0, id);
    });
  }

  void _toggleSegundo(int id, bool value) {
    setState(() {
      if (_ordenPlatos.isEmpty || _ordenPlatos[0] != id) return;
      if (!value) {
        if (_ordenPlatos.length >= 2 && _ordenPlatos[1] == id) {
          _ordenPlatos.removeAt(1);
        }
        return;
      }
      if (_ordenPlatos.length == 1) {
        _ordenPlatos.add(id);
      } else if (_ordenPlatos.length == 2 && _ordenPlatos[1] != id) {
        _ordenPlatos[1] = id;
      }
    });
  }

  void _seleccionarPlato(int id) {
    setState(() {
      if (_ordenPlatos.isEmpty) {
        _ordenPlatos.add(id);
        return;
      }
      if (_ordenPlatos.length == 1) {
        if (_ordenPlatos[0] == id) {
          _ordenPlatos.add(id);
        } else {
          _ordenPlatos.add(id);
        }
        return;
      }
      if (_esPrimero(id) && _esSegundo(id)) {
        _ordenPlatos.removeAt(1);
        return;
      }
      if (_esSegundo(id)) {
        _ordenPlatos.removeAt(1);
        return;
      }
      if (_esPrimero(id)) {
        _ordenPlatos.removeAt(0);
        return;
      }
      _ordenPlatos
        ..removeAt(0)
        ..add(id);
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
    if (widget.soloPostre) {
      if (_postreId == null) return 'Elige un postre';
      return null;
    }
    if (_ordenPlatos.length != 2) {
      return 'Elige 2 platos: el primero que toques es 1º, el segundo es 2º';
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
    if (widget.soloPostre) {
      Navigator.pop(context, {'postre_id': _postreId});
      return;
    }
    Navigator.pop(context, {
      'primeros': _primerosDesdeOrden,
      'segundos': _segundosDesdeOrden,
      'bebida_id': bebidaId,
      'bebida_del_menu': _bebidaMenuId != null,
      'postre_id': _sinPostre ? null : _postreId,
      'comentario': _comentCtrl.text.trim(),
      'dos_primeros': false,
      'dos_segundos': false,
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

  Widget _opcionMulti(MenuDelDiaProductoItem item) {
    final id = item.id;
    final esPrimero = _esPrimero(id);
    final esSegundo = _esSegundo(id);
    final dosCasillas = _mostrarDosCheckboxes(id);
    final puesto = _etiquetaPuesto(id);

    Widget leading;
    if (dosCasillas) {
      leading = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: esPrimero,
            onChanged: item.agotado
                ? null
                : (v) => _togglePrimero(id, v ?? false),
            activeColor: AppTheme.colorPrimario,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Checkbox(
            value: esSegundo,
            onChanged: item.agotado
                ? null
                : (v) => _toggleSegundo(id, v ?? false),
            activeColor: AppTheme.colorPrimario,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      );
    } else {
      leading = Checkbox(
        value: esPrimero || esSegundo,
        onChanged: item.agotado
            ? null
            : (v) {
                if (v == true) {
                  if (_ordenPlatos.isEmpty) {
                    _togglePrimero(id, true);
                  } else if (_ordenPlatos.length == 1 &&
                      _ordenPlatos[0] != id) {
                    setState(() => _ordenPlatos.add(id));
                  } else {
                    _togglePrimero(id, true);
                  }
                } else {
                  if (esSegundo) {
                    setState(() => _ordenPlatos.removeAt(1));
                  } else if (esPrimero) {
                    _togglePrimero(id, false);
                  }
                }
              },
        activeColor: AppTheme.colorPrimario,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    return ListTile(
      dense: true,
      enabled: !item.agotado,
      leading: leading,
      title: Text(
        item.nombre,
        style: TextStyle(
          fontSize: 16,
          color: item.agotado ? AppTheme.colorTextoGris : AppTheme.colorTexto,
          decoration: item.agotado ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: item.agotado
          ? const Text('AGOTADO', style: TextStyle(color: AppTheme.colorAgotado))
          : puesto != null
              ? Text(
                  'Elegido como $puesto',
                  style: const TextStyle(
                    color: AppTheme.colorPrimario,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null,
      onTap: item.agotado ? null : () => _seleccionarPlato(id),
    );
  }

  Widget _resumenOrdenPlatos() {
    if (_ordenPlatos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          'Toca los platos en el orden que quieras servirlos. '
          'El primero será 1º y el siguiente 2º (aunque esté en la otra lista).',
          style: TextStyle(fontSize: 14, color: AppTheme.colorTextoGris),
        ),
      );
    }
    final partes = <String>[];
    for (var i = 0; i < _ordenPlatos.length; i++) {
      final et = i == 0 ? '1º' : '2º';
      partes.add('$et ${_nombrePlato(_ordenPlatos[i])}');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(
        'Orden: ${partes.join(' · ')}',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppTheme.colorPrimario,
        ),
      ),
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
          fontSize: 16,
          color: item.agotado ? AppTheme.colorTextoGris : AppTheme.colorTexto,
          decoration: item.agotado ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: item.agotado
          ? const Text('AGOTADO', style: TextStyle(color: AppTheme.colorAgotado))
          : null,
      onTap: item.agotado ? null : () => _seleccionarBebidaMenu(item.id),
    );
  }

  Widget _opcionBebidaCatalogo(Producto p) {
    final sel = _bebidaAlternativaId == p.id;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      enabled: !p.agotado,
      leading: Icon(
        sel ? Icons.radio_button_checked : Icons.radio_button_off,
        color: sel ? AppTheme.colorPrimario : AppTheme.colorTextoGris,
      ),
      title: Text(
        p.nombreProductoPantalla,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: p.agotado ? AppTheme.colorTextoGris : AppTheme.colorTexto,
        ),
      ),
      subtitle: p.agotado
          ? const Text('AGOTADO', style: TextStyle(color: AppTheme.colorAgotado))
          : null,
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
          if (widget.modoEdicion && !widget.soloPostre)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Quitar menú del pedido',
              onPressed: () => Navigator.pop(context, {'eliminar': true}),
            ),
          TextButton(
            onPressed: _confirmar,
            child: Text(
              widget.soloPostre
                  ? 'Añadir postre'
                  : (widget.modoEdicion ? 'Guardar' : 'Añadir'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.soloPostre)
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
              children: widget.soloPostre
                  ? _buildSoloPostre()
                  : _buildFormularioCompleto(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSoloPostre() {
    return [
      if ((widget.comentarioCabecera ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            MenuDelDiaSeleccion.comentarioPlatosEnLinea(
              widget.comentarioCabecera!,
            ),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          'Elige el postre de este menú',
          style: TextStyle(
            fontSize: 15,
            color: AppTheme.colorTextoGris,
          ),
        ),
      ),
      _tituloSeccion('Postre'),
      ..._postresLista.map((p) {
        final sel = _postreId == p.id;
        return ListTile(
          dense: true,
          enabled: !p.agotado,
          leading: Icon(
            sel ? Icons.radio_button_checked : Icons.radio_button_off,
            color: sel ? AppTheme.colorPrimario : AppTheme.colorTextoGris,
          ),
          title: Text(
            p.nombre,
            style: TextStyle(
              fontSize: 16,
              decoration: p.agotado ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: p.agotado
              ? const Text(
                  'AGOTADO',
                  style: TextStyle(color: AppTheme.colorAgotado),
                )
              : null,
          onTap: p.agotado ? null : () => setState(() => _postreId = p.id),
        );
      }),
    ];
  }

  List<Widget> _buildFormularioCompleto() {
    return [
      _resumenOrdenPlatos(),
      _tituloSeccion('Primeros platos'),
      if (_primerosLista.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'No hay primeros configurados hoy',
            style: TextStyle(color: AppTheme.colorAgotado),
          ),
        )
      else
        ..._primerosLista.map(_opcionMulti),
      _tituloSeccion('Segundos platos'),
      if (_segundosLista.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'No hay segundos configurados hoy',
            style: TextStyle(color: AppTheme.colorAgotado),
          ),
        )
      else
        ..._segundosLista.map(_opcionMulti),
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
      _tituloSeccion('Otra bebida'),
      if (widget.config.descuentoBebidaAlternativaPct > 0)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Descuento del ${widget.config.descuentoBebidaAlternativaPct.toStringAsFixed(0)}% sobre carta.',
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
      if (_buscandoBebidaCatalogo && _bebidasCatalogo.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'No hay bebidas en carta que coincidan',
            style: TextStyle(color: AppTheme.colorTextoGris),
          ),
        )
      else if (_buscandoBebidaCatalogo)
        SizedBox(
          height: (_bebidasCatalogo.length.clamp(1, 5)) *
              _alturaFilaBebidaBusqueda,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _bebidasCatalogo.length,
            itemBuilder: (_, i) =>
                _opcionBebidaCatalogo(_bebidasCatalogo[i]),
          ),
        ),
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
              sel ? Icons.radio_button_checked : Icons.radio_button_off,
              color: sel ? AppTheme.colorPrimario : AppTheme.colorTextoGris,
            ),
            title: Text(p.nombre),
            onTap: p.agotado ? null : () => setState(() => _postreId = p.id),
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
    ];
  }
}
