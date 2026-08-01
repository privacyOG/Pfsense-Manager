import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  test('JWT read request refreshes once after an unauthorized response',
      () async {
    final adapter = _JwtRefreshAdapter(failFirstRead: true);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = PfSenseApiClient(_jwtProfile(), dio: dio);
    addTearDown(client.dispose);

    final response = await client.get('/api/v2/status/system');

    expect(response.statusCode, 200);
    expect(adapter.loginCount, 2);
    expect(adapter.readCount, 2);
    expect(
      adapter.authorizationHeaders,
      containsAllInOrder([
        'Basic bG9jYWwtYWRtaW46bG9jYWwtcGFzc3dvcmQ=',
        'Bearer issued-token-1',
        'Basic bG9jYWwtYWRtaW46bG9jYWwtcGFzc3dvcmQ=',
        'Bearer issued-token-2',
      ]),
    );
  });

  test('JWT write request is not automatically replayed after 401', () async {
    final adapter = _JwtRefreshAdapter(failWrites: true);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = PfSenseApiClient(_jwtProfile(), dio: dio);
    addTearDown(client.dispose);

    await expectLater(
      client.post('/api/v2/system/test', data: {'enabled': true}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('verify the firewall state before retrying'),
        ),
      ),
    );

    expect(adapter.loginCount, 1);
    expect(adapter.writeCount, 1);
  });
}

PfSenseProfile _jwtProfile() {
  return PfSenseProfile(
    id: 'jwt-refresh',
    name: 'JWT refresh',
    host: 'firewall.example.test',
    username: 'local-admin',
    authMode: PfSenseAuthMode.jwtPassword,
    password: 'local-password',
  );
}

class _JwtRefreshAdapter implements HttpClientAdapter {
  _JwtRefreshAdapter({
    this.failFirstRead = false,
    this.failWrites = false,
  });

  final bool failFirstRead;
  final bool failWrites;
  final List<String> authorizationHeaders = [];
  int loginCount = 0;
  int readCount = 0;
  int writeCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final authorization = options.headers['Authorization']?.toString();
    if (authorization != null) authorizationHeaders.add(authorization);

    if (options.path == '/api/v2/auth/jwt') {
      loginCount++;
      return _jsonResponse({
        'data': {'token': 'issued-token-$loginCount'},
      });
    }

    if (options.method == 'GET') {
      readCount++;
      if (failFirstRead && readCount == 1) {
        return _jsonResponse({'message': 'expired'}, statusCode: 401);
      }
      return _jsonResponse({'data': <String, dynamic>{}});
    }

    writeCount++;
    if (failWrites) {
      return _jsonResponse({'message': 'expired'}, statusCode: 401);
    }
    return _jsonResponse({'data': <String, dynamic>{}});
  }

  ResponseBody _jsonResponse(
    Map<String, dynamic> value, {
    int statusCode = 200,
  }) {
    return ResponseBody.fromString(
      jsonEncode(value),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
