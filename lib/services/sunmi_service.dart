
// lib/services/sunmi_service.dart
// Compatible con sunmi_printer_plus ^4.1.1
// API real: llamadas secuenciales con SunmiTextStyle
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

class SunmiService {
  static Future<bool> _esDispositivoSunmi() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final fabricante = info.manufacturer.trim().toUpperCase();
      return fabricante == 'SUNMI' || fabricante.contains('SUNMI');
    } catch (e) {
      debugPrint('No se pudo validar fabricante: $e');
      return false;
    }
  }
  
  static Future<void> imprimirConfirmacion({
    required int idMesa,
    required String camarero,
    required List<LineaPedido> lineasNuevas,
    required List<LineaPedido> lineasEliminadas,
    required List<LineaPedido> lineasMovidas,
  }) async {
    try {
      final esSunmi = await _esDispositivoSunmi();
      if (!esSunmi) {
        debugPrint('Impresion omitida: dispositivo no SUNMI');
        return;
      }

      // ── Cabecera ─────────────────────────────────────────────
      await SunmiPrinter.printText(
        'Tu Pedido. Mesa $idMesa',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER,fontSize: 25,reverse: false),
      );
      await SunmiPrinter.printText(
        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER,fontSize: 27,reverse: true),
      );
      await SunmiPrinter.printText(
        'Le atendió: $camarero',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER,fontSize: 30,reverse: false),
      );

      // ── Productos nuevos ──────────────────────────────────────
      if (lineasNuevas.isNotEmpty) {
        for (final l in lineasNuevas) {
          await SunmiPrinter.printText(
            '${l.cantidad}x${l.nombreProducto}',
            style: SunmiTextStyle(bold: true,fontSize: 35,reverse: false),
          );
          for (final opcion in l.opcionesNombres) {
            await SunmiPrinter.printText('>> $opcion', style: SunmiTextStyle(bold: true,fontSize: 12,reverse: false),);
          }
          if (l.comentario.isNotEmpty) {
            await SunmiPrinter.printText('Nota: ${l.comentario}', style: SunmiTextStyle(fontSize: 10,reverse: false),);
          }
        }
      }

      // ── Cancelados ────────────────────────────────────────────
      if (lineasEliminadas.isNotEmpty) {
        await SunmiPrinter.printText('---------------', style: SunmiTextStyle(reverse: false),);
        await SunmiPrinter.printText(
          'CANCELADO:',
          style: SunmiTextStyle(bold: true,reverse: false),
        );
        for (final l in lineasEliminadas) {
          await SunmiPrinter.printText(' ${l.cantidad}x${l.nombreProducto}', style: SunmiTextStyle(reverse: false),);
        }
      }

      // ── Movidos ───────────────────────────────────────────────
      if (lineasMovidas.isNotEmpty) {
        await SunmiPrinter.printText('---------------', style: SunmiTextStyle(reverse: false),);
        await SunmiPrinter.printText(
          'MOVIDO:',
          style: SunmiTextStyle(bold: true,reverse: false),
        );
        for (final l in lineasMovidas) {
          await SunmiPrinter.printText(' ${l.cantidad}x${l.nombreProducto}', style: SunmiTextStyle(reverse: false),);
          await SunmiPrinter.printText(
              '   Mesa $idMesa -> Mesa ${l.moverAMesa}', style: SunmiTextStyle(reverse: false),);
        }
      }

      // ── Pie ───────────────────────────────────────────────────
      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cutPaper();
    } catch (e) {
      debugPrint('Error impresion Sunmi: $e');
    }
  }
}
