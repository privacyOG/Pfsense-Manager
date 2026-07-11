import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../models/profile.dart';
import '../utils/api_exception.dart';
import '../utils/ping_request_validation.dart';

/// Core HTTP client for pfSense REST API.
class PfSenseApiClient {
  late final Dio _dio;
  final PfSenseProfile profile;
  bool _disposed = false;
  String? _jwtToken;
  Future<String>? _jwtTokenRequest;

  PfSenseApiClient(this.profile, {Dio? dio}) {
    if (!profile.useHttps) {
      throw const ApiException(
        'HTTPS is required for pfSense API connections. Edit this profile and use an HTTPS endpoint.',
      );
    }

    final options = BaseOptions(
      baseUrl: profile.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: false,
      maxRedirects: 0,
      headers: {},
    );
    _dio = dio ?? Dio(options);
    if (dio != null) {
      _dio.options
        ..baseUrl = options.baseUrl
        ..connectTimeout = options.connectTimeout
        ..receiveTimeout = options.receiveTimeout
        ..followRedirects = options.followRedirects
        ..maxRedirects = options.maxRedirects
        ..headers = <String, dynamic>{};
    }

    if (dio == null && profile.allowSelfSignedCert) {
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

  @visibleForTesting
  Dio get debugDio => _dio;

  void _setupAuth() {
    _dio.options.headers.remove('X-API-Key');
    _dio.options.headers.remove('Authorization');

    switch (profile.authMode) {
      case PfSenseAuthMode.apiKey:
        if (profile.apiKey.isEmpty) {
          throw const ApiException(
            'This API-key profile does not have an API key configured.',
          );
        }
        _dio.options.headers['X-API-Key'] = profile.apiKey;
        return;
      case PfSenseAuthMode.jwtPassword:
        if (profile.username.trim().isEmpty || profile.password.isEmpty) {
          throw const ApiException(
            'This JWT profile requires an explicit username and password.',
          );
        }
        return;
    }
  }

  /// Obtains the JWT token for a password-authenticated profile.
  ///
  /// API-key profiles cannot use this method and their key is never
  /// reinterpreted as a Basic authentication password.
  Future<String> getJwtToken() async {
    _ensureActive();
    if (profile.authMode != PfSenseAuthMode.jwtPassword) {
      throw const ApiException(
        'JWT login is only available for password-authenticated profiles.',
      );
    }

    final existing = _jwtToken;
    if (existing != null && existing.isNotEmpty) return existing;
    final pending = _jwtTokenRequest;
    if (pending != null) return pending;

    final request = _requestJwtToken();
    _jwtTokenRequest = request;
    try {
      final token = await request;
      _ensureActive();
      _jwtToken = token;
      return token;
    } finally {
      if (identical(_jwtTokenRequest, request)) _jwtTokenRequest = null;
    }
  }

  Future<String> _requestJwtToken() async {
    final authorization = buildBasicAuthorization(
      profile.username,
      profile.password,
    );
    try {
      final response = await _dio.post(
        '/api/v2/auth/jwt',
        options: Options(
          headers: {'Authorization': authorization},
        ),
      );
      _ensureActive();
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final data = response.data;
        final payload = data is Map ? data['data'] : null;
        final token = payload is Map ? payload['token']?.toString() : null;
        if (token != null && token.isNotEmpty) return token;
        throw const ApiException(
          'pfSense JWT login succeeded without returning a token.',
        );
      }
      throw ApiException(
        _extractErrorMessage(response.data),
        response.statusCode,
      );
    } on DioException catch (error) {
      if (_disposed) throw const ApiException('The pfSense session was closed.');
      throw ApiException.fromDio(error);
    }
  }

  Future<void> _prepareRequestAuth() async {
    if (profile.authMode != PfSenseAuthMode.jwtPassword) return;
    final token = await getJwtToken();
    _dio.options.headers.remove('X-API-Key');
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _request('GET', path, queryParameters: queryParameters);
  }

  Future<List<int>> getRawBytes(String path) async {
    _ensureActive();
    await _prepareRequestAuth();
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
    await _prepareRequestAuth();
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
        'pfSense web UI is reachable, but the REST API did not answer. Install/enable the pfSense REST API package and configure authentication.',
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
    _jwtToken = null;
    _jwtTokenRequest = null;
    _dio.close(force: true);
  }
}

String buildBasicAuthorization(String username, String password) {
  if (username.trim().isEmpty || password.isEmpty) {
    throw const ApiException(
      'JWT authentication requires an explicit username and password.',
    );
  }
  final credentials = '${username.trim()}:$password';
  return 'Basic ${base64Encode(utf8.encode(credentials))}';
}

Map<String, dynamic> buildPingPayload(dynamic data) {
  if (data is! Map) return {};
  final payload = Map<String, dynamic>.from(data);
  final countValue = payload['count'];
  if (countValue != null) {
    final count = countValue is int
        ? countValue
        : int.tryParse(countValue.toString().trim());
    if (count == null) {
      throw ArgumentError.value(
        countValue,
        'count',
        'Ping packet count must be an integer between $pingPacketCountMinimum and $pingPacketCountMaximum.',
      );
    }
    payload['count'] = validatePingPacketCount(count);
  }
  final legacySource = payload.remove('interface');
  final source = payload['source_address'] ?? legacySource;
  if (source != null && source.toString().trim().isNotEmpty) {
    payload['source_address'] = source.toString().trim();
  }
  return payload;
}
