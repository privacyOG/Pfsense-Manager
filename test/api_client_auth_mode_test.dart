import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  test('API-key profiles send only the API-key header', () {
    final client = PfSenseApiClient(
      PfSenseProfile(
        id: 'api-key-profile',
        name: 'API key profile',
        host: 'firewall.example.test',
        username: 'api-user',
        authMode: PfSenseAuthMode.apiKey,
        apiKey: 'configured-api-key',
        password: 'must-not-be-used',
      ),
    );
    addTearDown(client.dispose);

    expect(client.debugOptions.headers['X-API-Key'], 'configured-api-key');
    expect(client.debugOptions.headers.containsKey('Authorization'), isFalse);
  });

  test('API-key profiles cannot request a JWT token', () async {
    final client = PfSenseApiClient(
      PfSenseProfile(
        id: 'api-key-jwt-block',
        name: 'API key profile',
        host: 'firewall.example.test',
        username: 'api-user',
        apiKey: 'configured-api-key',
      ),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.getJwtToken(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('only available for password-authenticated profiles'),
        ),
      ),
    );
  });

  test('JWT login uses the explicit password and subsequent Bearer token',
      () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = PfSenseApiClient(
      PfSenseProfile(
        id: 'jwt-profile',
        name: 'JWT profile',
        host: 'firewall.example.test',
        username: 'local-admin',
        authMode: PfSenseAuthMode.jwtPassword,
        apiKey: 'must-not-be-used',
        password: 'local-password',
      ),
      dio: dio,
    );
    addTearDown(client.dispose);

    expect(client.debugOptions.headers.containsKey('X-API-Key'), isFalse);
    expect(client.debugOptions.headers.containsKey('Authorization'), isFalse);

    await client.get('/api/v2/status/system');
    await client.get('/api/v2/status/interfaces');

    expect(adapter.requests, hasLength(3));
    final login = adapter.requests[0];
    final system = adapter.requests[1];
    final interfaces = adapter.requests[2];

    expect(login.path, '/api/v2/auth/jwt');
    expect(_decodeBasic(login.headers['Authorization']),
        'local-admin:local-password');
    expect(login.headers.containsKey('X-API-Key'), isFalse);

    expect(system.headers['Authorization'], 'Bearer issued-token');
    expect(system.headers.containsKey('X-API-Key'), isFalse);
    expect(interfaces.headers['Authorization'], 'Bearer issued-token');
    expect(interfaces.headers.containsKey('X-API-Key'), isFalse);
  });

  test('JWT profiles require a separately configured password', () {
    expect(
      () => PfSenseApiClient(
        PfSenseProfile(
          id: 'jwt-without-password',
          name: 'JWT without password',
          host: 'firewall.example.test',
          username: 'local-admin',
          authMode: PfSenseAuthMode.jwtPassword,
          apiKey: 'an-api-key-is-not-a-password',
        ),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('explicit username and password'),
        ),
      ),
    );
  });

  test('Basic authorization helper requires both local credentials', () {
    expect(
      _decodeBasic(buildBasicAuthorization(' local-admin ', 'password')),
      'local-admin:password',
    );
    expect(
      () => buildBasicAuthorization('', 'password'),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => buildBasicAuthorization('local-admin', ''),
      throwsA(isA<ApiException>()),
    );
  });
}

String _decodeBasic(dynamic header) {
  final value = header?.toString() ?? '';
  expect(value, startsWith('Basic '));
  return utf8.decode(base64Decode(value.substring('Basic '.length)));
}

class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path == '/api/v2/auth/jwt') {
      return ResponseBody.fromString(
        jsonEncode({
          'data': {'token': 'issued-token'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'data': <String, dynamic>{},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
