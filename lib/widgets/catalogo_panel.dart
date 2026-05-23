// lib/widgets/catalogo_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/catalogo_provider.dart';
import '../utils/theme.dart';

/// Texto de categorías / subcategorías (los productos siguen en blanco).
const _colorTextoCategoria = Color.fromARGB(255, 99, 148, 100);

class CatalogoPanel extends StatefulWidget {
  final void Function(Producto) onTap;
  final void Function(Producto) onLongPress;

  /// Búsqueda por texto en pantalla de pedido: si está activa no se muestran categorías.
  final bool busquedaActiva;

  /// true ⇒ coincide con campo [Producto.filtro] (`mm` como prefijo en el campo padre).
  final bool modoCampoFiltro;

  /// Texto a buscar (sin el prefijo `mm` si correspondía).
  final String terminoBusqueda;

  /// Nota / artículo libre (solo en la raíz del catálogo).
  final VoidCallback? onManual;

  const CatalogoPanel({
    super.key,
    required this.onTap,
    required this.onLongPress,
    this.busquedaActiva = false,
    this.modoCampoFiltro = false,
    this.terminoBusqueda = '',
    this.onManual,
  });

  @override
  State<CatalogoPanel> createState() => CatalogoPanelState();
}

class CatalogoPanelState extends State<CatalogoPanel> {
  final List<Categoria?> _stack = [null]; // null = raíz (idPadre=1)

  int get _currentId => _stack.last?.id ?? 1;

  void _push(Categoria cat) => setState(() => _stack.add(cat));
  bool volverCategoriaSuperior() {
    if (_stack.length <= 1) return false;
    setState(() => _stack.removeLast());
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = context.watch<CatalogoProvider>();
    if (!catalogo.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final modoBusqueda = widget.busquedaActiva;
    late final List<Producto> resultadoBusqueda;
    if (modoBusqueda) {
      resultadoBusqueda =
          widget.modoCampoFiltro && widget.terminoBusqueda.trim().isEmpty
              ? const <Producto>[]
              : catalogo.productosPorBusquedaPedido(widget.terminoBusqueda,
                  enFiltro: widget.modoCampoFiltro);
    } else {
      resultadoBusqueda = const [];
    }

    final subcats = modoBusqueda
        ? const <Categoria>[]
        : catalogo.categoriasHijo(_currentId);
    final prods = modoBusqueda
        ? resultadoBusqueda
        : catalogo.productosDeCategoria(_currentId);
    final hayAtras = !modoBusqueda && _stack.length > 1;

    String? etiquetaCabecera;
    if (modoBusqueda) {
      if (widget.modoCampoFiltro && widget.terminoBusqueda.trim().isEmpty) {
        etiquetaCabecera = 'Filtrar campo clave (añade texto tras mm)';
      } else {
        etiquetaCabecera = widget.modoCampoFiltro ? 'Por filtro' : 'Por nombre';
      }
    }

    final showHeader = hayAtras || modoBusqueda;
    final showManual =
        !modoBusqueda && !hayAtras && widget.onManual != null;

    return Column(
      children: [
        if (showHeader)
          Container(
            color: AppTheme.colorSuperficie,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (hayAtras)
                  TextButton(
                    onPressed: volverCategoriaSuperior,
                    style: TextButton.styleFrom(
                      foregroundColor: _colorTextoCategoria,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '<- ${_stack.last?.nombre ?? ''}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _colorTextoCategoria,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (modoBusqueda)
                  Expanded(
                    child: Text(
                      etiquetaCabecera ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _colorTextoCategoria,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (modoBusqueda && prods.isEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Text(
                    widget.modoCampoFiltro &&
                            widget.terminoBusqueda.trim().isEmpty
                        ? 'Escribe después de mm el texto del campo filtro (ej. mmCL)'
                        : 'No hay coincidencias',
                    style: const TextStyle(
                        color: AppTheme.colorTextoGris, fontSize: 15),
                  ),
                ),
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
              if (showManual)
                _ManualTile(
                  onTap: widget.onManual!,
                  backgroundColor: (subcats.length + prods.length).isEven
                      ? AppTheme.colorTarjeta
                      : AppTheme.colorSuperficie,
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
            color: _colorTextoCategoria,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _ManualTile extends StatelessWidget {
  final VoidCallback onTap;
  final Color backgroundColor;

  const _ManualTile({
    required this.onTap,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: const Border(
            bottom: BorderSide(color: Colors.black26, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: const Text(
          'Manualmente',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
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
          p.nombreProductoPantalla,
          style: const TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
