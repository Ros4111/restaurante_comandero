// lib/screens/historico_mesas_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';

class HistoricoMesasScreen extends StatefulWidget {
  const HistoricoMesasScreen({super.key});

  @override
  State<HistoricoMesasScreen> createState() => _HistoricoMesasScreenState();
}

class _HistoricoMesasScreenState extends State<HistoricoMesasScreen> {
  // Filtro de período: 0 = todo, 1 = hoy, 7 = semana
  int _diasFiltro = 7;
  bool _cargando = true;
  List<MesaHistorico> _todas = [];
  List<MesaHistorico> _filtradas = [];
  final _buscarCtrl = TextEditingController();
  // idPedido → líneas cargadas (null = no cargadas todavía)
  final _detalles = <int, List<LineaHistorico>?>{};
  final _cargandoDetalle = <int, bool>{};
  // Para saber qué tiles están expandidos
  final _expandidos = <int>{};

  @override
  void initState() {
    super.initState();
    _cargar();
    _buscarCtrl.addListener(_filtrar);
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final api = context.read<ApiService>();
      final lista = await api.getHistoricoMesas(dias: _diasFiltro);
      if (!mounted) return;
      setState(() {
        _todas = lista;
        _cargando = false;
      });
      _filtrar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _showError(e.toString());
    }
  }

  void _filtrar() {
    final q = _buscarCtrl.text.trim().toLowerCase();
    setState(() {
      _filtradas = _todas.where((m) {
        if (q.isEmpty) return true;
        if (m.idMesa.toString().contains(q)) return true;
        if (m.nombreCliente.toLowerCase().contains(q)) return true;
        return false;
      }).toList();
    });
  }

  Future<void> _cargarDetalle(int idPedido) async {
    if (_detalles.containsKey(idPedido)) return; // ya cargado
    setState(() => _cargandoDetalle[idPedido] = true);
    try {
      final api = context.read<ApiService>();
      final data = await api.getHistoricoMesaDetalle(idPedido);
      final lineasRaw = data['detalles'] as List? ?? [];
      final lineas =
          lineasRaw.map((j) => LineaHistorico.fromJson(j as Map<String, dynamic>)).toList();
      if (!mounted) return;
      setState(() {
        _detalles[idPedido] = lineas;
        _cargandoDetalle[idPedido] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _detalles[idPedido] = [];
        _cargandoDetalle[idPedido] = false;
      });
      _showError(e.toString());
    }
  }

  Future<void> _reabrir(MesaHistorico mesa) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.colorTarjeta,
        title: Row(
          children: [
            const Icon(Icons.restore, color: Colors.orange),
            const SizedBox(width: 8),
            Text('Reabrir mesa ${mesa.idMesa}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Se creará una nueva mesa activa con los mismos productos '
              'de la mesa ${mesa.idMesa}${mesa.nombreCliente.trim().isNotEmpty ? ' (${mesa.nombreCliente.trim()})' : ''}.',
            ),
            const SizedBox(height: 8),
            Text(
              '${mesa.totalLineas} línea${mesa.totalLineas != 1 ? 's' : ''} · '
              '${mesa.totalImporte > 0 ? '${mesa.totalImporte.toStringAsFixed(2)} €' : 'sin precios almacenados'}',
              style: const TextStyle(
                  color: AppTheme.colorTextoGris, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'Los productos aparecerán como no impresos. El registro histórico original se conserva.',
              style: TextStyle(
                  color: AppTheme.colorTextoGris,
                  fontSize: 12,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    final api = context.read<ApiService>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Color(0xFF1E1E2C),
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Reabriendo mesa…'),
          ],
        ),
      ),
    );

    try {
      final result = await api.reabrirMesa(mesa.idPedido);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // cerrar loading
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Mesa ${result.idMesa} reabierta · pedido #${result.idPedido}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ));
      // Refrescar lista para que el registro aparezca actualizado
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showError(e.toString());
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red[700]));
  }

  // ── Parseo de fecha del servidor (MySQL datetime) ─────────────

  static final _reDatetime = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[\sT]+(\d{1,2}):(\d{2}):(\d{2})',
  );

  DateTime? _parseFecha(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final m = _reDatetime.firstMatch(raw.trim());
    if (m == null) return null;
    try {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }

  String _formatFecha(String? raw) {
    final dt = _parseFecha(raw);
    if (dt == null) return '--';
    final ahora = DateTime.now();
    if (dt.year == ahora.year &&
        dt.month == ahora.month &&
        dt.day == ahora.day) {
      return 'Hoy ${DateFormat('HH:mm').format(dt)}';
    }
    if (dt.year == ahora.year) {
      return DateFormat('dd/MM  HH:mm').format(dt);
    }
    return DateFormat('dd/MM/yy  HH:mm').format(dt);
  }

  // ── BUILD ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de mesas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargar,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Barra de búsqueda + chips de período ──────────────
          Container(
            color: AppTheme.colorTarjeta,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                TextField(
                  controller: _buscarCtrl,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar por mesa o cliente…',
                    hintStyle:
                        const TextStyle(color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        size: 20, color: Colors.white54),
                    suffixIcon: _buscarCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                size: 18, color: Colors.white54),
                            onPressed: () {
                              _buscarCtrl.clear();
                              _filtrar();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppTheme.colorSuperficie,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 8),
                // Chips de período
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _PeriodoChip(
                          label: 'Hoy',
                          activo: _diasFiltro == 1,
                          onTap: () => _setPeriodo(1)),
                      const SizedBox(width: 8),
                      _PeriodoChip(
                          label: '7 días',
                          activo: _diasFiltro == 7,
                          onTap: () => _setPeriodo(7)),
                      const SizedBox(width: 8),
                      _PeriodoChip(
                          label: '30 días',
                          activo: _diasFiltro == 30,
                          onTap: () => _setPeriodo(30)),
                      const SizedBox(width: 8),
                      _PeriodoChip(
                          label: 'Todo',
                          activo: _diasFiltro == 0,
                          onTap: () => _setPeriodo(0)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Contador de resultados ───────────────────────────
          if (!_cargando)
            Container(
              color: AppTheme.colorSuperficie,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              alignment: Alignment.centerLeft,
              child: Text(
                '${_filtradas.length} mesa${_filtradas.length != 1 ? 's' : ''} cerrada${_filtradas.length != 1 ? 's' : ''}',
                style: const TextStyle(
                    color: AppTheme.colorTextoGris, fontSize: 12),
              ),
            ),
          // ── Lista ────────────────────────────────────────────
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _filtradas.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history,
                                size: 64, color: Colors.white12),
                            const SizedBox(height: 12),
                            Text(
                              'No hay mesas cerradas en este período',
                              style: TextStyle(
                                  color: AppTheme.colorTextoGris,
                                  fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                            bottom: 24, top: 4, left: 8, right: 8),
                        itemCount: _filtradas.length,
                        itemBuilder: (ctx, i) =>
                            _MesaHistoricoTile(
                              mesa: _filtradas[i],
                              expandido: _expandidos
                                  .contains(_filtradas[i].idPedido),
                              lineas: _detalles[_filtradas[i].idPedido],
                              cargandoLineas: _cargandoDetalle[
                                      _filtradas[i].idPedido] ??
                                  false,
                              fechaTexto:
                                  _formatFecha(_filtradas[i].horaUltimaAccion),
                              onToggle: () =>
                                  _toggleExpansion(_filtradas[i]),
                              onReabrir: () => _reabrir(_filtradas[i]),
                            ),
                      ),
          ),
        ],
      ),
    );
  }

  void _setPeriodo(int dias) {
    if (_diasFiltro == dias) return;
    setState(() {
      _diasFiltro = dias;
      _expandidos.clear();
    });
    _cargar();
  }

  void _toggleExpansion(MesaHistorico mesa) {
    final id = mesa.idPedido;
    setState(() {
      if (_expandidos.contains(id)) {
        _expandidos.remove(id);
      } else {
        _expandidos.add(id);
        _cargarDetalle(id);
      }
    });
  }
}

// ── Chip de período ───────────────────────────────────────────

class _PeriodoChip extends StatelessWidget {
  final String label;
  final bool activo;
  final VoidCallback onTap;
  const _PeriodoChip(
      {required this.label, required this.activo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: activo
              ? AppTheme.colorPrimario
              : AppTheme.colorSuperficie,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: activo
                ? AppTheme.colorPrimario
                : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                activo ? FontWeight.bold : FontWeight.normal,
            color: activo ? Colors.white : AppTheme.colorTextoGris,
          ),
        ),
      ),
    );
  }
}

// ── Tile de mesa histórica ────────────────────────────────────

class _MesaHistoricoTile extends StatelessWidget {
  final MesaHistorico mesa;
  final bool expandido;
  final List<LineaHistorico>? lineas;
  final bool cargandoLineas;
  final String fechaTexto;
  final VoidCallback onToggle;
  final VoidCallback onReabrir;

  const _MesaHistoricoTile({
    required this.mesa,
    required this.expandido,
    required this.lineas,
    required this.cargandoLineas,
    required this.fechaTexto,
    required this.onToggle,
    required this.onReabrir,
  });

  @override
  Widget build(BuildContext context) {
    final cliente = mesa.nombreCliente.trim();
    final tieneImporte = mesa.totalImporte > 0;

    return Card(
      color: AppTheme.colorTarjeta,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          // ── Cabecera del tile ───────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  // Número de mesa
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.colorSuperficie,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.colorPrimario.withValues(alpha: 0.4)),
                    ),
                    child: Center(
                      child: Text(
                        '${mesa.idMesa}',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info central
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Mesa ${mesa.idMesa}',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold),
                            ),
                            if (cliente.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '· $cliente',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppTheme.colorTextoGris,
                                      fontSize: 13),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$fechaTexto  ·  ${mesa.totalLineas} línea${mesa.totalLineas != 1 ? 's' : ''}',
                          style: const TextStyle(
                              color: AppTheme.colorTextoGris, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Importe
                  if (tieneImporte)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${mesa.totalImporte.toStringAsFixed(2)} €',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.colorPrimario,
                        ),
                      ),
                    ),
                  // Flecha expansión
                  AnimatedRotation(
                    turns: expandido ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more,
                        color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
          // ── Panel expandido (líneas + botón reabrir) ──────────
          if (expandido)
            Container(
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: Colors.black26, width: 1)),
              ),
              child: Column(
                children: [
                  if (cargandoLineas)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (lineas == null || lineas!.isEmpty)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        'Sin líneas registradas',
                        style:
                            TextStyle(color: AppTheme.colorTextoGris),
                      ),
                    )
                  else ...[
                    // Lista de productos
                    ...lineas!.map((l) => _LineaHistoricoRow(linea: l)),
                    // Total calculado desde líneas
                    const Divider(height: 1, indent: 14, endIndent: 14),
                    if (tieneImporte)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text('Total: ',
                                style: TextStyle(
                                    color: AppTheme.colorTextoGris,
                                    fontSize: 13)),
                            Text(
                              '${mesa.totalImporte.toStringAsFixed(2)} €',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppTheme.colorPrimario,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  // Botón reabrir
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onReabrir,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[800],
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Reabrir esta mesa'),
                      ),
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

// ── Fila de línea histórica ───────────────────────────────────

class _LineaHistoricoRow extends StatelessWidget {
  final LineaHistorico linea;
  const _LineaHistoricoRow({required this.linea});

  @override
  Widget build(BuildContext context) {
    final esNota = linea.idProducto == 0;
    final opcNoPred = linea.opcionesElegidas.values
        .where((o) => !o.predeterminado)
        .map((o) => o.nombre)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cantidad
          SizedBox(
            width: 32,
            child: Text(
              '${linea.cantidad}×',
              style: TextStyle(
                color: esNota ? Colors.amber[300] : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Nombre + opciones
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (esNota) ...[
                      Icon(Icons.edit_note,
                          size: 14, color: Colors.amber[300]),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        linea.nombreProducto,
                        style: TextStyle(
                          fontSize: 14,
                          color: esNota ? Colors.amber[300] : Colors.white,
                          fontStyle: esNota
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ),
                  ],
                ),
                for (final op in opcNoPred)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 1),
                    child: Text('▸ $op',
                        style: const TextStyle(
                            color: AppTheme.colorTextoGris, fontSize: 12)),
                  ),
                if (linea.comentario.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 1),
                    child: Text(
                      '📝 ${linea.comentario}',
                      style: const TextStyle(
                          color: AppTheme.colorTextoGris,
                          fontSize: 12,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          ),
          // Precio unitario
          if (linea.pvpUnitario > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${linea.pvpUnitario.toStringAsFixed(2)} €',
                style: const TextStyle(
                    color: AppTheme.colorTextoGris, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
