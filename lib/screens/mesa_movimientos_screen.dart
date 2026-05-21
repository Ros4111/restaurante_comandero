// lib/screens/mesa_movimientos_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../utils/theme.dart';

class MesaMovimientosScreen extends StatefulWidget {
  final int idPedido;
  final int idMesa;
  final String? nombreCliente;

  const MesaMovimientosScreen({
    super.key,
    required this.idPedido,
    required this.idMesa,
    this.nombreCliente,
  });

  @override
  State<MesaMovimientosScreen> createState() => _MesaMovimientosScreenState();
}

class _MesaMovimientosScreenState extends State<MesaMovimientosScreen> {
  bool _cargando = true;
  String? _error;
  MesaMovimientos? _datos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data =
          await context.read<ApiService>().getMesaMovimientos(widget.idPedido);
      if (!mounted) return;
      setState(() {
        _datos = data;
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

  String _formatearHora(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '—';
    final parsed = DateTime.tryParse(trimmed.replaceFirst(' ', 'T'));
    if (parsed != null) {
      return DateFormat('dd/MM HH:mm').format(parsed.toLocal());
    }
    if (trimmed.length >= 16) {
      return trimmed.substring(5, 16).replaceFirst('-', '/');
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final cliente = (widget.nombreCliente ?? '').trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          cliente.isNotEmpty
              ? 'Movimientos · Mesa ${widget.idMesa}'
              : 'Movimientos · Mesa ${widget.idMesa}',
        ),
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent)),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : _datos == null
                  ? const Center(child: Text('Sin datos'))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                        children: [
                          if (cliente.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                cliente,
                                style: const TextStyle(
                                  color: AppTheme.colorTextoGris,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          _seccion(
                            titulo: 'Añadidos',
                            icono: Icons.add_circle_outline,
                            color: AppTheme.colorLineasModificadas,
                            items: _datos!.nuevos,
                            subtituloExtra: null,
                          ),
                          _seccion(
                            titulo: 'Eliminados',
                            icono: Icons.remove_circle_outline,
                            color: AppTheme.colorLineasNuevas,
                            items: _datos!.eliminados,
                            subtituloExtra: null,
                          ),
                          _seccion(
                            titulo: 'Enviados a otra mesa',
                            icono: Icons.arrow_forward,
                            color: Colors.orange,
                            items: _datos!.enviados,
                            subtituloExtra: (i) => i.mesaDestino != null
                                ? '→ Mesa ${i.mesaDestino}'
                                : null,
                          ),
                          _seccion(
                            titulo: 'Recibidos de otra mesa',
                            icono: Icons.arrow_back,
                            color: AppTheme.colorPrimario,
                            items: _datos!.recibidos,
                            subtituloExtra: (i) => i.mesaOrigen != null
                                ? '← Mesa ${i.mesaOrigen}'
                                : null,
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _seccion({
    required String titulo,
    required IconData icono,
    required Color color,
    required List<MovimientoMesaItem> items,
    required String? Function(MovimientoMesaItem)? subtituloExtra,
  }) {
    return Card(
      color: AppTheme.colorTarjeta,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: color, size: 22),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  '${items.length}',
                  style: const TextStyle(
                    color: AppTheme.colorTextoGris,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Ningún movimiento',
                  style: TextStyle(
                    color: AppTheme.colorTextoGris,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ...items.map((i) => _filaMovimiento(i, subtituloExtra)),
          ],
        ),
      ),
    );
  }

  Widget _filaMovimiento(
    MovimientoMesaItem i,
    String? Function(MovimientoMesaItem)? subtituloExtra,
  ) {
    final extra = subtituloExtra?.call(i);
    final cant = i.cantidad > 1 ? '  ×${i.cantidad}' : '';
    final usuario =
        i.usuario.trim().isNotEmpty ? i.usuario.trim() : 'Usuario';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              _formatearHora(i.fechaHora),
              style: const TextStyle(
                color: AppTheme.colorTextoGris,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i.producto}$cant',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (extra != null)
                  Text(
                    extra,
                    style: const TextStyle(
                      color: AppTheme.colorPrimario,
                      fontSize: 13,
                    ),
                  ),
                Text(
                  usuario,
                  style: const TextStyle(
                    color: AppTheme.colorTextoGris,
                    fontSize: 12,
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
