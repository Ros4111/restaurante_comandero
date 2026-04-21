
// lib/services/sunmi_service.dart
// Compatible con sunmi_printer_plus ^4.1.1
// API real: llamadas secuenciales con SunmiTextStyle
import 'package:flutter/foundation.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

class SunmiService {
  static Future<void> imprimirConfirmacion({
    required int idMesa,
    required String camarero,
    required List<LineaPedido> lineasNuevas,
    required List<LineaPedido> lineasEliminadas,
    required List<LineaPedido> lineasMovidas,
  }) async {
    try {
      // ── Cabecera ─────────────────────────────────────────────
      await SunmiPrinter.printText(
        '*** CONFIRMACION ***',
        style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.CENTER),
      );
      await SunmiPrinter.printText(
        'Mesa $idMesa',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
      );
      await SunmiPrinter.printText(
        DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now()),
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
      );
      await SunmiPrinter.printText(
        'Camarero: $camarero',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
      );
      await SunmiPrinter.printText('--------------------------------');

      // ── Productos nuevos ──────────────────────────────────────
      if (lineasNuevas.isNotEmpty) {
        await SunmiPrinter.printText(
          'NUEVO:',
          style: SunmiTextStyle(bold: true),
        );
        for (final l in lineasNuevas) {
          await SunmiPrinter.printText(
            ' ${l.cantidad}x ${l.nombreProducto}',
            style: SunmiTextStyle(bold: true),
          );
          for (final opcion in l.opcionesElegidas.values) {
            await SunmiPrinter.printText('   >> $opcion');
          }
          if (l.comentario.isNotEmpty) {
            await SunmiPrinter.printText('   Nota: ${l.comentario}');
          }
        }
      }

      // ── Cancelados ────────────────────────────────────────────
      if (lineasEliminadas.isNotEmpty) {
        await SunmiPrinter.printText('--------------------------------');
        await SunmiPrinter.printText(
          'CANCELADO:',
          style: SunmiTextStyle(bold: true),
        );
        for (final l in lineasEliminadas) {
          await SunmiPrinter.printText(' ${l.cantidad}x ${l.nombreProducto}');
        }
      }

      // ── Movidos ───────────────────────────────────────────────
      if (lineasMovidas.isNotEmpty) {
        await SunmiPrinter.printText('--------------------------------');
        await SunmiPrinter.printText(
          'MOVIDO:',
          style: SunmiTextStyle(bold: true),
        );
        for (final l in lineasMovidas) {
          await SunmiPrinter.printText(' ${l.cantidad}x ${l.nombreProducto}');
          await SunmiPrinter.printText(
              '   Mesa $idMesa -> Mesa ${l.moverAMesa}');
        }
      }

      // ── Pie ───────────────────────────────────────────────────
      await SunmiPrinter.printText('--------------------------------');
      await SunmiPrinter.printText(
        '--- FIN ---',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
      );
      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cutPaper();
    } catch (e) {
      debugPrint('Error impresion Sunmi: $e');
    }
  }
}
