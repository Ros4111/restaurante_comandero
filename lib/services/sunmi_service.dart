// lib/services/sunmi_service.dart
// Servicio de impresión por red ESC/POS (TCP 9100) y Bluetooth.
import 'dart:io';
import 'dart:math' as math;

import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as im;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import '../config/public_pedido_config.dart';
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

  static String _claveImpresionAgrupada(LineaPedido l) {
    final buf = StringBuffer()
      ..write('${l.idProducto}|')
      ..write('${l.comentario.trim()}|');
    if (l.moverAMesa != null) {
      buf.write('|mesa:${l.moverAMesa}');
    }
    final keys = l.opcionesElegidas.keys.toList()..sort();
    for (final k in keys) {
      final o = l.opcionesElegidas[k]!;
      buf.write('$k:${o.nombre}:${o.predeterminado};');
    }
    return buf.toString();
  }

  /// Misma línea lógica (producto, opciones y comentario), cantidades sumadas.
  /// No modifica las instancias originales del pedido.
  static List<LineaPedido> agruparLineasIgualdadImpresion(
      List<LineaPedido> lineas) {
    if (lineas.isEmpty) return [];
    if (lineas.length == 1) return List<LineaPedido>.from(lineas);
    final ordenClaves = <String>[];
    final cantidadPorClave = <String, int>{};
    final representantePorClave = <String, LineaPedido>{};

    for (final l in lineas) {
      final k = _claveImpresionAgrupada(l);
      if (cantidadPorClave.containsKey(k)) {
        cantidadPorClave[k] = cantidadPorClave[k]! + l.cantidad;
      } else {
        ordenClaves.add(k);
        representantePorClave[k] = l;
        cantidadPorClave[k] = l.cantidad;
      }
    }
    return [
      for (final k in ordenClaves)
        representantePorClave[k]!.copyWith(cantidad: cantidadPorClave[k]!),
    ];
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
      final nuevasImp = agruparLineasIgualdadImpresion(lineasNuevas);
      final elimImp = agruparLineasIgualdadImpresion(lineasEliminadas);

      final movImp = agruparLineasIgualdadImpresion(lineasMovidas);

      if (nuevasImp.isEmpty && elimImp.isEmpty && movImp.isEmpty) {
        return;
      }

      // Agrupar líneas por impresora
      final grouped = <int, List<LineaPedido>>{};
      for (final l in nuevasImp) {
        final idImpresora = impresoraPorProducto[l.idProducto] ?? 0;
        grouped.putIfAbsent(idImpresora, () => []).add(l);
      }

      final idsImpresora = grouped.keys.toList()..sort();

      // Líneas destinadas a impresoras Bluetooth (ip == 'bluetooth')
      final lineasBluetooth = <LineaPedido>[];

      // Impresoras TCP: solo si la IP del dispositivo está en 192.168.100.x
      final permiteRed = await _ipDispositivoPermiteImpresionTickets();
      if (!permiteRed) {
        debugPrint(
            'Impresión TCP omitida: IP del dispositivo no está en 192.168.100.x');
      }

      final profile = await CapabilityProfile.load();
      final hora = DateFormat('HH:mm').format(DateTime.now());

      for (final idImp in idsImpresora) {
        final cfg = impresorasPorId[idImp];
        final ip = cfg?.ip?.trim().toLowerCase() ?? '';
        final nuevasDeImpresora = grouped[idImp] ?? <LineaPedido>[];

        // Impresora Bluetooth: acumular líneas para imprimir por BT
        if (ip == 'bluetooth') {
          lineasBluetooth.addAll(nuevasDeImpresora);
          continue;
        }

        // Impresora de red TCP
        if (!permiteRed) continue;

        final puerto = cfg?.puerto ?? 0;
        if (ip.isEmpty || puerto <= 0) {
          debugPrint(
              'Impresora $idImp sin configuración válida en tabla impresoras');
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

        for (final l in nuevasDeImpresora) {
          _printEscPosText(
            printer,
            _escPosLineaProductoRed(l.cantidad, l.textoImprimirBarraCocina),
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

        if (elimImp.isNotEmpty) {
          printer.hr();
          _printEscPosText(printer, 'CANCELADO:',
              styles: const PosStyles(bold: true));
          for (final l in elimImp) {
            _printEscPosText(
              printer,
              _escPosLineaProductoRed(l.cantidad, l.textoImprimirBarraCocina,
                  sangria: true),
            );
          }
        }

        if (movImp.isNotEmpty) {
          printer.hr();
          _printEscPosText(printer, 'MOVIDO:',
              styles: const PosStyles(bold: true));
          for (final l in movImp) {
            _printEscPosText(
              printer,
              _escPosLineaProductoRed(l.cantidad, l.textoImprimirBarraCocina,
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

      // Impresión Bluetooth: solo si hay líneas nuevas asignadas a impresoras BT
      if (lineasBluetooth.isNotEmpty) {
        await _imprimirEnBluetooth(
          idMesa: idMesa,
          camarero: camarero,
          lineasNuevas: lineasBluetooth,
          lineasEliminadas: elimImp,
          lineasMovidas: movImp,
        );
      }
    } catch (e) {
      debugPrint('Error impresion ESC/POS: $e');
    }
  }

  /// Intenta conectar al periférico BT con reintentos.
  /// Espera [intervaloSegundos] segundos entre cada intento durante un máximo
  /// de [maxEsperaSegundos] segundos en total. Devuelve true si conecta.
  static Future<bool> _conectarBluetoothConReintentos(
    String mac, {
    int maxEsperaSegundos = 30,
    int intervaloSegundos = 3,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: maxEsperaSegundos));
    int intento = 0;
    while (DateTime.now().isBefore(deadline)) {
      intento++;
      debugPrint('BT: intento $intento de conexión a $mac');
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (ok) return true;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      final espera = remaining < Duration(seconds: intervaloSegundos)
          ? remaining
          : Duration(seconds: intervaloSegundos);
      debugPrint('BT: no conectado, reintentando en ${espera.inSeconds}s…');
      await Future.delayed(espera);
    }
    return false;
  }

  static Future<void> _imprimirEnBluetooth({
    required int idMesa,
    required String camarero,
    required List<LineaPedido> lineasNuevas,
    required List<LineaPedido> lineasEliminadas,
    required List<LineaPedido> lineasMovidas,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mac = prefs.getString('bt_printer_mac') ?? '';
      if (mac.isEmpty) return;

      final tablaCodigos =
          prefs.getString('bt_printer_tabla_codigos') ?? 'CP1252';
      final papel = prefs.getString('bt_printer_papel') ?? 'mm58';
      final paperSize = papel == 'mm80' ? PaperSize.mm80 : PaperSize.mm58;

      final connected = await _conectarBluetoothConReintentos(mac);
      if (!connected) {
        debugPrint('BT: no se pudo conectar a $mac tras varios intentos');
        return;
      }

      final profile = await CapabilityProfile.load();
      final generator = Generator(paperSize, profile);
      final hora = DateFormat('HH:mm').format(DateTime.now());
      final List<int> bytes = [];

      bytes.addAll(generator.reset());
      bytes.addAll(generator.setGlobalCodeTable(tablaCodigos));
      bytes.addAll(generator.text(
        _escPosSafeText('Mesa $idMesa $hora'),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size2,
        ),
      ));
      bytes.addAll(generator.text(
        _escPosSafeText('Le atendió: $camarero'),
        styles: const PosStyles(align: PosAlign.center),
      ));
      bytes.addAll(generator.hr());

      for (final l in lineasNuevas) {
        if (l.urgente) {
          bytes.addAll(generator.text(
            _escPosSafeText('*** URGENTE ***'),
            styles: const PosStyles(
              bold: true,
              align: PosAlign.center,
              reverse: true,
            ),
          ));
        }
        bytes.addAll(generator.text(
          _escPosSafeText(
              _escPosLineaProductoRed(l.cantidad, l.textoImprimirBarraCocina)),
          styles: const PosStyles(
            bold: true,
            width: PosTextSize.size1,
            height: PosTextSize.size2,
          ),
        ));
        for (final opcion in l.opcionesNoPredeterminadas) {
          bytes.addAll(generator.text(_escPosSafeText('> $opcion')));
        }
        if (l.comentario.trim().isNotEmpty) {
          bytes.addAll(generator.text(
            _escPosSafeText('Nota: ${l.comentario}'),
            styles: const PosStyles(bold: true),
          ));
        }
      }

      if (lineasEliminadas.isNotEmpty) {
        bytes.addAll(generator.hr());
        bytes.addAll(
            generator.text('CANCELADO:', styles: const PosStyles(bold: true)));
        for (final l in lineasEliminadas) {
          bytes.addAll(generator.text(_escPosSafeText(_escPosLineaProductoRed(
              l.cantidad, l.textoImprimirBarraCocina,
              sangria: true))));
        }
      }

      if (lineasMovidas.isNotEmpty) {
        bytes.addAll(generator.hr());
        bytes.addAll(
            generator.text('MOVIDO:', styles: const PosStyles(bold: true)));
        for (final l in lineasMovidas) {
          bytes.addAll(generator.text(_escPosSafeText(_escPosLineaProductoRed(
              l.cantidad, l.textoImprimirBarraCocina,
              sangria: true))));
          bytes.addAll(generator.text(
              _escPosSafeText('   Mesa $idMesa -> Mesa ${l.moverAMesa}')));
        }
      }

      bytes.addAll(generator.feed(3));
      bytes.addAll(generator.cut());

      await PrintBluetoothThermal.writeBytes(bytes);
      await Future.delayed(const Duration(milliseconds: 900));
      await PrintBluetoothThermal.disconnect;
    } catch (e) {
      debugPrint('Error impresión BT: $e');
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
  static Future<bool> dispositivoTieneImpresoraSunmiIntegrada() async {
    return _esSunmiImpresoraIntegrada();
  }

  /// Marca del teléfono Sunmi (fabricante).
  static Future<bool> dispositivoEsMarcaSunmi() async {
    return _esSunmiImpresoraIntegrada();
  }

  static bool _textoIndicaSunmi(String value) {
    final u = value.trim().toUpperCase();
    return u.contains('SUNMI');
  }

  static Future<bool> _esSunmiImpresoraIntegrada() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return _textoIndicaSunmi(info.manufacturer) ||
          _textoIndicaSunmi(info.brand) ||
          _textoIndicaSunmi(info.model);
    } catch (e) {
      debugPrint('No se pudo validar fabricante Sunmi: $e');
      return false;
    }
  }

  static bool _tokenPublicoValido(String token) =>
      RegExp(r'^[a-f0-9]{32}$', caseSensitive: false).hasMatch(token.trim());

  /// URL pública desde respuesta de guardar o de GET pedido.
  static String? urlPublicaDesdeMap(Map<String, dynamic> data) {
    final url = data['url_publica']?.toString().trim() ?? '';
    if (url.isNotEmpty) return url;
    var token = data['token_publico']?.toString().trim() ?? '';
    if (_tokenPublicoValido(token)) {
      return PublicPedidoConfig.urlConToken(token.toLowerCase());
    }
    final cab = data['cabecera'];
    if (cab is Map) {
      token = cab['token_publico']?.toString().trim() ?? '';
      if (_tokenPublicoValido(token)) {
        return PublicPedidoConfig.urlConToken(token.toLowerCase());
      }
    }
    return null;
  }

  static Future<void> _prepararImpresoraSunmi() async {}

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
        if (l.urgente) {
          await SunmiPrinter.printText(
            '*** URGENTE ***',
            style: SunmiTextStyle(bold: true, fontSize: 28, reverse: true),
          );
        }
        await SunmiPrinter.printText(
          '${l.cantidad}x${l.textoImprimirBarraCocina}',
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
          ' ${l.cantidad}x${l.textoImprimirBarraCocina}',
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
          ' ${l.cantidad}x${l.textoImprimirBarraCocina}',
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

  /// Imprime una imagen (bytes ya cargados) en una impresora ESC/POS por red.
  /// [usarRaster] → true usa imageRaster() (ESC *); false usa image() (GS v 0).
  /// Devuelve una cadena de resultado para mostrar al usuario.
  static Future<String> imprimirImagenLogoRed({
    required Uint8List imageBytes,
    required bool usarRaster,
    required String ip,
    required int puerto,
  }) async {
    try {
      final img = im.decodeImage(imageBytes);
      if (img == null) return 'No se pudo decodificar la imagen';

      final profile = await CapabilityProfile.load();
      final printer = NetworkPrinter(PaperSize.mm80, profile);
      final result = await printer.connect(
        ip,
        port: puerto,
        timeout: const Duration(seconds: 8),
      );
      if (result != PosPrintResult.success) {
        return 'Error al conectar ($result)';
      }

      if (usarRaster) {
        printer.imageRaster(img);
      } else {
        printer.image(img);
      }
      printer.cut();
      await Future.delayed(const Duration(milliseconds: 900));
      printer.disconnect();
      return 'OK · ${usarRaster ? "imageRaster()" : "image()"} → $ip:$puerto';
    } catch (e) {
      return 'Error: $e';
    }
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

  /// Ticket de texto (reparto entre comensales, etc.).
  /// [destino]: `bt` | `sunmi` | `tcp:<ip>:<puerto>` (puerto tras el último `:`).
  /// Devuelve cadena vacía si todo fue bien, o mensaje de error.
  static Future<String> imprimirTextoTicket({
    required List<String> lineas,
    required String destino,
  }) async {
    try {
      if (destino == 'bt') {
        return await _imprimirTextoBluetooth(lineas);
      }
      if (destino == 'sunmi') {
        return await _imprimirTextoSunmi(lineas);
      }
      if (destino.startsWith('tcp:')) {
        final rest = destino.substring(4);
        final colon = rest.lastIndexOf(':');
        if (colon <= 0) {
          return 'TCP: formato inválido';
        }
        final ip = rest.substring(0, colon);
        final puerto = int.tryParse(rest.substring(colon + 1)) ?? 0;
        if (ip.isEmpty || puerto <= 0) {
          return 'TCP: IP o puerto inválido';
        }
        return await _imprimirTextoTcp(lineas, ip, puerto);
      }
      return 'Destino de impresión no reconocido';
    } catch (e) {
      return 'Error: $e';
    }
  }

  static Future<String> _imprimirTextoBluetooth(List<String> lineas) async {
    final prefs = await SharedPreferences.getInstance();
    final mac = prefs.getString('bt_printer_mac') ?? '';
    if (mac.isEmpty) {
      return 'No hay impresora Bluetooth configurada';
    }

    final tablaCodigos =
        prefs.getString('bt_printer_tabla_codigos') ?? 'CP1252';
    final papel = prefs.getString('bt_printer_papel') ?? 'mm58';
    final paperSize = papel == 'mm80' ? PaperSize.mm80 : PaperSize.mm58;

    final connected = await _conectarBluetoothConReintentos(mac);
    if (!connected) {
      return 'No se pudo conectar por Bluetooth';
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    final bytes = <int>[];
    bytes.addAll(generator.reset());
    bytes.addAll(generator.setGlobalCodeTable(tablaCodigos));
    for (final line in lineas) {
      bytes.addAll(generator.text(_escPosSafeText(line)));
    }
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());
    await PrintBluetoothThermal.writeBytes(bytes);
    await Future.delayed(const Duration(milliseconds: 900));
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
    return '';
  }

  static Future<String> _imprimirTextoTcp(
    List<String> lineas,
    String ip,
    int puerto,
  ) async {
    if (!await _ipDispositivoPermiteImpresionTickets()) {
      return 'La impresora TCP solo está disponible en la red 192.168.100.x';
    }
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(PaperSize.mm80, profile);
    final result = await printer.connect(
      ip,
      port: puerto,
      timeout: const Duration(seconds: 8),
    );
    if (result != PosPrintResult.success) {
      return 'Error al conectar ($result)';
    }
    printer.setGlobalCodeTable('CP1252');
    for (final line in lineas) {
      _printEscPosText(printer, line);
    }
    printer.feed(3);
    printer.cut();
    await Future.delayed(const Duration(milliseconds: 900));
    printer.disconnect();
    return '';
  }

  /// Ticket cliente con QR. Devuelve cadena vacía si OK, o mensaje de error.
  static Future<String> imprimirTicketQrPedidoCliente({
    required int idMesa,
    required String urlPublica,
  }) async {
    if (!await _esSunmiImpresoraIntegrada()) {
      return 'Este dispositivo no es Sunmi o no tiene impresora integrada';
    }
    try {
      await _prepararImpresoraSunmi();
      await SunmiPrinter.printText(
        'Tu pedido — Mesa $idMesa',
        style: SunmiTextStyle(
          align: SunmiPrintAlign.CENTER,
          fontSize: 28,
          bold: true,
        ),
      );
      await SunmiPrinter.printText(
        'Escanee el código para ver su pedido',
        style: SunmiTextStyle(
          align: SunmiPrintAlign.CENTER,
          fontSize: 22,
        ),
      );
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printQRCode(
        urlPublica,
        style: SunmiQrcodeStyle(
          qrcodeSize: 6,
          errorLevel: SunmiQrcodeLevel.LEVEL_M,
        ),
      );
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printText(
        urlPublica,
        style: SunmiTextStyle(
          align: SunmiPrintAlign.CENTER,
          fontSize: 18,
        ),
      );
      await SunmiPrinter.lineWrap(2);
      await SunmiPrinter.cutPaper();
      return '';
    } catch (e) {
      debugPrint('Error impresión QR pedido cliente: $e');
      return 'Error al imprimir QR: $e';
    }
  }

  /// Carga datos de pedido (map GET /pedidos) e imprime QR en Sunmi.
  static Future<String> imprimirQrDesdeDatosPedido({
    required int idMesa,
    required Map<String, dynamic> pedidoData,
  }) async {
    final url = urlPublicaDesdeMap(pedidoData);
    if (url == null) {
      return 'Este pedido no tiene enlace público (token).';
    }
    return imprimirTicketQrPedidoCliente(idMesa: idMesa, urlPublica: url);
  }

  static Future<String> _imprimirTextoSunmi(List<String> lineas) async {
    if (!await _esSunmiImpresoraIntegrada()) {
      return 'Este dispositivo no tiene impresora SUNMI integrada';
    }
    await _prepararImpresoraSunmi();
    for (final line in lineas) {
      await SunmiPrinter.printText(
        line,
        style: SunmiTextStyle(
          align: SunmiPrintAlign.LEFT,
          fontSize: 22,
        ),
      );
    }
    await SunmiPrinter.lineWrap(2);
    await SunmiPrinter.cutPaper();
    return '';
  }
}
