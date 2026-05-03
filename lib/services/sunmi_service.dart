// lib/services/sunmi_service.dart
// Servicio de impresión por red ESC/POS (TCP 9100).
import 'dart:io';

import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

class SunmiService {
  /// Solo imprimir tickets POS si el dispositivo está en la WiFi 192.168.100.x
  /// (también acepta comprobación sin puntos: prefijo `192168100`).
  static Future<bool> _ipDispositivoPermiteImpresionTickets() async {
    if (kIsWeb) return false;
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          if (_esIp192168100(addr.address)) return true;
        }
      }
    } catch (e) {
      debugPrint('No se pudo comprobar IP del dispositivo: $e');
    }
    return false;
  }

  static bool _esIp192168100(String ip) {
    if (ip.startsWith('192.168.100.')) return true;
    final compact = ip.replaceAll('.', '');
    return compact.startsWith('192168100');
  }

  static Future<void> imprimirConfirmacion({
    required int idMesa,
    required String camarero,
    required List<LineaPedido> lineasNuevas,
    required List<LineaPedido> lineasEliminadas,
    required List<LineaPedido> lineasMovidas,
    required Map<int, int> impresoraPorProducto,
    required Map<int, Impresora> impresorasPorId,
  }) async {
    try {
      if (lineasNuevas.isEmpty &&
          lineasEliminadas.isEmpty &&
          lineasMovidas.isEmpty) {
        return;
      }

      if (!await _ipDispositivoPermiteImpresionTickets()) {
        debugPrint(
          'Impresión ticket POS omitida: la IP del dispositivo no está en 192.168.100.x',
        );
        return;
      }

      // Impresion de red: usar solo ESC/POS (sin SunmiPrinter).

      final grouped = <int, List<LineaPedido>>{};
      for (final l in lineasNuevas) {
        final idImpresora = impresoraPorProducto[l.idProducto] ?? 0;
        grouped.putIfAbsent(idImpresora, () => []).add(l);
      }

      final profile = await CapabilityProfile.load();
      final hora = DateFormat('HH:mm').format(DateTime.now());
      final idsImpresora = grouped.keys.toList()..sort();

      for (final idImp in idsImpresora) {
        final cfg = impresorasPorId[idImp];
        final ip = cfg?.ip?.trim() ?? '';
        final puerto = cfg?.puerto ?? 0;
        if (ip.isEmpty || puerto <= 0) {
          debugPrint(
            'Impresora $idImp sin configuración válida en tabla impresoras',
          );
          continue;
        }

        final printer = NetworkPrinter(PaperSize.mm80, profile);
        final result = await printer.connect(
          ip,
          port: puerto,
          timeout: const Duration(seconds: 8),
        );

        if (result != PosPrintResult.success) {
          debugPrint('No se pudo conectar a impresora ESC/POS: $result');
          continue;
        }

        final tablaCodigos = (cfg?.tablaCodigos.trim().isNotEmpty ?? false)
            ? cfg!.tablaCodigos.trim().toUpperCase()
            : 'CP1252';
        printer.setGlobalCodeTable(tablaCodigos);
        _printEscPosText(
          printer,
          'Mesa $idMesa $hora',
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            width: PosTextSize.size2,
            height: PosTextSize.size2,
          ),
        );
        _printEscPosText(
          printer,
          'Le atendió: $camarero',
          styles: const PosStyles(align: PosAlign.center),
        );
        printer.hr();

        final nuevasDeImpresora = grouped[idImp] ?? <LineaPedido>[];
        for (final l in nuevasDeImpresora) {
          final lineaTexto = '${l.cantidad}x${l.textoImprimir}';

          _printEscPosText(
            printer,
            lineaTexto,
            styles: const PosStyles(
              bold: true,
              width: PosTextSize.size1,
              height: PosTextSize.size2,
            ),
          );
          for (final opcion in l.opcionesNoPredeterminadas) {
            _printEscPosText(printer, '> $opcion');
          }
          if (l.comentario.trim().isNotEmpty) {
            _printEscPosText(
              printer,
              'Nota: ${l.comentario}',
              styles: const PosStyles(bold: true),
            );
          }
        }

        if (lineasEliminadas.isNotEmpty) {
          printer.hr();
          _printEscPosText(
            printer,
            'CANCELADO:',
            styles: const PosStyles(bold: true),
          );
          for (final l in lineasEliminadas) {
            _printEscPosText(printer, ' ${l.cantidad}x ${l.textoImprimir}');
          }
        }

        if (lineasMovidas.isNotEmpty) {
          printer.hr();
          _printEscPosText(
            printer,
            'MOVIDO:',
            styles: const PosStyles(bold: true),
          );
          for (final l in lineasMovidas) {
            _printEscPosText(printer, ' ${l.cantidad}x ${l.textoImprimir}');
            _printEscPosText(
                printer, '   Mesa $idMesa -> Mesa ${l.moverAMesa}');
          }
        }
        printer.emptyLines(3);
        printer.cut();
        await Future.delayed(const Duration(milliseconds: 900));
        printer.disconnect();
      }
    } catch (e) {
      debugPrint('Error impresion ESC/POS: $e');
    }
  }

  static Future<bool> _esDispositivoSunmi() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final fabricante = info.manufacturer.trim().toUpperCase();
      return fabricante == 'SUNMI2' || fabricante.contains('SUNMI2');
    } catch (e) {
      debugPrint('No se pudo validar fabricante: $e');
      return false;
    }
  }

  static Future<void> _imprimirEnSunmi({
    required int idMesa,
    required String camarero,
    required List<LineaPedido> lineasNuevas,
    required List<LineaPedido> lineasEliminadas,
    required List<LineaPedido> lineasMovidas,
  }) async {
    final esSunmi = await _esDispositivoSunmi();
    if (!esSunmi) return;

    await SunmiPrinter.printText(
      'Tu Pedido. Mesa $idMesa',
      style: SunmiTextStyle(
        align: SunmiPrintAlign.CENTER,
        fontSize: 25,
        reverse: false,
      ),
    );
    await SunmiPrinter.printText(
      DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      style: SunmiTextStyle(
        align: SunmiPrintAlign.CENTER,
        fontSize: 27,
        reverse: true,
      ),
    );
    await SunmiPrinter.printText(
      'Le atendio: $camarero',
      style: SunmiTextStyle(
        align: SunmiPrintAlign.CENTER,
        fontSize: 30,
        reverse: false,
      ),
    );

    if (lineasNuevas.isNotEmpty) {
      for (final l in lineasNuevas) {
        await SunmiPrinter.printText(
          '${l.cantidad}x${l.textoImprimir}',
          style: SunmiTextStyle(bold: true, fontSize: 35, reverse: false),
        );
        for (final opcion in l.opcionesNoPredeterminadas) {
          await SunmiPrinter.printText(
            '>> $opcion',
            style: SunmiTextStyle(bold: true, fontSize: 20, reverse: false),
          );
        }
        if (l.comentario.isNotEmpty) {
          await SunmiPrinter.printText(
            'Nota: ${l.comentario}',
            style: SunmiTextStyle(fontSize: 20, reverse: false),
          );
        }
      }
    }

    if (lineasEliminadas.isNotEmpty) {
      await SunmiPrinter.printText(
        '---------------',
        style: SunmiTextStyle(reverse: false),
      );
      await SunmiPrinter.printText(
        'CANCELADO:',
        style: SunmiTextStyle(bold: true, reverse: false),
      );
      for (final l in lineasEliminadas) {
        await SunmiPrinter.printText(
          ' ${l.cantidad}x${l.textoImprimir}',
          style: SunmiTextStyle(reverse: false),
        );
      }
    }

    if (lineasMovidas.isNotEmpty) {
      await SunmiPrinter.printText(
        '---------------',
        style: SunmiTextStyle(reverse: false),
      );
      await SunmiPrinter.printText(
        'MOVIDO:',
        style: SunmiTextStyle(bold: true, reverse: false),
      );
      for (final l in lineasMovidas) {
        await SunmiPrinter.printText(
          ' ${l.cantidad}x${l.textoImprimir}',
          style: SunmiTextStyle(reverse: false),
        );
        await SunmiPrinter.printText(
          '   Mesa $idMesa -> Mesa ${l.moverAMesa}',
          style: SunmiTextStyle(reverse: false),
        );
      }
    }
    await SunmiPrinter.lineWrap(3);
    await SunmiPrinter.cutPaper();
  }

  static String _escPosSafeText(String input) {
    var normalized = input
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('…', '...')
        .replaceAll('´', "'")
        .replaceAll('`', "'")
        .replaceAll('•', '*')
        .replaceAll('·', '.')
        .replaceAll('−', '-')
        .replaceAll('×', 'x')
        .replaceAll('÷', '/')
        .replaceAll('º', 'o')
        .replaceAll('ª', 'a')
        .replaceAll('`', "'");

    // Fracciones Unicode frecuentes -> texto ASCII legible.
    normalized = normalized
        .replaceAll('⅓', '1/3')
        .replaceAll('¼', '1/4')
        .replaceAll('¾', '3/4')
        .replaceAll('⅛', '1/8')
        .replaceAll('⅕', '1/5')
        .replaceAll('½', '1/2')
        .replaceAll('€', 'Eur');

    final out = StringBuffer();
    for (final rune in normalized.runes) {
      // Mantener ASCII + latin-1 (acentos y ñ típicos en CP1252) + saltos.
      if ((rune >= 32 && rune <= 126) ||
          (rune >= 160 && rune <= 255) ||
          rune == 10 ||
          rune == 13 ||
          rune == 9) {
        out.write(String.fromCharCode(rune));
      } else {
        // Cualquier carácter especial se representa en hexadecimal visible.
        out.write('[0x${rune.toRadixString(16).toUpperCase()}]');
      }
    }
    return out.toString();
  }

  static void _printEscPosText(
    NetworkPrinter printer,
    String text, {
    PosStyles styles = const PosStyles(),
  }) {
    final buffer = StringBuffer();

    void flushBuffer() {
      if (buffer.isEmpty) return;

      printer.text(_escPosSafeText(buffer.toString()), styles: styles);
      buffer.clear();
    }

    for (final rune in text.runes) {
      if (rune == 0x20AC) {
        // Evita depender de tabla de códigos para el símbolo euro.
        buffer.write('Eur');
      } else if (rune == 0x00BD) {
        // Fuerza formato legible en todos los firmwares.
        buffer.write('1/2');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    flushBuffer();
  }
}
