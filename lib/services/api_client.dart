import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import '../utils/api_exception.dart';

/// Core HTTP client for pfSense REST API.
class PfSenseApiClient {
  late final Dio _dio;
  final PfSenseProfile profile;
  final bool _useApiKey = true;
  bool _disposed = false;

  PfSenseApiClient(this.profile) {
    if (!profile.useHttps) {
      throw const ApiException(
        'HTTPS is required for pfSense API connections. Edit this profile and use an HTTPS endpoint.',
      );
    }

    _dio = Dio(
      BaseOptions(
        baseUrl: profile.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: false,
        maxRedirects: 0,
        headers: {},
      ),
    );

    if (profile.allowSelfSignedCert) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (_, __, ___) => true;
          return client;
        },
      );
    }

    _setupAuth();
  }

  @visibleForTesting
  BaseOptions get debugOptions => _dio.options;

  void _setupAuth() {
    if (_useApiKey && profile.apiKey.isNotEmpty) {
      _dio.options.headers['X-API-Key'] = profile.apiKey;
    } else {
      final credentials = '${profile.username}:${profile.apiKey}';
      final encoded = base64Encode(utf8.encode(credentials));
      _dio.options.headers['Authorization'] = 'Basic $encoded';
    }
  }

  /// Switch to JWT auth mode (get token, then use Bearer)
  Future<String> getJwtToken() async {
    _ensureActive();
    try {
      final credentials = '${profile.username}:${profile.apiKey}';
      final encoded = base64Encode(utf8.encode(credentials));

      final response = await _dio.post(
        '/api/v2/auth/jwt',
        options: Options(headers: {'Authorization': "Basic $encoded"}),
      );

      if (response.statusCode == 200) {
        return response.data['data']['token'] as String;
      }
      throw ApiException('Failed to get JWT token', response.statusCode);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _request('GET', path, queryParameters: queryParameters);
  }

  Future<List<int>> getRawBytes(String path) async {
    _ensureActive();
    try {
      final response = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      _ensureActive();
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        return response.data ?? [];
      }
      throw ApiException('Download failed', response.statusCode);
    } on DioException catch (e) {
      if (_disposed) throw const ApiException('The pfSense session was closed.');
      throw ApiException.fromDio(e);
    }
  }

  Future<Response> post(String path, {dynamic data}) async {
    return _request('POST', path, data: data);
  }

  Future<Response> put(String path, {dynamic data}) async {
    return _request('PUT', path, data: data);
  }

  Future<Response> patch(String path, {dynamic data}) async {
    return _request('PATCH', path, data: data);
  }

  Future<Response> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _request('DELETE', path, queryParameters: queryParameters);
  }

  Future<Response> _request(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    _ensureActive();
    final requestPath = _normalisedPath(method, path);
    final requestData = _normalisedData(method, requestPath, data);
    try {
      final response = await _dio.request(
        requestPath,
        data: requestData,
        queryParameters: queryParameters,
        options: Options(method: method),
      );
      _ensureActive();

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        _validateApiResponse(requestPath, response.data);
        if (_requiresFirewallApply(method, requestPath)) {
          await _applyFirewallChanges();
        }
        return response;
      }

      throw ApiException(
        _extractErrorMessage(response.data),
        response.statusCode,
      );
    } on DioException catch (e) {
      if (_disposed) {
        throw const ApiException('The pfSense session was closed.');
      }
      throw ApiException.fromDio(e);
    }
  }

  String _normalisedPath(String method, String path) {
    if (method == 'POST' && path == '/api/v2/firewall/rules') {
      return '/api/v2/firewall/rule';
    }
    if (method == 'GET' && path == '/api/v2/vpn/wireguard/servers') {
      return '/api/v2/vpn/wireguard/tunnels';
    }
    return path;
  }

  dynamic _normalisedData(String method, String path, dynamic data) {
    if (method == 'POST' && path == '/api/v2/diagnostics/ping') {
      return buildPingPayload(data);
    }
    return data;
  }

  bool _requiresFirewallApply(String method, String path) {
    return path == '/api/v2/firewall/rule' &&
        (method == 'POST' || method == 'PATCH' || method == 'DELETE');
  }

  Future<void> _applyFirewallChanges() async {
    final response = await _dio.post('/api/v2/firewall/apply');
    _ensureActive();
    if (response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300) {
      _validateApiResponse('/api/v2/firewall/apply', response.data);
      return;
    }
    throw ApiException(_extractErrorMessage(response.data), response.statusCode);
  }

  void _validateApiResponse(String path, dynamic data) {
    if (!path.startsWith('/api/')) return;

    if (data is Map<String, dynamic>) return;

    if (data is String && data.toLowerCase().contains('<html')) {
      throw const ApiException(
        'pfSense web UI is reachable, but the REST API did not answer. Install/enable the pfSense REST API package and create an API key.',
      );
    }

    throw const ApiException(
      'pfSense REST API returned an unexpected response. Check REST API settings and credentials.',
    );
  }

  String _extractErrorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data['message'] as String? ?? 'API Error';
    }
    return 'Unknown error';
  }

  void _ensureActive() {
    if (_disposed) {
      throw const ApiException('The pfSense session was closed.');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dio.close(force: true);
  }
}

Map<String, dynamic> buildPingPayload(dynamic data) {
  if (data is! Map) return {};
  final payload = Map<String, dynamic>.from(data);
  final legacySource = payload.remove('interface');
  final source = payload['source_address'] ?? legacySource;
  if (source != null && source.toString().trim().isNotEmpty) {
    payload['source_address'] = source.toString().trim();
  }
  return payload;
}
