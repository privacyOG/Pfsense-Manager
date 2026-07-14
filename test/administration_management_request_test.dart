import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/administration_management.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/administration_basic_auth_transport.dart';
import 'package:pfsense_manager/services/administration_management_service.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfrest_capability_service.dart';

void main() {
  late _AdministrationApiClient client;
  late PfRestCapabilityService capabilityService;
  late AdministrationManagementService service;

  setUp(() async {
    client = _AdministrationApiClient();
    capabilityService = PfRestCapabilityService(
      client,
      profileId: 'administration-request-test',
    );
    service = AdministrationManagementService(
      client,
      capabilityService: capabilityService,
      basicAuthTransport: client.basicAuthTransport,
    );
    await capabilityService.refresh();
    client.requests.clear();
  });

  tearDown(() {
    capabilityService.dispose();
    client.dispose();
  });

  test('lists users from the exact reported collection path', () async {
    final users = await service.list(AdministrationResourceKind.users);

    expect(client.requests.single.method, 'GET');
    expect(client.requests.single.path, '/api/v2/users');
    expect(users.single.displayName, 'alice');
    expect(users.single.raw, isNot(contains('password')));
  });

  test('user updates preserve reported fields and omit secrets', () async {
    final user = (await service.list(AdministrationResourceKind.users)).single;
    client.requests.clear();

    await service.update(user, const {'descr': 'Updated account'});

    expect(client.requests.single.method, 'PATCH');
    expect(client.requests.single.path, '/api/v2/user');
    expect(client.requests.single.data, containsPair('id', 1));
    expect(client.requests.single.data, containsPair('descr', 'Updated account'));
    expect(
      client.requests.single.data,
      containsPair('future_setting', 'preserve-me'),
    );
    expect(client.requests.single.data, isNot(contains('password')));
  });

  test('API key creation and revocation use Basic authentication only', () async {
    final created = await service.create(
      AdministrationResourceKind.apiKeys,
      const {'descr': 'Mobile administration'},
    );

    expect(client.requests.single.method, 'POST_BASIC');
    expect(client.requests.single.path, '/api/v2/auth/key');
    expect(created.ephemeralSecret, 'generated-api-key');
    expect(created.safeData, isNot(contains('key')));

    client.requests.clear();
    final key = (await service.list(AdministrationResourceKind.apiKeys)).single;
    client.requests.clear();
    await service.delete(key);

    expect(client.requests.single.method, 'DELETE_BASIC');
    expect(client.requests.single.path, '/api/v2/auth/key');
    expect(client.requests.single.queryParameters, {'id': '9'});
  });

  test('system update action dispatches to the exact POST endpoint', () async {
    final result = await service.runAction(
      AdministrationActionKind.updateSystem,
      const {},
    );

    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, '/api/v2/system/update');
    expect(result.safeData['status'], 'started');
  });

  test('read-only schemas expose resources without write operations', () async {
    final readOnlyClient = _AdministrationApiClient(readOnly: true);
    final readOnlyCapabilities = PfRestCapabilityService(
      readOnlyClient,
      profileId: 'administration-read-only',
    );
    final readOnlyService = AdministrationManagementService(
      readOnlyClient,
      capabilityService: readOnlyCapabilities,
      basicAuthTransport: readOnlyClient.basicAuthTransport,
    );
    addTearDown(() {
      readOnlyCapabilities.dispose();
      readOnlyClient.dispose();
    });
    await readOnlyCapabilities.refresh();

    final capability = readOnlyService.capabilities.forResource(
      AdministrationResourceKind.users,
    );
    expect(capability.canRead, isTrue);
    expect(capability.readOnly, isTrue);
    expect(
      await readOnlyService.list(AdministrationResourceKind.users),
      isNotEmpty,
    );
  });
}

class _AdministrationApiClient extends PfSenseApiClient {
  _AdministrationApiClient({this.readOnly = false})
      : super(
          PfSenseProfile(
            id: 'administration-request-test',
            name: 'Administration request test',
            host: 'firewall.example.test',
            username: 'admin',
            authMode: PfSenseAuthMode.jwtPassword,
            password: 'test-password',
          ),
        );

  final bool readOnly;
  final List<_Request> requests = [];

  AdministrationBasicAuthTransport get basicAuthTransport =>
      _FakeBasicAuthTransport(requests);

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(_Request('GET', path, queryParameters: queryParameters));
    if (path == pfRestOpenApiSchemaPath) {
      return _response(path, _schema(readOnly));
    }
    if (path == '/api/v2/users') {
      return _response(path, {
        'data': [
          {
            'id': 1,
            'username': 'alice',
            'descr': 'Administrator',
            'password': 'must-not-return',
            'future_setting': 'preserve-me',
          },
        ],
      });
    }
    if (path == '/api/v2/auth/keys') {
      return _response(path, {
        'data': [
          {'id': 9, 'descr': 'Mobile key'},
        ],
      });
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    requests.add(_Request('POST', path, data: data));
    if (path == '/api/v2/system/update') {
      return _response(path, {
        'data': {'status': 'started'},
      });
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    requests.add(_Request('PATCH', path, data: data));
    if (path == '/api/v2/user') return _response(path, {'data': data});
    throw StateError('Unexpected PATCH $path');
  }
}

class _FakeBasicAuthTransport implements AdministrationBasicAuthTransport {
  const _FakeBasicAuthTransport(this.requests);

  final List<_Request> requests;

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    requests.add(_Request('POST_BASIC', path, data: data));
    return _response(path, {
      'data': {
        'id': 9,
        'descr': data['descr'],
        'key': 'generated-api-key',
      },
    });
  }

  @override
  Future<Response<dynamic>> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(
      _Request('DELETE_BASIC', path, queryParameters: queryParameters),
    );
    return _response(path, {'data': true});
  }
}

class _Request {
  const _Request(
    this.method,
    this.path, {
    this.data,
    this.queryParameters,
  });

  final String method;
  final String path;
  final dynamic data;
  final Map<String, dynamic>? queryParameters;
}

Response<dynamic> _response(String path, dynamic data) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: data,
  );
}

Map<String, dynamic> _schema(bool readOnly) {
  final paths = <String, dynamic>{
    '/api/v2/users': {'get': _operation()},
    '/api/v2/user': {
      'get': _operation(idQuery: true),
      if (!readOnly)
        'post': _operation(
          fields: _userFields,
          requiredFields: const ['username', 'password'],
          secretFields: const ['password'],
        ),
      if (!readOnly)
        'patch': _operation(
          fields: _userFields,
          requiredFields: const ['id'],
          secretFields: const ['password'],
        ),
      if (!readOnly) 'delete': _operation(idQuery: true),
    },
    if (!readOnly) ...{
      '/api/v2/auth/keys': {'get': _operation()},
      '/api/v2/auth/key': {
        'post': _operation(
          fields: const {'descr': ''},
          requiredFields: const ['descr'],
        ),
        'delete': _operation(idQuery: true),
      },
      '/api/v2/system/update': {'post': _operation()},
    },
  };
  return {
    'data': {
      'openapi': '3.0.3',
      'paths': paths,
    },
  };
}

Map<String, dynamic> _operation({
  Map<String, dynamic>? fields,
  List<String> requiredFields = const [],
  List<String> secretFields = const [],
  bool idQuery = false,
}) {
  return {
    'tags': ['SYSTEM'],
    if (idQuery)
      'parameters': [
        {
          'name': 'id',
          'in': 'query',
          'required': true,
          'schema': {'type': 'integer'},
        },
      ],
    if (fields != null)
      'requestBody': {
        'content': {
          'application/json': {
            'schema': {
              'type': 'object',
              'required': requiredFields,
              'properties': {
                for (final entry in fields.entries)
                  entry.key: {
                    ..._property(entry.value),
                    if (secretFields.contains(entry.key)) 'writeOnly': true,
                  },
              },
            },
          },
        },
      },
  };
}

Map<String, dynamic> _property(Object? value) {
  if (value is bool) return {'type': 'boolean'};
  if (value is int) return {'type': 'integer'};
  if (value is List) return {'type': 'array', 'items': {'type': 'string'}};
  return {'type': 'string'};
}

const _userFields = <String, dynamic>{
  'id': 1,
  'username': '',
  'descr': '',
  'password': '',
  'future_setting': '',
};