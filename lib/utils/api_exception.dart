import 'dart:io';

import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isNetworkError;
  final bool isTimeout;
  final bool isTlsError;

  const ApiException(
    this.message, [
    this.statusCode,
    this.isNetworkError = false,
    this.isTimeout = false,
    this.isTlsError = false,
  ]);

  bool get isAuthenticationError => statusCode == 401;
  bool get isPermissionError => statusCode == 403;
  bool get isEndpointUnavailable => statusCode == 404 || statusCode == 405;

  /// Retained for callers that need to treat both invalid credentials and
  /// insufficient privileges as authorization failures.
  bool get isAuthError => isAuthenticationError || isPermissionError;

  factory ApiException.fromDio(DioException error) {
    final code = error.response?.statusCode;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          'Connection timed out. Check network and pfSense reachability.',
          code,
          false,
          true,
        );
      case DioExceptionType.badCertificate:
        return ApiException(
          'TLS certificate validation failed. Verify the certificate or enable self-signed certificate support for this profile.',
          code,
          false,
          false,
          true,
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        if (_looksLikeTlsFailure(error)) {
          return ApiException(
            'TLS negotiation failed. Verify the certificate, hostname and protocol settings.',
            code,
            false,
            false,
            true,
          );
        }
        return ApiException(
          'Network error. Cannot reach the pfSense instance.',
          code,
          true,
        );
      default:
        return ApiException(_extractMessage(error.response?.data), code);
    }
  }

  static bool _looksLikeTlsFailure(DioException error) {
    final cause = error.error;
    if (cause is HandshakeException || cause is CertificateException) return true;
    final text = '${error.message ?? ''} ${cause ?? ''}'.toLowerCase();
    return text.contains('certificate') ||
        text.contains('handshake') ||
        text.contains('tls') ||
        text.contains('ssl');
  }

  static String _extractMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data['message'] as String? ??
          data['error'] as String? ??
          'API error';
    }
    return 'Unknown API error';
  }

  @override
  String toString() {
    return statusCode == null ? message : '$message ($statusCode)';
  }
}

class AppException implements Exception {
  final String message;
  final String? code;

  const AppException(this.message, [this.code]);

  @override
  String toString() => code == null ? message : '$message [$code]';
}
