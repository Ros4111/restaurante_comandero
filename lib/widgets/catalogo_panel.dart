// lib/widgets/catalogo_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';

class CatalogoPanel extends StatefulWidget {
  final void Function(Producto) onTap;
  final void Function(Producto) onLongPress;

  const CatalogoPanel({super.key, required this.onTap, required this.onLongPress});

  @override
  State<CatalogoPanel> createState() => _CatalogoPanelState();
}

class _CatalogoPanelState extends State<CatalogoPanel> {
  // Pila de navegación de categorías (empieza en raíz = 1)
  final List<Categoria?> _stack = [null]; // null = raíz (idPadre=1)

  int get _currentId => _stack.last?.id ?? 1;

  void _push(Categoria cat) => setState(() => _stack.add(cat));
  void _pop() { if (_stack.length > 1) setState(() => _stack.removeLast()); }

  @override
  Widget build(BuildContext context) {
    final catalogo = context.watch<CatalogoProvider>();
    if (!catalogo.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final subcats  = catalogo.categoriasHijo(_currentId);
    final prods    = catalogo.productosDeCategoria(_currentId);
    final hayAtras = _stack.length > 1;

    return Column(
      children: [
        // Cabecera con ruta actual
        Container(
          color: AppTheme.colorSuperficie,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (hayAtras)
                TextButton.icon(
                  onPressed: _pop,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Volver'),
                ),
              Expanded(
                child: Text(_stack.last?.nombre ?? 'Menú',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              // Subcategorías
              ...subcats.map((cat) => _CatTile(cat: cat, onTap: () => _push(cat))),
              // Productos
              ...prods.map((p) => _ProdTile(
                    p: p,
                    onTap: () => widget.onTap(p),
                    onLongPress: () => widget.onLongPress(p),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

class _CatTile extends StatelessWidget {
  final Categoria cat;
  final VoidCallback onTap;
  const _CatTile({required this.cat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.colorCategorias,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        title: Text(cat.nombre,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white),
        onTap: onTap,
      ),
    );
  }
}

class _ProdTile extends StatelessWidget {
  final Producto p;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _ProdTile({required this.p, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final color = p.personalizable ? AppTheme.colorProductoPersonalizable : AppTheme.colorProductoNormal;
    return Card(
      color: AppTheme.colorTarjeta,
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha:0.4), width: 1)),
      child: ListTile(
        title: Text(p.nombre, style: TextStyle(color: color, fontSize: 17)),
        subtitle: p.personalizable
            ? const Text('Personalizable · manten pulsado',
                style: TextStyle(color: AppTheme.colorTextoGris, fontSize: 12))
            : null,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
