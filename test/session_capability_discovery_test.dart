import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/providers/session_provider.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfrest_capability_service.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  test('session loads capabilities after a successful connection check',
      () async {
    final client = _SessionCapabilityClient(
      _profile('profile-a'),
      schemaResult: _schemaResponse(
        version: '2.4.3',
        paths: {
          '/api/v2/status/system': {'get': <String, dynamic>{}},
          '/api/v2/diagnostics/ping': {'post': <String, dynamic>{}},
        },
      ),
    );
    final session = _sessionWithFactory((_) => client);
    addTearDown(session.dispose);

    await session.connect(_profile('profile-a'));

    expect(session.connected, isTrue);
    expect(session.connectionError, isNull);
    expect(session.capabilityService, isNotNull);
    expect(session.capabilities?.isAvailable, isTrue);
    expect(session.capabilities?.profileId, 'profile-a');
    expect(session.capabilities?.apiVersion, '2.4.3');
    expect(
      session.capabilities?.supports('/api/v2/diagnostics/ping', 'POST'),
      isTrue,
    );
    expect(client.schemaCalls, 1);
  });

  test('schema permission failure keeps the session connected and limited',
      () async {
    final client = _SessionCapabilityClient(
      _profile('restricted'),
      schemaResult: const ApiException('Schema privilege required', 403),
    );
    final session = _sessionWithFactory((_) => client);
    addTearDown(session.dispose);

    await session.connect(_profile('restricted'));

    expect(session.connected, isTrue);
    expect(session.service, isNotNull);
    expect(session.connectionError, isNull);
    expect(session.capabilities?.isLimited, isTrue);
    expect(
      session.capabilities?.issue,
      PfRestCapabilityIssue.permissionDenied,
    );
    expect(session.connectionNotice, contains('OpenAPI schema (403)'));
    expect(session.connectionNotice, contains('Basic features remain available'));
  });

  test('switching profiles clears the previous capability snapshot', () async {
    final firstClient = _SessionCapabilityClient(
      _profile('profile-a'),
      schemaResult: _schemaResponse(
        version: '2.4.3',
        paths: {
          '/api/v2/status/system': {'get': <String, dynamic>{}},
        },
      ),
    );
    final secondClient = _SessionCapabilityClient(
      _profile('profile-b'),
      schemaResult: _schemaResponse(
        version: '2.5.0',
        paths: {
          '/api/v2/status/interfaces': {'get': <String, dynamic>{}},
        },
      ),
    );
    final clients = <String, _SessionCapabilityClient>{
      'profile-a': firstClient,
      'profile-b': secondClient,
    };
    final session = _sessionWithFactory((profile) => clients[profile.id]!);
    addTearDown(session.dispose);

    await session.connect(_profile('profile-a'));
    final firstFingerprint = session.capabilities?.schemaFingerprint;
    expect(session.capabilities?.profileId, 'profile-a');
    expect(
      session.capabilities?.supports('/api/v2/status/system', 'GET'),
      isTrue,
    );

    await session.connect(_profile('profile-b'));

    expect(firstClient.closed, isTrue);
    expect(session.capabilities?.profileId, 'profile-b');
    expect(session.capabilities?.apiVersion, '2.5.0');
    expect(session.capabilities?.schemaFingerprint, isNot(firstFingerprint));
    expect(
      session.capabilities?.supports('/api/v2/status/system', 'GET'),
      isFalse,
    );
    expect(
      session.capabilities?.supports('/api/v2/status/interfaces', 'GET'),
      isTrue,
    );
  });

  test('manual refresh replaces the active session snapshot', () async {
    final client = _SessionCapabilityClient(
      _profile('profile-a'),
      schemaResult: _schemaResponse(
        version: '2.4.3',
        paths: {
          '/api/v2/status/system': {'get': <String, dynamic>{}},
        },
      ),
      laterSchemaResults: [
        _schemaResponse(
          version: '2.4.4',
          paths: {
            '/api/v2/status/system': {'get': <String, dynamic>{}},
            '/api/v2/status/services': {'get': <String, dynamic>{}},
          },
        ),
      ],
    );
    final session = _sessionWithFactory((_) => client);
    addTearDown(session.dispose);

    await session.connect(_profile('profile-a'));
    final refreshed = await session.refreshCapabilities();

    expect(refreshed?.apiVersion, '2.4.4');
    expect(session.capabilities?.apiVersion, '2.4.4');
    expect(
      session.capabilities?.supports('/api/v2/status/services', 'GET'),
      isTrue,
    );
    expect(client.schemaCalls, 2);
  });
}

PfSenseSessionProvider _sessionWithFactory(
  PfSenseApiClient Function(PfSenseProfile profile) factory,
) {
  return PfSenseSessionProvider(
    profileResolver: (profile) async => profile,
    apiClientFactory: factory,
  );
}

PfSenseProfile _profile(String id) {
  return PfSenseProfile(
    id: id,
    name: id,
    host: '$id.example.test',
    username: 'api-user',
    apiKey: 'test-key',
  );
}

Response<dynamic> _schemaResponse({
  required String version,
  required Map<String, dynamic> paths,
}) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: pfRestOpenApiSchemaPath),
    statusCode: 200,
    data: {
      'data': {
        'openapi': '3.0.3',
        'info': {'version': version},
        'paths': paths,
      },
    },
  );
}

class _SessionCapabilityClient extends PfSenseApiClient {
  _SessionCapabilityClient(
    super.profile, {
    required this.schemaResult,
    List<Object> laterSchemaResults = const [],
  }) : _schemaResults = [schemaResult, ...laterSchemaResults];

  final Object schemaResult;
  final List<Object> _schemaResults;
  int schemaCalls = 0;
  bool closed = false;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == pfRestOpenApiSchemaPath) {
      schemaCalls++;
      if (_schemaResults.isEmpty) {
        throw StateError('No schema response queued.');
      }
      final result = _schemaResults.removeAt(0);
      if (result is Error) throw result;
      if (result is Exception) throw result;
      return result as Response<dynamic>;
    }

    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: const {'data': <dynamic>[]},
    );
  }

  @override
  void dispose() {
    if (closed) return;
    closed = true;
    super.dispose();
  }
}
