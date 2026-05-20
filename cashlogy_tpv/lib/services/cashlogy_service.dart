// lib/services/cashlogy_service.dart
// Protocolo Cashlogy Connector v2.5 (TCP, comandos #I# / #C# / #X#).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

// ── Configuración ─────────────────────────────────────────────

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

  static const _kHost = 'cashlogy_host';
  static const _kPort = 'cashlogy_port';
  static const _kTill = 'cashlogy_till';

  static Future<CashlogyConfig> load() async {
    final p = await SharedPreferences.getInstance();
    return CashlogyConfig(
      host: p.getString(_kHost) ?? defaultHost,
      port: p.getInt(_kPort) ?? defaultPort,
      tillCode: p.getString(_kTill) ?? 'TPV',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHost, host.trim());
    await p.setInt(_kPort, port);
    await p.setString(_kTill, tillCode.trim());
  }

  CashlogyConfig copyWith({String? host, int? port, String? tillCode}) =>
      CashlogyConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        tillCode: tillCode ?? this.tillCode,
      );
}

// ── Resultados ────────────────────────────────────────────────

class CashlogyInitResult {
  final bool ok;
  final String? version;
  final String raw;
  final String? error;
  const CashlogyInitResult({
    required this.ok,
    this.version,
    required this.raw,
    this.error,
  });
}

class CashlogyChargeResult {
  final bool ok;
  final bool cancelled;
  final int requestedCents;
  final int autoCents;
  final int returnedCents;
  final int manualCents;
  final int changeCents;
  final String statusCode;
  final String raw;
  final String? message;

  const CashlogyChargeResult({
    required this.ok,
    this.cancelled = false,
    required this.requestedCents,
    this.autoCents = 0,
    this.returnedCents = 0,
    this.manualCents = 0,
    this.changeCents = 0,
    required this.statusCode,
    required this.raw,
    this.message,
  });

  int get netCents => autoCents + manualCents - returnedCents;

  double get requestedEuros => requestedCents / 100.0;
  double get netEuros => netCents / 100.0;
  double get autoEuros => autoCents / 100.0;
  double get returnedEuros => returnedCents / 100.0;
  double get manualEuros => manualCents / 100.0;
  double get changeEuros => changeCents / 100.0;
}

class CashlogyException implements Exception {
  final String message;
  const CashlogyException(this.message);
  @override
  String toString() => message;
}

// ── Servicio principal ────────────────────────────────────────

class CashlogyService {
  /// Convierte euros a céntimos (mínima unidad del protocolo).
  static int eurosACentimos(double euros) =>
      (double.parse(euros.toStringAsFixed(2)) * 100).round();

  /// Formato del comando de cobro express (manual 6.3.1.3).
  /// numeroOperacion: referencia única (ej. "OP001").
  static String _cmdCobro({
    required String numOp,
    required String caja,
    required int centimos,
  }) =>
      '#C#'
      '$numOp#'
      '$caja#'
      '$centimos#'
      '0#0#0#' // sin 2ª pantalla
      '0#' // sin botón ACEPTAR → cobro automático
      '0#' // sin cobro parcial
      '0#' // pantalla Connector en segundo plano
      '0#' // sin céntimos manuales
      '0#'; // sin depósito manual

  // ── Parsing ────────────────────────────────────────────────

  static List<String> _partes(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return [];
    if (!s.startsWith('#')) return [s];
    return s.split('#');
  }

  static int _int(String? v) => int.tryParse(v ?? '') ?? 0;

  static CashlogyInitResult _parseInit(String raw) {
    final p = _partes(raw);
    if (p.length >= 3 && p[1] == '0') {
      return CashlogyInitResult(ok: true, version: p[2], raw: raw);
    }
    final code = p.length >= 2 ? p[1] : '?';
    return CashlogyInitResult(
        ok: false, raw: raw, error: _descCodigo(code));
  }

  static CashlogyChargeResult _parseCobro(String raw, int reqCents) {
    final p = _partes(raw);
    if (p.length < 2) {
      return CashlogyChargeResult(
        ok: false,
        requestedCents: reqCents,
        statusCode: '?',
        raw: raw,
        message: 'Respuesta vacía o no reconocida',
      );
    }
    final status = p[1];
    final auto = _int(p.length > 2 ? p[2] : null);
    final ret = _int(p.length > 3 ? p[3] : null);
    final manual = _int(p.length > 4 ? p[4] : null);
    final change = _int(p.length > 5 ? p[5] : null);

    if (status == 'WR:CANCEL') {
      return CashlogyChargeResult(
        ok: false,
        cancelled: true,
        requestedCents: reqCents,
        autoCents: auto,
        returnedCents: ret,
        manualCents: manual,
        changeCents: change,
        statusCode: status,
        raw: raw,
        message: 'Cobro cancelado por el cliente',
      );
    }

    final neto = auto + manual - ret;
    final cuadra = neto == reqCents;

    if (status == '0' || status.startsWith('WR:')) {
      return CashlogyChargeResult(
        ok: cuadra,
        requestedCents: reqCents,
        autoCents: auto,
        returnedCents: ret,
        manualCents: manual,
        changeCents: change,
        statusCode: status,
        raw: raw,
        message: cuadra
            ? (status.startsWith('WR:') ? _descCodigo(status) : null)
            : 'Importe cobrado ($neto cts) ≠ solicitado ($reqCents cts)',
      );
    }

    return CashlogyChargeResult(
      ok: false,
      requestedCents: reqCents,
      autoCents: auto,
      returnedCents: ret,
      manualCents: manual,
      changeCents: change,
      statusCode: status,
      raw: raw,
      message: _descCodigo(status),
    );
  }

  static String _descCodigo(String code) => switch (code) {
        'ER:GENERIC' => 'Error de Cashlogy (comunicación o dispensado)',
        'ER:BUSY' => 'Cashlogy ocupado; inténtalo de nuevo',
        'ER:BAD_DATA' => 'Parámetros incorrectos enviados al Connector',
        'ER:ILLEGAL' =>
          'Comando no permitido (¿falta inicializar o modo sin pantalla?)',
        'WR:CANCEL' => 'Operación cancelada',
        'WR:LEVEL' => 'Aviso: algún hopper/reciclador cerca del límite',
        _ => 'Código: $code',
      };

  // ── Comunicación TCP ──────────────────────────────────────

  Future<String> _enviar(
    String cmd,
    CashlogyConfig cfg, {
    Duration connectTimeout = const Duration(seconds: 12),
    Duration responseTimeout = const Duration(minutes: 5),
  }) async {
    if (cfg.host.trim().isEmpty) {
      throw const CashlogyException('Configura la IP de Cashlogy en ajustes');
    }
    Socket? socket;
    try {
      socket = await Socket.connect(cfg.host.trim(), cfg.port,
          timeout: connectTimeout);
      socket.write(utf8.encode(cmd));
      await socket.flush();
      return await _leerRespuesta(socket, responseTimeout);
    } on SocketException catch (e) {
      throw CashlogyException(
          'No se pudo conectar con ${cfg.host}:${cfg.port} — $e');
    } on TimeoutException {
      throw CashlogyException(
          'Tiempo de espera agotado (${responseTimeout.inSeconds}s)');
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  Future<String> _leerRespuesta(Socket socket, Duration timeout) async {
    final buf = <int>[];
    DateTime ultimoChunk = DateTime.now();
    final done = Completer<void>();

    late final StreamSubscription<List<int>> sub;
    sub = socket.listen(
      (chunk) {
        buf.addAll(chunk);
        ultimoChunk = DateTime.now();
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
      if (buf.isNotEmpty &&
          DateTime.now().difference(ultimoChunk).inMilliseconds >= 500) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    await sub.cancel();
    try {
      await socket.close();
    } catch (_) {}

    if (buf.isEmpty) {
      throw const CashlogyException('Sin respuesta del Cashlogy Connector');
    }
    return utf8.decode(buf, allowMalformed: true).trim();
  }

  // ── API pública ──────────────────────────────────────────

  /// Inicializa la sesión Cashlogy (#I#).
  Future<CashlogyInitResult> inicializar(CashlogyConfig cfg) async {
    final raw = await _enviar('#I#', cfg,
        responseTimeout: const Duration(seconds: 90));
    return _parseInit(raw);
  }

  /// Realiza un cobro por el importe indicado en céntimos.
  Future<CashlogyChargeResult> cobrar({
    required CashlogyConfig cfg,
    required int centimos,
    required String numOperacion,
  }) async {
    if (centimos <= 0) {
      throw const CashlogyException('El importe debe ser mayor que cero');
    }
    final cmd = _cmdCobro(
        numOp: numOperacion, caja: cfg.tillCode, centimos: centimos);
    final raw = await _enviar(cmd, cfg);
    return _parseCobro(raw, centimos);
  }

  /// Inicializa y cobra en una sola operación.
  Future<CashlogyChargeResult> inicializarYCobrar({
    required CashlogyConfig cfg,
    required int centimos,
    required String numOperacion,
  }) async {
    final init = await inicializar(cfg);
    if (!init.ok) {
      throw CashlogyException(
          'Error al inicializar Cashlogy: ${init.error ?? init.raw}');
    }
    return cobrar(cfg: cfg, centimos: centimos, numOperacion: numOperacion);
  }
}
