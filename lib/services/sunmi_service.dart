// lib/services/sunmi_service.dart
// Servicio de impresión por red ESC/POS (TCP 9100).
import 'dart:io';
import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

class SunmiService {
  static const String _printerIp = '192.168.100.10';
  static const int _printerPort = 9100;
  static const String _ticketLogoAsset = 'assets/ticket_logo.bmp';
  static const String _escPosCodeTable = 'CP1252';

  static Future<void> imprimirConfirmacion({
    required int idMesa,
    required String camarero,
    required List<LineaPedido> lineasNuevas,
    required List<LineaPedido> lineasEliminadas,
    required List<LineaPedido> lineasMovidas,
    required Map<int, int> impresoraPorProducto,
  }) async {
    try {
      if (lineasNuevas.isEmpty &&
          lineasEliminadas.isEmpty &&
          lineasMovidas.isEmpty) {
        return;
      }

      await _imprimirEnSunmi(
        idMesa: idMesa,
        camarero: camarero,
        lineasNuevas: lineasNuevas,
        lineasEliminadas: lineasEliminadas,
        lineasMovidas: lineasMovidas,
      );

      final grouped = <int, List<LineaPedido>>{};
      for (final l in lineasNuevas) {
        final idImpresora = impresoraPorProducto[l.idProducto] ?? 0;
        grouped.putIfAbsent(idImpresora, () => []).add(l);
      }

      final profile = await CapabilityProfile.load();
      final hora = DateFormat('HH:mm').format(DateTime.now());
      final idsImpresora = grouped.keys.toList()..sort();

      for (final idImp in idsImpresora) {
        final printer = NetworkPrinter(PaperSize.mm80, profile);
        final result = await printer.connect(
          _printerIp,
          port: _printerPort,
          timeout: const Duration(seconds: 8),
        );

        if (result != PosPrintResult.success) {
          debugPrint('No se pudo conectar a impresora ESC/POS: $result');
          continue;
        }

        printer.setGlobalCodeTable(_escPosCodeTable);
        printer.text(
          _escPosSafeText('Mesa $idMesa $hora'),
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            width: PosTextSize.size2,
            height: PosTextSize.size2,
          ),
        );
        printer.text(
          _escPosSafeText('Le atendió: $camarero'),
          styles: const PosStyles(align: PosAlign.center),
        );
        printer.hr();

        final nuevasDeImpresora = grouped[idImp] ?? <LineaPedido>[];
        for (final l in nuevasDeImpresora) {
          printer.text(
            _escPosSafeText(
              '${l.cantidad}x ${l.textoImprimir.isNotEmpty ? l.textoImprimir : l.nombreProducto}',
            ),
            styles: const PosStyles(
              bold: true,
              width: PosTextSize.size2,
              height: PosTextSize.size2,
            ),
          );
          for (final opcion in l.opcionesNoPredeterminadas) {
            printer.text(_escPosSafeText('>> $opcion'));
          }
          if (l.comentario.trim().isNotEmpty) {
            printer.text(
              _escPosSafeText('Nota: ${l.comentario}'),
              styles: const PosStyles(bold: true),
            );
          }
        }

        if (lineasEliminadas.isNotEmpty) {
          printer.hr();
          printer.text(
            _escPosSafeText('CANCELADO:'),
            styles: const PosStyles(bold: true),
          );
          for (final l in lineasEliminadas) {
            printer.text(_escPosSafeText(' ${l.cantidad}x ${l.nombreProducto}'));
          }
        }

        if (lineasMovidas.isNotEmpty) {
          printer.hr();
          printer.text(
            _escPosSafeText('MOVIDO:'),
            styles: const PosStyles(bold: true),
          );
          for (final l in lineasMovidas) {
            printer.text(_escPosSafeText(' ${l.cantidad}x ${l.nombreProducto}'));
            printer.text(
              _escPosSafeText('   Mesa $idMesa -> Mesa ${l.moverAMesa}'),
            );
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
      return fabricante == 'SUNMI' || fabricante.contains('SUNMI');
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
          '${l.cantidad}x${l.nombreProducto}',
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
          ' ${l.cantidad}x${l.nombreProducto}',
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
          ' ${l.cantidad}x${l.nombreProducto}',
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

  static Future<List<int>?> _buildLogoBytes() async {
    try {
      final bytes = await rootBundle.load(_ticketLogoAsset);

      final uint8List = Uint8List.fromList(
        bytes.buffer.asUint8List(),
      ); // 👈 FIX BUENO

      final src = img.decodeImage(uint8List);
      if (src == null) return null;

      // Ancho múltiplo de 8: esc_pos_utils_plus 2.0.4 usa List.filled + insertAll
      // en _toRasterFormat y revienta con "fixed-length list" si width % 8 != 0.
      final resized = img.copyResize(src, width: 96, height: 96);
      final threshold = _toBlackAndWhite(resized, limit: 150);

      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);

      // En algunas ESC/POS de red, "graphics" provoca salida basura.
      // Priorizamos el modo bitImageRaster, más compatible.
      final bytesRaster = generator.imageRaster(
        threshold,
        align: PosAlign.center,
        imageFn: PosImageFn.bitImageRaster,
      );

      if (bytesRaster.isNotEmpty) return bytesRaster;

      return generator.image(threshold, align: PosAlign.center);
    } catch (e) {
      debugPrint('Error general cargando logo: $e');
      return null;
    }
  }

  static img.Image _toBlackAndWhite(img.Image source, {int limit = 150}) {
    final out = img.Image.from(source);
    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        final p = out.getPixel(x, y);
        final luminance = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        final bw = luminance >= limit ? 255 : 0;
        out.setPixelRgba(x, y, bw, bw, bw, p.a);
      }
    }
    return out;
  }

  static String _escPosSafeText(String input) {
    return input
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('…', '...');
  }
}
