import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/models/system_log_source.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfsense_service.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  test('discovers sources from the documented OpenAPI schema endpoint', () async {
    final client = _SystemLogApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);

    final sources = await service.getSystemLogSources();

    expect(client.requests.single.path, systemLogSchemaPath);
    expect(client.requests.single.queryParameters, isNull);
    expect(sources.map((source) => source.id), [
      'system',
      'authentication',
      'openvpn',
      'restapi',
    ]);
    expect(sources.map((source) => source.id), isNot(contains('resolver')));
    expect(sources.map((source) => source.id), isNot(contains('gateways')));
  });

  test('requests the exact path supplied by the discovered source', () async {
    final client = _SystemLogApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);
    final source = (await service.getSystemLogSources())
        .singleWhere((item) => item.id == 'authentication');
    client.requests.clear();

    final entries = await service.getSystemLog(source, limit: 75);

    expect(client.requests.single.path, '/custom/status/logs/authentication');
    expect(client.requests.single.queryParameters, {'limit': '75'});
    expect(entries.single.process, 'sshd');
    expect(entries.single.message, contains('Accepted publickey'));
  });

  test('schema permission errors are not converted to an empty source list',
      () async {
    final client = _SystemLogApiClient(schemaError: const ApiException(
      'OpenAPI schema read privilege required',
      403,
    ));
    final service = PfSenseService(client);
    addTearDown(service.dispose);

    await expectLater(
      service.getSystemLogSources(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having(
              (error) => error.message,
              'message',
              'OpenAPI schema read privilege required',
            ),
      ),
    );
  });
}

class _SystemLogApiClient extends PfSenseApiClient {
  _SystemLogApiClient({this.schemaError})
      : super(
          PfSenseProfile(
            id: 'system-log-test',
            name: 'System log test',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  final Object? schemaError;
  final List<_RecordedRequest> requests = [];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(
      _RecordedRequest(
        path: path,
        queryParameters: queryParameters == null
            ? null
            : Map<String, dynamic>.from(queryParameters),
      ),
    );

    if (path == systemLogSchemaPath) {
      final error = schemaError;
      if (error is Error) throw error;
      if (error is Exception) throw error;
      return Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'openapi': '3.0.0',
            'paths': <String, dynamic>{
              '/api/v2/status/logs/system': {
                'get': <String, dynamic>{},
              },
              '/custom/status/logs/authentication': {
                'get': <String, dynamic>{},
              },
              '/api/v2/status/logs/openvpn': {
                'get': <String, dynamic>{},
              },
              '/api/v2/status/logs/rest_api': {
                'get': <String, dynamic>{},
              },
              '/api/v2/status/logs/resolver': {
                'post': <String, dynamic>{},
              },
            },
          },
        },
      );
    }

    if (path == '/custom/status/logs/authentication') {
      return Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: <String, dynamic>{
          'data': <Map<String, dynamic>>[
            {
              'text':
                  'Jul 12 08:15:01 firewall sshd[1234]: Accepted publickey for admin',
            },
          ],
        },
      );
    }

    throw StateError('Unexpected request path: $path');
  }
}

class _RecordedRequest {
  const _RecordedRequest({required this.path, this.queryParameters});

  final String path;
  final Map<String, dynamic>? queryParameters;
}
