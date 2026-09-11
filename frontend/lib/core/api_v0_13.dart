import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config_v0_13.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// Thin HTTP client around the backend API. Holds the bearer token in memory.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? _token;
  void setToken(String? t) => _token = t;
  String? get token => _token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Future<dynamic> get(String path) async {
    final r = await http.get(_uri(path), headers: _headers);
    return _decode(r);
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final r = await http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {}));
    return _decode(r);
  }

  Future<dynamic> put(String path, [Map<String, dynamic>? body]) async {
    final r = await http.put(_uri(path), headers: _headers, body: jsonEncode(body ?? {}));
    return _decode(r);
  }

  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) async {
    final r = await http.patch(_uri(path), headers: _headers, body: jsonEncode(body ?? {}));
    return _decode(r);
  }

  /// (v0.13) DELETE may carry a body — account deletion sends the password
  /// confirmation. Existing callers that pass no body are unaffected.
  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) async {
    final r = await http.delete(
      _uri(path),
      headers: _headers,
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(r);
  }

  dynamic _decode(http.Response r) {
    final body = r.body.isEmpty ? {} : jsonDecode(r.body);
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    final msg = (body is Map && body['error'] != null) ? body['error'].toString() : 'Request failed (${r.statusCode})';
    throw ApiException(r.statusCode, msg);
  }
}
