// lib/services/sunmi_service.dart
// Servicio de impresión por red ESC/POS (TCP 9100).
import 'dart:io';
import 'dart:math' as math;

import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as im;
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

  /// Ticket ESC/POS por red: cantidad 1 → solo nombre; en otro caso `Nx` o ` Nx ` si [sangria].
  static String _escPosLineaProductoRed(int cantidad, String texto,
      {bool sangria = false}) {
    if (cantidad == 1) return sangria ? ' $texto' : texto;
    return sangria ? ' ${cantidad}x $texto' : '${cantidad}x$texto';
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
          final lineaTexto =
              _escPosLineaProductoRed(l.cantidad, l.textoImprimir);

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
            _printEscPosText(
              printer,
              _escPosLineaProductoRed(l.cantidad, l.textoImprimir,
                  sangria: true),
            );
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
            _printEscPosText(
              printer,
              _escPosLineaProductoRed(l.cantidad, l.textoImprimir,
                  sangria: true),
            );
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

  /// SUNMI en sentido amplio (impresión integrada), para tickets auxiliares.
  static Future<bool> _esSunmiImpresoraIntegrada() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.manufacturer.toUpperCase().contains('SUNMI');
    } catch (e) {
      debugPrint('No se pudo validar fabricante Sunmi: $e');
      return false;
    }
  }

  static Uint8List _pngTarjetaDatfono() {
    const w = 384;
    const h = 96;
    final pic = im.Image(width: w, height: h);
    im.fill(pic, color: im.ColorUint8.rgb(236, 239, 241));
    im.fillRect(
      pic,
      x1: 72,
      y1: 12,
      x2: w - 72,
      y2: h - 12,
      color: im.ColorUint8.rgb(30, 136, 229),
    );
    im.fillRect(
      pic,
      x1: 88,
      y1: 24,
      x2: w - 88,
      y2: h - 24,
      color: im.ColorUint8.rgb(187, 222, 251),
    );
    im.fillCircle(
      pic,
      x: w ~/ 2,
      y: h ~/ 2,
      radius: 10,
      color: im.ColorUint8.rgb(255, 213, 79),
    );
    return im.encodePng(pic);
  }

  static Uint8List _pngSenalPeligro() {
    const w = 384;
    const h = 200;
    final pic = im.Image(width: w, height: h);
    const stripe = 32;
    for (int y = 0; y < h; y += stripe) {
      final yMid = math.min(y + stripe ~/ 2, h - 1);
      im.fillRect(
        pic,
        x1: 0,
        y1: y,
        x2: w - 1,
        y2: yMid,
        color: im.ColorUint8.rgb(255, 193, 7),
      );
      final yEnd = math.min(y + stripe, h - 1);
      im.fillRect(
        pic,
        x1: 0,
        y1: yMid + 1,
        x2: w - 1,
        y2: yEnd,
        color: im.ColorUint8.rgb(33, 33, 33),
      );
    }
    im.fillPolygon(
      pic,
      vertices: [
        im.Point(w / 2, 35),
        im.Point(w / 2 - 70, h - 35),
        im.Point(w / 2 + 70, h - 35),
      ],
      color: im.ColorUint8.rgb(183, 28, 28),
    );
    im.fillCircle(
      pic,
      x: w ~/ 2,
      y: h ~/ 2 - 6,
      radius: 9,
      color: im.ColorUint8.rgb(255, 255, 255),
    );
    im.fillRect(
      pic,
      x1: w ~/ 2 - 5,
      y1: h ~/ 2 + 8,
      x2: w ~/ 2 + 5,
      y2: h - 42,
      color: im.ColorUint8.rgb(255, 255, 255),
    );
    return im.encodePng(pic);
  }

  /// Ticket de simulación datáfono (imagen + texto + imagen peligro). Solo SUNMI.
  static Future<void> imprimirTicketDatfonoDenunciada() async {
    if (!await _esSunmiImpresoraIntegrada()) {
      debugPrint('Ticket datáfono: no es dispositivo SUNMI, no se imprime.');
      return;
    }
    try {
      await SunmiPrinter.printImage(
        _pngTarjetaDatfono(),
        align: SunmiPrintAlign.CENTER,
      );
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText(
        'Tarjeta denunciada, alejese',
        style: SunmiTextStyle(
          align: SunmiPrintAlign.CENTER,
          bold: true,
          fontSize: 22,
        ),
      );
      await SunmiPrinter.printText(
        'discretamente de la mesa',
        style: SunmiTextStyle(
          align: SunmiPrintAlign.CENTER,
          bold: true,
          fontSize: 22,
        ),
      );
      await SunmiPrinter.printText(
        'y llame a la Policia',
        style: SunmiTextStyle(
          align: SunmiPrintAlign.CENTER,
          bold: true,
          fontSize: 22,
        ),
      );
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printImage(
        _pngSenalPeligro(),
        align: SunmiPrintAlign.CENTER,
      );
      await SunmiPrinter.lineWrap(2);
      await SunmiPrinter.cutPaper();
    } catch (e) {
      debugPrint('Error impresión ticket datáfono: $e');
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
