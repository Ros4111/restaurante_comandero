// lib/widgets/catalogo_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';

class CatalogoPanel extends StatefulWidget {
  final void Function(Producto) onTap;
  final void Function(Producto) onLongPress;

  const CatalogoPanel(
      {super.key, required this.onTap, required this.onLongPress});

  @override
  State<CatalogoPanel> createState() => _CatalogoPanelState();
}

class _CatalogoPanelState extends State<CatalogoPanel> {
  final List<Categoria?> _stack = [null]; // null = raíz (idPadre=1)

  int get _currentId => _stack.last?.id ?? 1;

  void _push(Categoria cat) => setState(() => _stack.add(cat));
  void _pop() {
    if (_stack.length > 1) setState(() => _stack.removeLast());
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = context.watch<CatalogoProvider>();
    if (!catalogo.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final subcats = catalogo.categoriasHijo(_currentId);
    final prods = catalogo.productosDeCategoria(_currentId);
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
                TextButton(
                  onPressed: _pop,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '<- ${_stack.last?.nombre ?? ''}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (!hayAtras)
                const Expanded(
                  child: Text(
                    'Menú',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero, // SIN padding exterior
            children: [
              // Subcategorías — sin icono, sin padding extra
              ...subcats.asMap().entries.map(
                    (entry) => _CatTile(
                      cat: entry.value,
                      onTap: () => _push(entry.value),
                      backgroundColor: entry.key.isEven
                          ? AppTheme.colorTarjeta
                          : AppTheme.colorSuperficie,
                    ),
                  ),
              // Productos
              ...prods.asMap().entries.map(
                    (entry) => _ProdTile(
                      p: entry.value,
                      onTap: () => widget.onTap(entry.value),
                      onLongPress: () => widget.onLongPress(entry.value),
                      backgroundColor: (subcats.length + entry.key).isEven
                          ? AppTheme.colorTarjeta
                          : AppTheme.colorSuperficie,
                    ),
                  ),
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
  final Color backgroundColor;
  const _CatTile({
    required this.cat,
    required this.onTap,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        // Sin margin, borde inferior fino como separador
        decoration: BoxDecoration(
          color: backgroundColor,
          border:
              const Border(bottom: BorderSide(color: Colors.black26, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Text(
          cat.nombre,
          style: const TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
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
  final Color backgroundColor;
  const _ProdTile({
    required this.p,
    required this.onTap,
    required this.onLongPress,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: const Border(
            bottom: BorderSide(color: Colors.black26, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Text(
          p.nombre,
          style: const TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
