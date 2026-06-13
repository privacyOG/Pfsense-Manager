import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isNetworkError;
  final bool isTimeout;
  final bool isAuthError;

  const ApiException(
    this.message, [
    this.statusCode,
    this.isNetworkError = false,
    this.isTimeout = false,
  ]) : isAuthError = statusCode == 401 || statusCode == 403;

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
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return ApiException(
          'Network error. Cannot reach the pfSense instance.',
          code,
          true,
        );
      default:
        return ApiException(_extractMessage(error.response?.data), code);
    }
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
