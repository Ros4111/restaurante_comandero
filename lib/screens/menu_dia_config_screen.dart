// lib/screens/menu_dia_config_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/catalogo_provider.dart';
import '../services/menu_dia_provider.dart';
import '../utils/theme.dart';

class MenuDiaConfigScreen extends StatefulWidget {
  const MenuDiaConfigScreen({super.key});

  @override
  State<MenuDiaConfigScreen> createState() => _MenuDiaConfigScreenState();
}

class _MenuDiaConfigScreenState extends State<MenuDiaConfigScreen> {
  static const _etiquetasGrupo = {
    'primero': 'Primeros platos',
    'segundo': 'Segundos platos',
    'bebida': 'Bebidas',
    'postre': 'Postres',
  };

  DateTime _fecha = DateTime.now();
  bool _activo = true;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  final TextEditingController _descuentoBebidaCtrl = TextEditingController();
  final TextEditingController _notasCtrl = TextEditingController();
  final Map<String, List<_ProdSel>> _seleccion = {
    for (final g in MenuDelDiaConfig.nombresGrupos) g: <_ProdSel>[],
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _descuentoBebidaCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  String get _fechaStr =>
      '${_fecha.year.toString().padLeft(4, '0')}-${_fecha.month.toString().padLeft(2, '0')}-${_fecha.day.toString().padLeft(2, '0')}';

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data =
          await context.read<ApiService>().getMenuDia(fecha: _fechaStr);
      if (!mounted) return;
      final cfg = MenuDelDiaConfig.fromJson(data);
      final cat = context.read<CatalogoProvider>();
      setState(() {
        _activo = cfg.activo || data['activo'] != false;
        _descuentoBebidaCtrl.text = cfg.descuentoBebidaAlternativaPct > 0
            ? cfg.descuentoBebidaAlternativaPct.toStringAsFixed(0)
            : '';
        _notasCtrl.text = cfg.notas;
        for (final g in MenuDelDiaConfig.nombresGrupos) {
          _seleccion[g] = cfg.productosGrupo(g).map((p) {
            final prod = cat.productoPorId(p.id);
            return _ProdSel(
              id: p.id,
              nombre: p.nombre.isNotEmpty
                  ? p.nombre
                  : (prod?.nombreProductoPantalla ?? '#${p.id}'),
            );
          }).toList();
        }
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  Future<void> _elegirFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _fecha = picked);
    await _cargar();
  }

  Future<void> _anadirProducto(String grupo) async {
    final id = await showDialog<int>(
      context: context,
      builder: (_) => _BuscarProductoDialog(
        excluir: _seleccion.values
            .expand((l) => l)
            .map((e) => e.id)
            .toSet(),
      ),
    );
    if (id == null || !mounted) return;
    final cat = context.read<CatalogoProvider>();
    final p = cat.productoPorId(id);
    if (p == null) return;
    setState(() {
      if (_seleccion[grupo]!.any((e) => e.id == id)) return;
      _seleccion[grupo]!.add(
        _ProdSel(id: id, nombre: p.nombreProductoPantalla),
      );
    });
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final desc =
          double.tryParse(_descuentoBebidaCtrl.text.replaceAll(',', '.')) ?? 0;
      final body = {
        'fecha': _fechaStr,
        'activo': _activo,
        'descuento_bebida_alternativa_pct': desc,
        'notas': _notasCtrl.text.trim(),
        'productos': {
          for (final g in MenuDelDiaConfig.nombresGrupos)
            g: _seleccion[g]!.map((e) => e.id).toList(),
        },
      };
      final data = await context.read<ApiService>().guardarMenuDia(body);
      if (!mounted) return;
      context.read<MenuDelDiaProvider>().cargar(data);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Menú del día guardado'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _seccionGrupo(String grupo) {
    final lista = _seleccion[grupo] ?? [];
    return Card(
      color: AppTheme.colorSuperficie,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _etiquetasGrupo[grupo] ?? grupo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _anadirProducto(grupo),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Añadir'),
                ),
              ],
            ),
            if (lista.isEmpty)
              const Text(
                'Sin productos — añade platos del catálogo',
                style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 13),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < lista.length; i++)
                    InputChip(
                      label: Text(lista[i].nombre),
                      onDeleted: () => setState(() => lista.removeAt(i)),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menú del Día'),
        actions: [
          if (_guardando)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _guardar,
              tooltip: 'Guardar',
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _elegirFecha,
                        icon: const Icon(Icons.calendar_today),
                        label: Text('Fecha: $_fechaStr'),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Menú activo este día'),
                        value: _activo,
                        onChanged: (v) => setState(() => _activo = v),
                      ),
                      TextField(
                        controller: _descuentoBebidaCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText:
                              'Descuento % bebida distinta a la del menú',
                          helperText:
                              '0 = precio normal de carta. Si el cliente elige otra bebida, se cobra el PVP de carta con este descuento.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notasCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notas internas (opcional)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Productos disponibles hoy (deben existir en el catálogo):',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      for (final g in MenuDelDiaConfig.nombresGrupos) _seccionGrupo(g),
                      const SizedBox(height: 8),
                      const Text(
                        'El producto «Menú del Día» (filtro menu_dia) debe existir en '
                        'CRUD productos. Los platos de la lista son productos normales.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.colorTextoGris,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _ProdSel {
  final int id;
  final String nombre;
  _ProdSel({required this.id, required this.nombre});
}

class _BuscarProductoDialog extends StatefulWidget {
  final Set<int> excluir;
  const _BuscarProductoDialog({required this.excluir});

  @override
  State<_BuscarProductoDialog> createState() => _BuscarProductoDialogState();
}

class _BuscarProductoDialogState extends State<_BuscarProductoDialog> {
  final TextEditingController _ctrl = TextEditingController();
  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onTextoChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _resultados = [];
        _buscando = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () => _buscar(q));
  }

  Future<void> _buscar(String q) async {
    setState(() => _buscando = true);
    try {
      final list =
          await context.read<ApiService>().getProductosLista(q: q);
      if (!mounted) return;
      setState(() {
        _resultados = list
            .where((p) =>
                !widget.excluir.contains(int.parse(p['id_producto'].toString())))
            .toList();
        _buscando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.colorTarjeta,
      title: const Text('Añadir producto'),
      content: SizedBox(
        width: 400,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o filtro…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onTextoChanged,
            ),
            if (_buscando) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _resultados.length,
                itemBuilder: (_, i) {
                  final p = _resultados[i];
                  final id = int.parse(p['id_producto'].toString());
                  final nombre = p['nombre_producto_pantalla']?.toString() ?? '';
                  return ListTile(
                    title: Text(nombre),
                    subtitle: Text('#$id · ${p['filtro'] ?? ''}'),
                    onTap: () => Navigator.pop(context, id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
