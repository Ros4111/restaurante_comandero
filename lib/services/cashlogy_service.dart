// Integración Cashlogy Connector v2.5 (TCP, comandos #I# / #C#).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/precio_redondeo.dart';

class CashlogyConfig {
  final String host;
  final int port;
  final String tillCode;

  const CashlogyConfig({
    required this.host,
    required this.port,
    this.tillCode = 'TPV',
  });

  static const defaultHost = '192.168.100.19';
  static const defaultPort = 8092;
}

class CashlogyInitResult {
  final bool ok;
  final String? protocolVersion;
  final String rawResponse;
  final String? message;

  const CashlogyInitResult({
    required this.ok,
    this.protocolVersion,
    required this.rawResponse,
    this.message,
  });
}

class CashlogyChargeResult {
  final bool ok;
  final bool cancelled;
  final int amountRequestedCents;
  final int amountChargedAuto;
  final int amountReturned;
  final int amountManual;
  final int amountAddedInChange;
  final String statusCode;
  final String rawResponse;
  final String? message;

  const CashlogyChargeResult({
    required this.ok,
    this.cancelled = false,
    required this.amountRequestedCents,
    this.amountChargedAuto = 0,
    this.amountReturned = 0,
    this.amountManual = 0,
    this.amountAddedInChange = 0,
    required this.statusCode,
    required this.rawResponse,
    this.message,
  });

  int get netChargedCents =>
      amountChargedAuto + amountManual - amountReturned;
}

class CashlogyException implements Exception {
  final String message;
  const CashlogyException(this.message);
  @override
  String toString() => message;
}

class CashlogyService {
  static const _prefHost = 'cashlogy_host';
  static const _prefPort = 'cashlogy_port';
  static const _prefTill = 'cashlogy_till_code';
  static const _prefEnabled = 'cashlogy_enabled';

  /// Cobro en efectivo al cerrar mesa (desactivado por defecto).
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, enabled);
  }

  static Future<CashlogyConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return CashlogyConfig(
      host: prefs.getString(_prefHost) ?? CashlogyConfig.defaultHost,
      port: prefs.getInt(_prefPort) ?? CashlogyConfig.defaultPort,
      tillCode: prefs.getString(_prefTill) ?? 'TPV',
    );
  }

  static Future<void> saveConfig(CashlogyConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefHost, config.host.trim());
    await prefs.setInt(_prefPort, config.port);
    await prefs.setString(_prefTill, config.tillCode.trim());
  }

  /// Importe en euros → céntimos (manual: valores en mínima unidad de moneda).
  static int eurosACentimos(double euros) =>
      (redondearMoneda(euros) * 100).round();

  /// Comando express #C# (ver manual 6.3.1.3).
  static String comandoCobro({
    required String numeroOperacion,
    required String codigoCaja,
    required int importeCentimos,
  }) {
    if (importeCentimos < 0) {
      importeCentimos = importeCentimos.abs();
    }
    return '#C#'
        '$numeroOperacion#'
        '$codigoCaja#'
        '$importeCentimos#'
        '0#0#0#' // sin 2ª pantalla
        '0#' // sin botón ACEPTAR → cobro automático al alcanzar importe
        '0#' // sin cobro parcial
        '0#' // pantalla Connector en segundo plano (TPV remoto)
        '0#' // sin céntimos manuales
        '0#'; // sin depósito manual
  }

  static List<String> _partesRespuesta(String raw) {
    if (raw.isEmpty) return const [];
    var s = raw.trim();
    if (!s.startsWith('#')) return [s];
    return s.split('#');
  }

  static int _enteroSeguro(String? v) => int.tryParse(v ?? '') ?? 0;

  static CashlogyInitResult parseInit(String raw) {
    final p = _partesRespuesta(raw);
    if (p.length < 2) {
      return CashlogyInitResult(
        ok: false,
        rawResponse: raw,
        message: 'Respuesta no reconocida',
      );
    }
    final code = p[1];
    if (code == '0' && p.length >= 3) {
      return CashlogyInitResult(
        ok: true,
        protocolVersion: p[2],
        rawResponse: raw,
      );
    }
    return CashlogyInitResult(
      ok: false,
      rawResponse: raw,
      message: _mensajeCodigo(code),
    );
  }

  static CashlogyChargeResult parseCobro(
    String raw, {
    required int importeSolicitadoCentimos,
  }) {
    final p = _partesRespuesta(raw);
    if (p.length < 2) {
      return CashlogyChargeResult(
        ok: false,
        amountRequestedCents: importeSolicitadoCentimos,
        statusCode: '?',
        rawResponse: raw,
        message: 'Respuesta vacía o no reconocida',
      );
    }

    final status = p[1];
    final auto = _enteroSeguro(p.length > 2 ? p[2] : null);
    final devuelto = _enteroSeguro(p.length > 3 ? p[3] : null);
    final manual = _enteroSeguro(p.length > 4 ? p[4] : null);
    final cambioAnadido = _enteroSeguro(p.length > 5 ? p[5] : null);

    if (status == '0') {
      final neto = auto + manual - devuelto;
      final cuadra = neto == importeSolicitadoCentimos;
      return CashlogyChargeResult(
        ok: cuadra,
        amountRequestedCents: importeSolicitadoCentimos,
        amountChargedAuto: auto,
        amountReturned: devuelto,
        amountManual: manual,
        amountAddedInChange: cambioAnadido,
        statusCode: status,
        rawResponse: raw,
        message: cuadra
            ? null
            : 'Importe cobrado ($neto cts) no coincide con lo pedido '
                '($importeSolicitadoCentimos cts)',
      );
    }

    if (status == 'WR:CANCEL') {
      return CashlogyChargeResult(
        ok: false,
        cancelled: true,
        amountRequestedCents: importeSolicitadoCentimos,
        amountChargedAuto: auto,
        amountReturned: devuelto,
        amountManual: manual,
        amountAddedInChange: cambioAnadido,
        statusCode: status,
        rawResponse: raw,
        message: 'Cobro cancelado en Cashlogy',
      );
    }

    if (status.startsWith('ER:')) {
      return CashlogyChargeResult(
        ok: false,
        amountRequestedCents: importeSolicitadoCentimos,
        amountChargedAuto: auto,
        amountReturned: devuelto,
        amountManual: manual,
        amountAddedInChange: cambioAnadido,
        statusCode: status,
        rawResponse: raw,
        message: _mensajeCodigo(status),
      );
    }

    if (status.startsWith('WR:')) {
      final neto = auto + manual - devuelto;
      final cuadra = neto == importeSolicitadoCentimos;
      return CashlogyChargeResult(
        ok: cuadra,
        amountRequestedCents: importeSolicitadoCentimos,
        amountChargedAuto: auto,
        amountReturned: devuelto,
        amountManual: manual,
        amountAddedInChange: cambioAnadido,
        statusCode: status,
        rawResponse: raw,
        message: cuadra
            ? 'Cobro OK con aviso: ${_mensajeCodigo(status)}'
            : _mensajeCodigo(status),
      );
    }

    return CashlogyChargeResult(
      ok: false,
      amountRequestedCents: importeSolicitadoCentimos,
      statusCode: status,
      rawResponse: raw,
      message: 'Estado desconocido: $status',
    );
  }

  static String _mensajeCodigo(String code) {
    switch (code) {
      case 'ER:GENERIC':
        return 'Error en Cashlogy (comunicación o dispensado)';
      case 'ER:BUSY':
        return 'Cashlogy ocupado; inténtalo de nuevo';
      case 'ER:BAD_DATA':
        return 'Parámetros incorrectos enviados al Connector';
      case 'ER:ILLEGAL':
        return 'Comando no permitido (¿falta inicializar o modo sin pantalla?)';
      case 'WR:CANCEL':
        return 'Operación cancelada';
      case 'WR:LEVEL':
        return 'Aviso: algún hopper/reciclador cerca del límite';
      default:
        return code;
    }
  }

  Future<String> enviarComando(
    String comando, {
    CashlogyConfig? config,
    Duration connectTimeout = const Duration(seconds: 12),
    Duration responseTimeout = const Duration(seconds: 120),
  }) async {
    final cfg = config ?? await loadConfig();
    final host = cfg.host.trim();
    if (host.isEmpty) {
      throw const CashlogyException('Configura la IP de Cashlogy');
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        cfg.port,
        timeout: connectTimeout,
      );
      socket.write(utf8.encode(comando));
      await socket.flush();
      return await _leerRespuesta(socket, responseTimeout);
    } on SocketException catch (e) {
      throw CashlogyException('No se pudo conectar con $host:${cfg.port}: $e');
    } on TimeoutException {
      throw CashlogyException(
        'Tiempo de espera agotado (${responseTimeout.inSeconds}s)',
      );
    } finally {
      await socket?.close();
    }
  }

  Future<String> _leerRespuesta(Socket socket, Duration timeout) async {
    final buffer = <int>[];
    var lastChunkAt = DateTime.now();
    final done = Completer<void>();

    late final StreamSubscription<List<int>> sub;
    sub = socket.listen(
      (chunk) {
        buffer.addAll(chunk);
        lastChunkAt = DateTime.now();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
    );

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (done.isCompleted) break;
      if (buffer.isNotEmpty) {
        final quiet = DateTime.now().difference(lastChunkAt);
        if (quiet.inMilliseconds >= 500) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    await sub.cancel();
    try {
      await socket.close();
    } catch (_) {}

    if (buffer.isEmpty) {
      throw const CashlogyException('Sin respuesta de Cashlogy Connector');
    }
    return utf8.decode(buffer, allowMalformed: true).trim();
  }

  Future<CashlogyInitResult> inicializar({CashlogyConfig? config}) async {
    final raw = await enviarComando(
      '#I#',
      config: config,
      responseTimeout: const Duration(seconds: 90),
    );
    return parseInit(raw);
  }

  Future<CashlogyChargeResult> cobrar({
    required int importeCentimos,
    required String numeroOperacion,
    CashlogyConfig? config,
  }) async {
    if (importeCentimos <= 0) {
      throw const CashlogyException('El importe debe ser mayor que cero');
    }
    final cfg = config ?? await loadConfig();
    final cmd = comandoCobro(
      numeroOperacion: numeroOperacion,
      codigoCaja: cfg.tillCode,
      importeCentimos: importeCentimos,
    );
    final raw = await enviarComando(
      cmd,
      config: cfg,
      responseTimeout: const Duration(minutes: 5),
    );
    return parseCobro(raw, importeSolicitadoCentimos: importeCentimos);
  }

  Future<CashlogyChargeResult> cobrarEuros(
    double importeEuros, {
    required String numeroOperacion,
    CashlogyConfig? config,
  }) {
    return cobrar(
      importeCentimos: eurosACentimos(importeEuros),
      numeroOperacion: numeroOperacion,
      config: config,
    );
  }
}
