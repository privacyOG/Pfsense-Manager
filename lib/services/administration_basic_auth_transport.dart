import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../models/profile.dart';
import '../utils/api_exception.dart';

abstract class AdministrationBasicAuthTransport {
  Future<Response<dynamic>> post(String path, {dynamic data});

  Future<Response<dynamic>> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
  });
}

class PfSenseBasicAuthTransport implements AdministrationBasicAuthTransport {
  const PfSenseBasicAuthTransport(this.profile);

  final PfSenseProfile profile;

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) {
    return _request('POST', path, data: data);
  }

  @override
  Future<Response<dynamic>> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _request(
      'DELETE',
      path,
      queryParameters: queryParameters,
    );
  }

  Future<Response<dynamic>> _request(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (profile.authMode != PfSenseAuthMode.jwtPassword ||
        profile.username.trim().isEmpty ||
        profile.password.isEmpty) {
      throw const ApiException(
        'This operation requires a password-authenticated profile.',
      );
    }

    final dio = Dio(
      BaseOptions(
        baseUrl: profile.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );
    if (profile.useHttps && profile.allowSelfSignedCert) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true,
      );
    }

    final authorization =
        'Basic ${base64Encode(utf8.encode('${profile.username}:${profile.password}'))}';
    try {
      final response = await dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: {'Authorization': authorization},
        ),
      );
      final status = response.statusCode;
      if (status == null || status < 200 || status >= 300) {
        throw ApiException(_message(response.data), status);
      }
      final body = response.data;
      if (body is Map) {
        final code = body['code'];
        if (code is num && code >= 400) {
          throw ApiException(_message(body), code.toInt());
        }
      }
      return response;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    } finally {
      dio.close(force: true);
    }
  }
}

String _message(dynamic data) {
  if (data is Map) {
    for (final key in const ['message', 'error', 'status']) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
  }
  return 'The pfSense administrative request failed.';
}