// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class ApiService extends ChangeNotifier {
  String _baseUrl = '';
  String? _token;
  bool _serverReachable = true;

  String get baseUrl => _baseUrl;
  bool get serverReachable => _serverReachable;
  bool get hasToken => _token != null;

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
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
          res = await http.get(uri, headers: _headers)
              .timeout(const Duration(seconds: 8));
        } else {
          res = await http.post(uri,
              headers: _headers,
              body: body != null ? json.encode(body) : null)
              .timeout(const Duration(seconds: 15));
        }


        debugPrint('>>> URL: $uri');
        debugPrint('>>> STATUS: ${res.statusCode}');
        debugPrint('>>> BODY: ${res.body}');
        
        _setReachable(true);

        final data = json.decode(res.body) as Map<String, dynamic>;
        if (data['ok'] == true) return data['data'] as Map<String, dynamic>? ?? {};
        throw ApiException(data['error'] ?? 'Error del servidor', statusCode: res.statusCode);

      } on TimeoutException {
        _setReachable(false);
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        if (e is ApiException) rethrow;
        _setReachable(false);
        if (attempt == maxRetries - 1) throw ApiException('Sin conexión al servidor');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    throw ApiException('Sin conexión al servidor');
  }

  Future<List<dynamic>> _requestList(String path) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final uri = Uri.parse('$_baseUrl/api$path');
        final res = await http.get(uri, headers: _headers)
            .timeout(const Duration(seconds: 8));
        _setReachable(true);
        final data = json.decode(res.body);
        if (data['ok'] == true) {
          return data['data'] as List<dynamic>;
        }
        throw ApiException(data['error'] ?? 'Error');
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
    try {
      final uri = Uri.parse('$_baseUrl/api/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      final ok = res.statusCode == 200;
      _setReachable(ok);
      return ok;
    } catch (_) {
      _setReachable(false);
      return false;
    }
  }

  // ── Usuarios ───────────────────────────────────────────────
  Future<List<Usuario>> getUsuarios() async {
    final list = await _requestList('/usuarios/lista');
    return list.map((j) => Usuario.fromJson(j as Map<String, dynamic>)).toList();
  }

  // ── Login ──────────────────────────────────────────────────
  Future<Map<String, dynamic>> login(int idUsuario, String password) async {
    final data = await _request('POST', '/auth/login',
        body: {'id_usuario': idUsuario, 'password': password});
    return data;
  }

  // ── Catálogo ───────────────────────────────────────────────
  Future<Map<String, dynamic>> getCatalogo() async {
    return await _request('GET', '/catalogo');
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
      body['nombre_producto'] = nombreProducto.trim();
    }
    final data = await _request('POST', '/productos/copiar', body: body);
    return int.parse(data['id_producto'].toString());
  }

  // ── Mesas ──────────────────────────────────────────────────
  Future<List<MesaResumen>> getMesas() async {
    final list = await _requestList('/mesas');
    return list.map((j) => MesaResumen.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<int> abrirMesa(int numMesa) async {
    final data = await _request('POST', '/mesas/abrir', body: {'id_mesa': numMesa});
    return int.parse(data['id_pedido'].toString());
  }

  Future<void> bloquearMesa(int idPedido) async {
    await _request('POST', '/mesas/$idPedido/bloquear');
  }

  Future<void> pingMesa(int idPedido) async {
    await _request('POST', '/mesas/$idPedido/ping');
  }

  Future<void> cerrarMesa(int idPedido) async {
    await _request('POST', '/mesas/$idPedido/cerrar');
  }

  Future<void> expulsarUsuario(int idPedido) async {
    await _request('POST', '/mesas/$idPedido/expulsar');
  }

  // ── Pedidos ────────────────────────────────────────────────
  Future<Map<String, dynamic>> getPedido(int idPedido) async {
    return await _request('GET', '/pedidos/$idPedido');
  }

  Future<void> guardarPedido(int idPedido, List<LineaPedido> lineas) async {
    await _request('POST', '/pedidos/$idPedido/guardar', body: {
      'lineas': lineas.map((l) => l.toJson()).toList(),
    });
  }
}
