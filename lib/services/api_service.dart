// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class ApiService extends ChangeNotifier {
  static const _deviceChannel =
      MethodChannel('com.restaurante.restaurante_tpv/device');

  String _baseUrl = '';
  String? _token;
  bool _serverReachable = true;
  String? _lastHealthError;
  bool _tokenExpirado = false;
  String? _terminalSerieCache;
  final http.Client _httpClient = http.Client();

  String get baseUrl => _baseUrl;
  bool get serverReachable => _serverReachable;
  String? get lastHealthError => _lastHealthError;
  bool get hasToken => _token != null;
  bool get tokenExpirado => _tokenExpirado;

  void resetTokenExpirado() {
    _tokenExpirado = false;
    notifyListeners();
  }

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _lastHealthError = null;
    notifyListeners();
  }

  void setToken(String token) {
    _token = token;
    notifyListeners();
  }

  void clearToken() {
    _token = null;
    notifyListeners();
  }

  void _setReachable(bool v) {
    if (_serverReachable != v) {
      _serverReachable = v;
      notifyListeners();
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  String _sha256(String input) => sha256.convert(utf8.encode(input)).toString();

  String _passwordHash(String nombreUsuario, String password) =>
      _sha256('${nombreUsuario.trim()}$password');

  /// Serie de hardware (Build.getSerial / Build.SERIAL), como antes con device_info_plus.
  Future<String?> _androidHardwareSerial() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final raw = await _deviceChannel.invokeMethod<String>('getDeviceSerial');
      final t = raw?.trim() ?? '';
      if (t.isNotEmpty && t.toLowerCase() != 'unknown') return t;
    } catch (_) {}
    return null;
  }

  Future<String> terminalSerie() async {
    if (_terminalSerieCache != null && _terminalSerieCache!.isNotEmpty) {
      return _terminalSerieCache!;
    }
    if (kIsWeb || !Platform.isAndroid) {
      final prefs = await SharedPreferences.getInstance();
      var local = prefs.getString('terminal_serie_local')?.trim() ?? '';
      if (local.isEmpty) {
        local =
            'desk-${DateTime.now().millisecondsSinceEpoch}-${identityHashCode(this)}';
        if (local.length > 120) local = local.substring(0, 120);
        await prefs.setString('terminal_serie_local', local);
      }
      _terminalSerieCache = local;
      return _terminalSerieCache!;
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final candidates = <String?>[
        await _androidHardwareSerial(),
        info.id,
        info.fingerprint,
        '${info.manufacturer}-${info.model}',
      ];
      final raw = candidates.firstWhere(
        (v) => v != null && v.trim().isNotEmpty && v.trim() != 'unknown',
        orElse: () => 'terminal-android',
      )!;
      _terminalSerieCache = raw.trim();
    } catch (_) {
      _terminalSerieCache = 'terminal-android';
    }
    if (_terminalSerieCache!.length > 120) {
      _terminalSerieCache = _terminalSerieCache!.substring(0, 120);
    }
    return _terminalSerieCache!;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    int maxRetries = 3,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final uri = Uri.parse('$_baseUrl/api$path');
        late http.Response res;

        if (method == 'GET') {
          res = await _httpClient
              .get(uri, headers: _headers)
              .timeout(const Duration(seconds: 8));
        } else {
          res = await _httpClient
              .post(uri,
                  headers: _headers,
                  body: body != null ? json.encode(body) : null)
              .timeout(const Duration(seconds: 15));
        }

        if (kDebugMode) {
          debugPrint('>>> URL: $uri');
          debugPrint('>>> STATUS: ${"{"}res.statusCode{"}"}');
          debugPrint('>>> BODY: ${"{"}res.body{"}"}');
        }

        _setReachable(true);

        final data = json.decode(res.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          return data['data'] as Map<String, dynamic>? ?? {};
        }
        if (_token != null &&
            (res.statusCode == 401 || res.statusCode == 403)) {
          _tokenExpirado = true;
          notifyListeners();
        }
        throw ApiException(data['error'] ?? 'Error del servidor',
            statusCode: res.statusCode);
      } on TimeoutException {
        _setReachable(false);
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        if (e is ApiException) rethrow;
        _setReachable(false);
        if (attempt == maxRetries - 1) {
          throw ApiException('Sin conexión al servidor');
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw ApiException('Sin conexión al servidor');
  }

  Future<List<dynamic>> _requestList(String path) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final uri = Uri.parse('$_baseUrl/api$path');
        final res = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 8));
        _setReachable(true);
        final data = json.decode(res.body);
        if (data['ok'] == true) {
          return data['data'] as List<dynamic>;
        }
        if (_token != null &&
            (res.statusCode == 401 || res.statusCode == 403)) {
          _tokenExpirado = true;
          notifyListeners();
        }
        throw ApiException(data['error'] ?? 'Error',
            statusCode: res.statusCode);
      } on TimeoutException {
        _setReachable(false);
        if (attempt == 2) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        if (e is ApiException) rethrow;
        _setReachable(false);
        if (attempt == 2) throw ApiException('Sin conexión al servidor');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw ApiException('Sin conexión al servidor');
  }

  // ── Health check ───────────────────────────────────────────
  Future<bool> checkHealth() async {
    _lastHealthError = null;
    try {
      final uri = Uri.parse('$_baseUrl/api/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      final ok = res.statusCode == 200;
      if (!ok) {
        _lastHealthError = res.statusCode == 404
            ? 'El servidor responde, pero no existe /api/health. Revisa que Apache redirija /api al backend.'
            : 'El servidor responde con HTTP ${res.statusCode} al comprobar /api/health.';
      }
      _setReachable(ok);
      return ok;
    } on TimeoutException {
      _lastHealthError =
          'Tiempo de espera agotado al conectar con el servidor.';
      _setReachable(false);
      return false;
    } catch (e) {
      _lastHealthError = 'No se pudo conectar con el servidor: $e';
      _setReachable(false);
      return false;
    }
  }

  // ── Usuarios ───────────────────────────────────────────────
  Future<List<Usuario>> getUsuarios() async {
    const path = '/usuarios/lista';
    const tag = '[getUsuarios]';

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final uri = Uri.parse('$_baseUrl/api$path');
        debugPrint('$tag GET $uri (intento ${attempt + 1}/3)');

        final res = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 8));

        debugPrint('$tag status=${res.statusCode}');
        debugPrint('$tag body=${res.body}');

        _setReachable(true);

        if (res.statusCode != 200) {
          if (kDebugMode) {
            debugPrint(
                '$tag ERROR HTTP ${res.statusCode}: cuerpo no procesado como OK');
          }
          throw ApiException(
            'HTTP ${res.statusCode}: ${res.body.length > 200 ? '${res.body.substring(0, 200)}…' : res.body}',
            statusCode: res.statusCode,
          );
        }

        final dynamic decoded;
        try {
          decoded = json.decode(res.body);
        } catch (e, st) {
          if (kDebugMode) debugPrint('$tag ERROR JSON inválido: $e');
          if (kDebugMode) debugPrint('$tag $st');
          throw ApiException('Respuesta no es JSON válido');
        }

        if (decoded is! Map<String, dynamic>) {
          debugPrint(
              '$tag ERROR: raíz JSON inesperada (${decoded.runtimeType})');
          throw ApiException('Formato de respuesta inesperado');
        }

        if (decoded['ok'] != true) {
          final err = decoded['error']?.toString() ?? 'sin mensaje';
          debugPrint('$tag ERROR servidor (ok!=true): $err');
          throw ApiException(err, statusCode: res.statusCode);
        }

        final data = decoded['data'];
        if (data == null) {
          debugPrint('$tag ERROR: campo "data" ausente');
          throw ApiException('Respuesta sin lista de usuarios');
        }
        if (data is! List) {
          debugPrint(
              '$tag ERROR: "data" no es lista (${data.runtimeType}): $data');
          throw ApiException('Lista de usuarios con formato incorrecto');
        }

        final usuarios = <Usuario>[];
        for (var i = 0; i < data.length; i++) {
          final item = data[i];
          if (item is! Map<String, dynamic>) {
            debugPrint('$tag AVISO ítem[$i] ignorado (no es objeto): $item');
            continue;
          }
          try {
            usuarios.add(Usuario.fromJson(item));
          } catch (e, st) {
            debugPrint('$tag ERROR parseando ítem[$i]: $item');
            debugPrint('$tag $e');
            debugPrint('$tag $st');
          }
        }

        if (usuarios.isEmpty && data.isNotEmpty) {
          debugPrint(
              '$tag AVISO: ${data.length} ítems en respuesta pero ningún usuario válido');
        } else {
          debugPrint('$tag OK: ${usuarios.length} usuario(s)');
        }

        return usuarios;
      } on TimeoutException {
        debugPrint('$tag TIMEOUT conectando con el servidor');
        _setReachable(false);
        if (attempt == 2) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      } on ApiException catch (e) {
        debugPrint('$tag ApiException: ${e.message} (HTTP ${e.statusCode})');
        if (attempt == 2) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      } catch (e, st) {
        debugPrint('$tag EXCEPCIÓN: $e');
        debugPrint('$tag $st');
        _setReachable(false);
        if (attempt == 2) {
          throw ApiException('Sin conexión al servidor');
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    debugPrint('$tag ERROR: agotados reintentos');
    throw ApiException('Sin conexión al servidor');
  }

  // ── Login ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> login(
      int idUsuario, String nombreUsuario, String password) async {
    final data = await _request('POST', '/auth/login', body: {
      'id_usuario': idUsuario,
      'password_sha256': _passwordHash(nombreUsuario, password),
    });
    return data;
  }

  // ── Servicio en mesa ─────────────────────────────────────────
  Future<List<PedidoPendienteServir>> getServicioPendientes() async {
    final list = await _requestList('/servicio/pendientes');
    return list
        .map((j) => PedidoPendienteServir.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<int> marcarLineasServidas(List<int> idsLinea) async {
    if (idsLinea.isEmpty) return 0;
    final data = await _request('POST', '/servicio/marcar-servido', body: {
      'ids_linea': idsLinea,
    });
    return int.parse((data['actualizadas'] ?? 0).toString());
  }

  Future<bool> marcarLineaUrgente(
    int idPedido,
    int idLinea, {
    required bool urgente,
  }) async {
    final data = await _request('POST', '/pedidos/$idPedido/urgente', body: {
      'id_linea': idLinea,
      'urgente': urgente,
      'terminal_serie': await terminalSerie(),
    });
    return data['urgente'] == true;
  }

  /// SSE: emite cuando cambia la cola de pendientes de servir (cocina/barra).
  /// Reconecta automáticamente si el servidor cierra la conexión (~55 s).
  Stream<void> subscribeServicioPendientesUpdates() async* {
    if (_token == null || _baseUrl.isEmpty) return;

    while (true) {
      try {
        final uri = Uri.parse('$_baseUrl/servicio/stream');
        final req = http.Request('GET', uri);
        req.headers.addAll({
          'Authorization': 'Bearer $_token',
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
        });

        final resp =
            await _httpClient.send(req).timeout(const Duration(seconds: 90));
        if (resp.statusCode == 401) {
          _tokenExpirado = true;
          notifyListeners();
          return;
        }
        if (resp.statusCode != 200) {
          await Future<void>.delayed(const Duration(seconds: 5));
          continue;
        }
        _setReachable(true);

        var buffer = '';
        await for (final chunk in resp.stream.transform(utf8.decoder)) {
          buffer += chunk;
          while (true) {
            final sep = buffer.indexOf('\n\n');
            if (sep < 0) break;
            final block = buffer.substring(0, sep);
            buffer = buffer.substring(sep + 2);
            if (block.contains('event: update')) {
              yield null;
            }
          }
        }
      } catch (_) {
        _setReachable(false);
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  /// Registra o actualiza el dispositivo actual en la tabla `dispositivos`.
  /// Se llama tras el login; los errores no interrumpen el flujo pero sí se
  /// imprimen en consola para facilitar el diagnóstico.
  Future<void> registrarDispositivo() async {
    try {
      String idDispositivo = await terminalSerie();
      String nombreDispositivo = 'Dispositivo desconocido';
      int? bateria;

      if (!kIsWeb && Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        final fabricante = info.manufacturer.trim();
        final modelo = info.model.trim();
        nombreDispositivo =
            (fabricante.isNotEmpty && !modelo.startsWith(fabricante))
                ? '$fabricante $modelo'
                : modelo;
      }

      try {
        final batt = Battery();
        bateria = await batt.batteryLevel;
      } catch (e) {
        debugPrint('[dispositivo] No se pudo leer la batería: $e');
        bateria = null;
      }

      debugPrint('[dispositivo] Enviando ping — '
          'id=$idDispositivo  nombre=$nombreDispositivo  bateria=$bateria');

      await _request('POST', '/dispositivos/ping', body: {
        'id_dispositivo': idDispositivo,
        'nombre_dispositivo': nombreDispositivo,
        if (bateria != null) 'bateria': bateria,
      });

      debugPrint('[dispositivo] Ping OK');
    } catch (e) {
      debugPrint('[dispositivo] Error al registrar: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getUsuariosAdmin() async {
    final list = await _requestList('/usuarios/admin/lista');
    return list
        .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<int> crearUsuarioAdmin(Map<String, dynamic> body) async {
    final payload = Map<String, dynamic>.from(body);
    if (payload['password'] is String) {
      final password = (payload['password'] as String).trim();
      final nombre = (payload['nombre_usuario'] as String? ?? '').trim();
      if (password.isNotEmpty) {
        payload['password_sha256'] = _passwordHash(nombre, password);
      }
      payload.remove('password');
    }
    final data = await _request('POST', '/usuarios/admin/crear', body: payload);
    return int.parse(data['id_usuario'].toString());
  }

  Future<void> actualizarUsuarioAdmin(
      int idUsuario, Map<String, dynamic> body) async {
    final payload = Map<String, dynamic>.from(body);
    if (payload['password'] is String) {
      final password = (payload['password'] as String).trim();
      final nombre = (payload['nombre_usuario'] as String? ?? '').trim();
      if (password.isNotEmpty) {
        payload['password_sha256'] = _passwordHash(nombre, password);
      }
      payload.remove('password');
    }
    await _request('POST', '/usuarios/admin/$idUsuario/actualizar',
        body: payload);
  }

  Future<void> eliminarUsuarioAdmin(int idUsuario) async {
    await _request('POST', '/usuarios/admin/$idUsuario/eliminar');
  }

  Future<List<Map<String, dynamic>>> getImpresorasConfig() async {
    final uri = Uri.parse('$_baseUrl/api/impresoras/config');
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    final data = json.decode(res.body) as Map<String, dynamic>;
    if (data['ok'] == true) {
      final list = data['data'] as List<dynamic>;
      return list
          .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
          .toList();
    }
    throw ApiException(
        data['error']?.toString() ?? 'Error al cargar impresoras',
        statusCode: res.statusCode);
  }

  Future<void> saveImpresorasConfig(
      List<Map<String, dynamic>> impresoras) async {
    final uri = Uri.parse('$_baseUrl/api/impresoras/config');
    final res = await http
        .post(uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: json.encode({'impresoras': impresoras}))
        .timeout(const Duration(seconds: 15));
    final data = json.decode(res.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw ApiException(
          data['error']?.toString() ?? 'Error al guardar impresoras',
          statusCode: res.statusCode);
    }
  }

  Future<Map<String, dynamic>> crearImpresoraConfig({
    String nombre = '',
    String ip = '',
    int puerto = 9100,
    String tablaCodigos = 'CP1252',
  }) async {
    final uri = Uri.parse('$_baseUrl/api/impresoras/config/crear');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: json.encode({
            'nombre': nombre,
            'ip': ip,
            'puerto': puerto,
            'tabla_codigos': tablaCodigos,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = json.decode(res.body) as Map<String, dynamic>;
    if (data['ok'] == true) {
      return Map<String, dynamic>.from(data['data'] as Map<dynamic, dynamic>);
    }
    throw ApiException(data['error']?.toString() ?? 'Error al crear impresora',
        statusCode: res.statusCode);
  }

  Future<void> eliminarImpresoraConfig(int idImpresora) async {
    final uri =
        Uri.parse('$_baseUrl/api/impresoras/config/$idImpresora/eliminar');
    final res = await http.post(uri, headers: {
      'Content-Type': 'application/json; charset=utf-8'
    }).timeout(const Duration(seconds: 15));
    final data = json.decode(res.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw ApiException(
          data['error']?.toString() ?? 'Error al eliminar impresora',
          statusCode: res.statusCode);
    }
  }

  // ── Catálogo ───────────────────────────────────────────────
  Future<Map<String, dynamic>> getCatalogo() async {
    return await _request('GET', '/catalogo');
  }

  Future<Map<String, dynamic>> getMenuDia({String? fecha}) async {
    final q = (fecha != null && fecha.isNotEmpty) ? '?fecha=$fecha' : '';
    return await _request('GET', '/menu-dia$q');
  }

  Future<Map<String, dynamic>> guardarMenuDia(Map<String, dynamic> body) async {
    return await _request('POST', '/menu-dia', body: body);
  }

  // ── Productos (admin / supervisor) ─────────────────────────
  Future<List<Map<String, dynamic>>> getProductosLista({String? q}) async {
    final path = (q == null || q.trim().isEmpty)
        ? '/productos'
        : '/productos?q=${Uri.encodeQueryComponent(q.trim())}';
    final list = await _requestList(path);
    return list
        .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getProductoDetalle(int id) async {
    return await _request('GET', '/productos/$id');
  }

  Future<int> crearProducto(Map<String, dynamic> body) async {
    final data = await _request('POST', '/productos/crear', body: body);
    return int.parse(data['id_producto'].toString());
  }

  Future<void> actualizarProducto(int id, Map<String, dynamic> body) async {
    await _request('POST', '/productos/$id/actualizar', body: body);
  }

  Future<void> eliminarProducto(int id) async {
    await _request('POST', '/productos/$id/eliminar');
  }

  Future<int> copiarProducto(
      {required int idOrigen, String? nombreProducto}) async {
    final body = <String, dynamic>{'id_producto_origen': idOrigen};
    if (nombreProducto != null && nombreProducto.trim().isNotEmpty) {
      body['nombre_producto_pantalla'] = nombreProducto.trim();
    }
    final data = await _request('POST', '/productos/copiar', body: body);
    return int.parse(data['id_producto'].toString());
  }

  // ── Mesas ──────────────────────────────────────────────────
  Future<List<MesaResumen>> getMesas() async {
    final terminal = Uri.encodeComponent(await terminalSerie());
    final list = await _requestList('/mesas?terminal_serie=$terminal');
    return list
        .map((j) => MesaResumen.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<int> abrirMesa(int numMesa) async {
    final data = await _request('POST', '/mesas/abrir', body: {
      'id_mesa': numMesa,
      'terminal_serie': await terminalSerie(),
    });
    return int.parse(data['id_pedido'].toString());
  }

  Future<void> bloquearMesa(int idPedido) async {
    await _request('POST', '/mesas/$idPedido/bloquear', body: {
      'terminal_serie': await terminalSerie(),
    });
  }

  Future<void> desbloquearMesa(int idPedido) async {
    await _request('POST', '/mesas/$idPedido/desbloquear', body: {
      'terminal_serie': await terminalSerie(),
    });
  }

  Future<void> pingMesa(int idPedido) async {
    await _request('POST', '/mesas/$idPedido/ping', body: {
      'terminal_serie': await terminalSerie(),
    });
  }

  Future<void> cerrarMesa(int idPedido) async {
    await _request('POST', '/mesas/$idPedido/cerrar', body: {
      'terminal_serie': await terminalSerie(),
    });
  }

  Future<void> expulsarUsuario(int idPedido) async {
    await _request('POST', '/mesas/$idPedido/expulsar', body: {
      'terminal_serie': await terminalSerie(),
    });
  }

  Future<void> traspasarMesa(int idPedido, int idMesaDestino) async {
    await _request('POST', '/mesas/$idPedido/traspasar', body: {
      'id_mesa_destino': idMesaDestino,
      'terminal_serie': await terminalSerie(),
    });
  }

  Future<MesaMovimientos> getMesaMovimientos(int idPedido) async {
    final data = await _request('GET', '/mesas/$idPedido/movimientos');
    return MesaMovimientos.fromJson(data);
  }

  // ── Pedidos ────────────────────────────────────────────────
  Future<Map<String, dynamic>> getPedido(int idPedido) async {
    final terminal = Uri.encodeComponent(await terminalSerie());
    return await _request('GET', '/pedidos/$idPedido?terminal_serie=$terminal');
  }

  Future<Map<String, dynamic>> guardarPedido(
    int idPedido,
    List<LineaPedido> lineas, {
    required String nombreCliente,
    String? horaUltimaAccionRef,
  }) async {
    final body = <String, dynamic>{
      'lineas': lineas.map((l) => l.toJsonParaGuardarPedido()).toList(),
      'terminal_serie': await terminalSerie(),
      'nombre_cliente': nombreCliente.trim(),
    };
    final ref = horaUltimaAccionRef?.trim();
    if (ref != null && ref.isNotEmpty) {
      body['hora_ultima_accion_ref'] = ref;
    }
    return await _request('POST', '/pedidos/$idPedido/guardar', body: body);
  }

  Future<int> crearNotaLibre({
    required int idPedido,
    required String texto,
    required double pvpConIva,
    required int idImpresora,
  }) async {
    final data = await _request('POST', '/pedidos/$idPedido/nota-libre', body: {
      'texto': texto.trim(),
      'pvp_con_iva': pvpConIva,
      'id_impresora': idImpresora,
      'terminal_serie': await terminalSerie(),
    });
    return int.parse(data['id_linea'].toString());
  }

  Future<void> editarNotaLibre({
    required int idPedido,
    required int idLinea,
    required String texto,
    required double pvpConIva,
  }) async {
    await _request('POST', '/pedidos/$idPedido/nota-libre/$idLinea/editar',
        body: {
          'texto': texto.trim(),
          'pvp_con_iva': pvpConIva,
          'terminal_serie': await terminalSerie(),
        });
  }

  // ── Historial de mesas ─────────────────────────────────────
  Future<List<MesaHistorico>> getHistoricoMesas({int dias = 0}) async {
    final path = dias > 0 ? '/historico/mesas?dias=$dias' : '/historico/mesas';
    final list = await _requestList(path);
    return list
        .map((j) => MesaHistorico.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getHistoricoMesaDetalle(int idPedido) async {
    return await _request('GET', '/historico/mesas/$idPedido');
  }

  Future<({int idPedido, int idMesa})> reabrirMesa(int idPedido) async {
    final data = await _request('POST', '/historico/mesas/$idPedido/reabrir',
        body: {'terminal_serie': await terminalSerie()});
    return (
      idPedido: int.parse(data['id_pedido'].toString()),
      idMesa: int.parse(data['id_mesa'].toString()),
    );
  }

  /// Envía al servidor los nuevos órdenes de productos y/o categorías.
  /// [items] es una lista de mapas con las claves:
  ///   - 'tipo': 'producto' | 'categoria'
  ///   - 'id': int
  ///   - 'orden': int
  Future<void> reordenarCatalogo(List<Map<String, dynamic>> items) async {
    await _request('POST', '/catalogo/reordenar', body: {'items': items});
  }

  /// Marca o desmarca un producto como agotado (86) desde cocina/barra.
  Future<void> marcarProductoAgotado(int idProducto, bool agotado) async {
    await _request('POST', '/catalogo/agotado', body: {
      'id_producto': idProducto,
      'agotado': agotado ? 1 : 0,
    });
  }

  /// SSE: emite cuando cambia el estado agotado del catálogo.
  Stream<void> subscribeCatalogoUpdates() async* {
    if (_token == null || _baseUrl.isEmpty) return;

    while (true) {
      try {
        final uri = Uri.parse('$_baseUrl/catalogo/stream');
        final req = http.Request('GET', uri);
        req.headers.addAll({
          'Authorization': 'Bearer $_token',
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
        });

        final resp =
            await _httpClient.send(req).timeout(const Duration(seconds: 90));
        if (resp.statusCode == 401) {
          _tokenExpirado = true;
          notifyListeners();
          return;
        }
        if (resp.statusCode != 200) {
          await Future<void>.delayed(const Duration(seconds: 5));
          continue;
        }
        _setReachable(true);

        var buffer = '';
        await for (final chunk in resp.stream.transform(utf8.decoder)) {
          buffer += chunk;
          while (true) {
            final sep = buffer.indexOf('\n\n');
            if (sep < 0) break;
            final block = buffer.substring(0, sep);
            buffer = buffer.substring(sep + 2);
            if (block.contains('event: update')) {
              yield null;
            }
          }
        }
      } catch (_) {
        _setReachable(false);
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}
