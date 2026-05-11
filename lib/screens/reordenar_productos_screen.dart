// lib/screens/reordenar_productos_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';

/// Representa un elemento de la lista reordenable (categoría o producto).
class _ItemOrden {
  final String tipo; // 'categoria' | 'producto'
  final int id;
  final String nombre;
  int orden;

  _ItemOrden({
    required this.tipo,
    required this.id,
    required this.nombre,
    required this.orden,
  });
}

class ReordenarProductosScreen extends StatefulWidget {
  const ReordenarProductosScreen({super.key});

  @override
  State<ReordenarProductosScreen> createState() =>
      _ReordenarProductosScreenState();
}

class _ReordenarProductosScreenState extends State<ReordenarProductosScreen> {
  // Categoría padre seleccionada (null = Root)
  Categoria? _categoriaPadre;

  List<_ItemOrden> _items = [];
  bool _guardando = false;
  bool _modificado = false;

  // ── helpers ────────────────────────────────────────────────

  CatalogoProvider get _catalogo => context.read<CatalogoProvider>();

  /// Categorías hijas (incluidas no disponibles) del padre dado.
  List<Categoria> _subcategorias(int idPadre) =>
      _catalogo.categorias.where((c) => c.idPadre == idPadre).toList()
        ..sort((a, b) => a.orden.compareTo(b.orden));

  /// Productos (incluidos no disponibles) de una categoría.
  List<Producto> _productos(int idCategoria) =>
      _catalogo.productos.where((p) => p.idCategoria == idCategoria).toList()
        ..sort((a, b) => a.orden.compareTo(b.orden));

  void _cargarItems() {
    final idPadre = _categoriaPadre?.id ?? 0;
    final subs = _subcategorias(idPadre);
    final prods = _productos(idPadre);

    // Mezclamos categorías y productos, ordenados por su campo orden actual.
    final todos = <_ItemOrden>[
      for (final c in subs)
        _ItemOrden(
            tipo: 'categoria', id: c.id, nombre: c.nombre, orden: c.orden),
      for (final p in prods)
        _ItemOrden(
            tipo: 'producto',
            id: p.id,
            nombre: p.nombreProductoPantalla,
            orden: p.orden),
    ]..sort((a, b) => a.orden.compareTo(b.orden));

    setState(() {
      _items = todos;
      _modificado = false;
    });
  }

  // ── lifecycle ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Diferimos para tener el contexto listo.
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarItems());
  }

  // ── acciones ───────────────────────────────────────────────

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
      _modificado = true;
    });
  }

  Future<void> _guardar() async {
    if (!_modificado) return;

    setState(() => _guardando = true);
    try {
      // Reasignamos órdenes según posición actual (1-indexed).
      final payload = <Map<String, dynamic>>[];
      for (int i = 0; i < _items.length; i++) {
        payload.add({
          'tipo': _items[i].tipo,
          'id': _items[i].id,
          'orden': i + 1,
        });
      }

      final apiService = context.read<ApiService>();
      final catalogo = context.read<CatalogoProvider>();

      await apiService.reordenarCatalogo(payload);

      // Actualizamos el proveedor local para que el resto de la app refleje
      // el nuevo orden sin necesidad de recargar el catálogo completo.
      for (int i = 0; i < _items.length; i++) {
        final nuevoOrden = i + 1;
        final item = _items[i];
        if (item.tipo == 'categoria') {
          final idx = catalogo.categorias.indexWhere((c) => c.id == item.id);
          if (idx >= 0) {
            catalogo.categorias[idx] = Categoria(
              id: catalogo.categorias[idx].id,
              idPadre: catalogo.categorias[idx].idPadre,
              nombre: catalogo.categorias[idx].nombre,
              nombreImagen: catalogo.categorias[idx].nombreImagen,
              disponible: catalogo.categorias[idx].disponible,
              orden: nuevoOrden,
            );
          }
        } else {
          final idx = catalogo.productos.indexWhere((p) => p.id == item.id);
          if (idx >= 0) {
            catalogo.productos[idx] = Producto(
              id: catalogo.productos[idx].id,
              nombreProductoPantalla:
                  catalogo.productos[idx].nombreProductoPantalla,
              idCategoria: catalogo.productos[idx].idCategoria,
              textoImprimirBarraCocina:
                  catalogo.productos[idx].textoImprimirBarraCocina,
              textoImprimirCliente:
                  catalogo.productos[idx].textoImprimirCliente,
              idImpresora: catalogo.productos[idx].idImpresora,
              disponible: catalogo.productos[idx].disponible,
              orden: nuevoOrden,
            );
          }
        }
      }
      catalogo.notificarCambios();

      setState(() => _modificado = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Orden guardado correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: AppTheme.colorAcento,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ── build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final catalogo = context.watch<CatalogoProvider>();

    // Lista de categorías raíz para el selector (idPadre == 0).
    final categoriasRaiz = catalogo.categorias
        .where((c) => c.idPadre == 0)
        .toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reordenar productos'),
        actions: [
          if (_modificado)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _guardando
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _guardar,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar'),
                    ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Selector de categoría ──────────────────────────
          Container(
            color: AppTheme.colorSuperficie,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.folder_open, color: AppTheme.colorPrimario),
                const SizedBox(width: 10),
                const Text(
                  'Categoría:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CategoryDropdown(
                    value: _categoriaPadre,
                    rootLabel: 'Root (nivel superior)',
                    categorias: categoriasRaiz,
                    allCategorias: catalogo.categorias,
                    onChanged: (cat) {
                      setState(() => _categoriaPadre = cat);
                      _cargarItems();
                    },
                  ),
                ),
              ],
            ),
          ),
          // ── Hint ──────────────────────────────────────────
          if (_items.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.drag_indicator,
                      size: 16, color: AppTheme.colorTextoGris),
                  SizedBox(width: 6),
                  Text(
                    'Arrastra los elementos para cambiar su posición',
                    style:
                        TextStyle(fontSize: 13, color: AppTheme.colorTextoGris),
                  ),
                ],
              ),
            ),
          // ── Lista reordenable ─────────────────────────────
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text(
                      'No hay elementos en esta categoría',
                      style: TextStyle(color: AppTheme.colorTextoGris),
                    ),
                  )
                : ReorderableListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _items.length,
                    onReorder: _onReorder,
                    proxyDecorator: (child, index, animation) =>
                        _ProxyItem(child: child),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return _ItemTile(
                        key: ValueKey('${item.tipo}-${item.id}'),
                        item: item,
                        index: index,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Selector de categoría con soporte para Root ────────────────────────────

class _CategoryDropdown extends StatelessWidget {
  final Categoria? value;
  final String rootLabel;
  final List<Categoria> categorias;
  final List<Categoria> allCategorias;
  final ValueChanged<Categoria?> onChanged;

  const _CategoryDropdown({
    required this.value,
    required this.rootLabel,
    required this.categorias,
    required this.allCategorias,
    required this.onChanged,
  });

  /// Construye la lista plana de todas las categorías con indentación visual.
  List<DropdownMenuItem<Categoria?>> _buildItems() {
    final items = <DropdownMenuItem<Categoria?>>[];

    // Opción raíz
    items.add(DropdownMenuItem<Categoria?>(
      value: null,
      child: Text(
        rootLabel,
        style: const TextStyle(fontStyle: FontStyle.italic),
      ),
    ));

    void addLevel(List<Categoria> cats, int depth) {
      for (final c in cats) {
        final prefix = '  ' * depth;
        items.add(DropdownMenuItem<Categoria?>(
          value: c,
          child: Text('$prefix${c.nombre}'),
        ));
        final hijos = allCategorias.where((h) => h.idPadre == c.id).toList()
          ..sort((a, b) => a.orden.compareTo(b.orden));
        if (hijos.isNotEmpty) addLevel(hijos, depth + 1);
      }
    }

    addLevel(categorias, 0);
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButton<Categoria?>(
      value: value,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      dropdownColor: AppTheme.colorTarjeta,
      items: _buildItems(),
      onChanged: onChanged,
    );
  }
}

// ── Tile individual ────────────────────────────────────────────────────────

class _ItemTile extends StatelessWidget {
  final _ItemOrden item;
  final int index;

  const _ItemTile({super.key, required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    final esCategoria = item.tipo == 'categoria';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: esCategoria
          ? AppTheme.colorCategorias.withAlpha(60)
          : AppTheme.colorTarjeta,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: esCategoria
            ? const BorderSide(color: AppTheme.colorCategorias, width: 1)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Icon(
          esCategoria ? Icons.folder : Icons.fastfood_outlined,
          color:
              esCategoria ? AppTheme.colorCategorias : AppTheme.colorPrimario,
        ),
        title: Text(item.nombre),
        subtitle: Text(
          esCategoria ? 'Categoría' : 'Producto',
          style: const TextStyle(fontSize: 12, color: AppTheme.colorTextoGris),
        ),
        trailing: const Icon(
          Icons.drag_handle,
          color: AppTheme.colorTextoGris,
        ),
      ),
    );
  }
}

// ── Decorador del proxy de arrastre ───────────────────────────────────────

class _ProxyItem extends StatelessWidget {
  final Widget child;

  const _ProxyItem({required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: Opacity(opacity: 0.85, child: child),
    );
  }
}
