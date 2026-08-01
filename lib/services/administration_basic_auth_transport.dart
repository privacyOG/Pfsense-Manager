import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../models/profile.dart';
import '../utils/api_exception.dart';
import 'certificate_trust.dart';

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
    String? certificateFailureMessage;
    if (profile.useHttps && profile.allowSelfSignedCert) {
      final expectedFingerprint = normalizeCertificateFingerprint(
        profile.trustedCertificateSha256,
      );
      if (!isValidCertificateFingerprint(expectedFingerprint)) {
        throw const ApiException(
          'This profile requires a trusted SHA-256 certificate fingerprint. Edit the profile and inspect the firewall certificate before connecting.',
          null,
          false,
          false,
          true,
        );
      }
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (_, __, ___) => true;
          return client;
        },
        validateCertificate: (certificate, host, port) {
          if (certificate == null) {
            certificateFailureMessage =
                'The firewall did not present a TLS certificate.';
            return false;
          }
          final presented = sha256FingerprintFromDer(certificate.der);
          final matches = presented == expectedFingerprint;
          certificateFailureMessage = matches
              ? null
              : 'The firewall certificate changed. Expected ${formatCertificateFingerprint(expectedFingerprint)} but received ${formatCertificateFingerprint(presented)}.';
          return matches;
        },
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
      if (certificateFailureMessage != null &&
          (error.type == DioExceptionType.badCertificate ||
              error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.unknown)) {
        throw ApiException(
          certificateFailureMessage!,
          error.response?.statusCode,
          false,
          false,
          true,
        );
      }
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
