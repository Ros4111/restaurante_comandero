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
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Volver', style: TextStyle(fontSize: 15)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              Expanded(
                child: Text(_stack.last?.nombre ?? 'Menú',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero, // SIN padding exterior
            children: [
              // Subcategorías — sin icono, sin padding extra
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
    return InkWell(
      onTap: onTap,
      child: Container(
        // Sin margin, borde inferior fino como separador
        decoration: const BoxDecoration(
          color: AppTheme.colorCategorias,
          border: Border(bottom: BorderSide(color: Colors.black26, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Text(
          cat.nombre,
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
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
    final color = p.personalizable
        ? AppTheme.colorProductoPersonalizable
        : AppTheme.colorProductoNormal;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.colorTarjeta,
          border: Border(
            bottom: BorderSide(color: Colors.black26, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          p.nombre,
          style: TextStyle(color: color, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
