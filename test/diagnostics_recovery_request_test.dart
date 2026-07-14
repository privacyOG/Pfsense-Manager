import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/diagnostics_recovery.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/diagnostics_recovery_service.dart';
import 'package:pfsense_manager/services/pfrest_capability_service.dart';

void main() {
  late _DiagnosticsApiClient client;
  late PfRestCapabilityService capabilityService;
  late DiagnosticsRecoveryService service;

  setUp(() async {
    client = _DiagnosticsApiClient();
    capabilityService = PfRestCapabilityService(
      client,
      profileId: 'diagnostics-request-test',
    );
    service = DiagnosticsRecoveryService(
      client,
      capabilityService: capabilityService,
    );
    await capabilityService.refresh();
    client.requests.clear();
  });

  tearDown(() {
    capabilityService.dispose();
    client.dispose();
  });

  test('ARP reads and deletes use exact stock endpoints', () async {
    final entries = await service.listArpEntries();
    await service.deleteArpEntry(entries.single);
    await service.clearArpTable();

    expect(client.requests[0].method, 'GET');
    expect(client.requests[0].path, '/api/v2/diagnostics/arp_table');
    expect(client.requests[1].method, 'DELETE');
    expect(
      client.requests[1].path,
      '/api/v2/diagnostics/arp_table/entry',
    );
    expect(client.requests[1].queryParameters, {'id': 3});
    expect(client.requests[2].method, 'DELETE');
    expect(client.requests[2].path, '/api/v2/diagnostics/arp_table');
  });

  test('pf tables and configuration history preserve exact identifiers',
      () async {
    final tables = await service.listPfTables();
    await service.flushPfTable(tables.single);
    final revisions = await service.listConfigRevisions();
    await service.deleteConfigRevision(revisions.single);

    expect(client.requests[0].path, '/api/v2/diagnostics/tables');
    expect(client.requests[1].path, '/api/v2/diagnostics/table');
    expect(client.requests[1].queryParameters, {'id': 'blocked_hosts'});
    expect(
      client.requests[2].path,
      '/api/v2/diagnostics/config_history/revisions',
    );
    expect(
      client.requests[3].path,
      '/api/v2/diagnostics/config_history/revision',
    );
    expect(client.requests[3].queryParameters, {'id': 7});
  });

  test('halt and unlocked command prompt use exact POST endpoints', () async {
    await service.haltSystem();
    final result = await service.runCommand(
      'echo test',
      explicitlyUnlocked: true,
    );

    expect(client.requests[0].method, 'POST');
    expect(client.requests[0].path, '/api/v2/diagnostics/halt_system');
    expect(client.requests[1].method, 'POST');
    expect(client.requests[1].path, '/api/v2/diagnostics/command_prompt');
    expect(client.requests[1].data, {'command': 'echo test'});
    expect(result.resultCode, 0);
    expect(result.output, isNot(contains('test-password')));
    expect(result.output, isNot(contains('header-secret')));
    expect(result.output, contains('[REDACTED]'));
  });

  test('locked command prompt rejects before any network request', () async {
    await expectLater(
      service.runCommand('id', explicitlyUnlocked: false),
      throwsA(isA<StateError>()),
    );
    expect(client.requests, isEmpty);
  });

  test('rollback is absent for stock history and dispatched only when reported',
      () async {
    final revision = ConfigHistoryRevision(const {
      'id': 7,
      'time': 1760000000,
      'description': 'Before change',
    });
    expect(service.capabilities.canRollback, isFalse);
    await expectLater(
      service.rollbackConfigRevision(revision),
      throwsA(anything),
    );

    final rollbackClient = _DiagnosticsApiClient(includeRollback: true);
    final rollbackCapabilities = PfRestCapabilityService(
      rollbackClient,
      profileId: 'diagnostics-rollback-test',
    );
    final rollbackService = DiagnosticsRecoveryService(
      rollbackClient,
      capabilityService: rollbackCapabilities,
    );
    addTearDown(() {
      rollbackCapabilities.dispose();
      rollbackClient.dispose();
    });
    await rollbackCapabilities.refresh();
    rollbackClient.requests.clear();

    await rollbackService.rollbackConfigRevision(revision);

    expect(rollbackClient.requests.single.method, 'POST');
    expect(
      rollbackClient.requests.single.path,
      '/api/v2/diagnostics/config_history/revision/restore',
    );
    expect(rollbackClient.requests.single.data, {'id': 7});
  });

  test('read-only OpenAPI profiles expose no mutating operations', () async {
    final readOnlyClient = _DiagnosticsApiClient(readOnly: true);
    final readOnlyCapabilities = PfRestCapabilityService(
      readOnlyClient,
      profileId: 'diagnostics-read-only-test',
    );
    final readOnlyService = DiagnosticsRecoveryService(
      readOnlyClient,
      capabilityService: readOnlyCapabilities,
    );
    addTearDown(() {
      readOnlyCapabilities.dispose();
      readOnlyClient.dispose();
    });
    await readOnlyCapabilities.refresh();

    expect(readOnlyService.capabilities.canReadArp, isTrue);
    expect(readOnlyService.capabilities.canReadTables, isTrue);
    expect(readOnlyService.capabilities.canReadHistory, isTrue);
    expect(readOnlyService.capabilities.canMutateArp, isFalse);
    expect(readOnlyService.capabilities.canFlushTables, isFalse);
    expect(readOnlyService.capabilities.canDeleteRevision, isFalse);
    expect(readOnlyService.capabilities.canHalt, isFalse);
    expect(readOnlyService.capabilities.canRunCommands, isFalse);
  });
}

class _DiagnosticsApiClient extends PfSenseApiClient {
  _DiagnosticsApiClient({
    this.readOnly = false,
    this.includeRollback = false,
  }) : super(
          PfSenseProfile(
            id: 'diagnostics-request-test',
            name: 'Diagnostics request test',
            host: 'firewall.example.test',
            username: 'admin',
            authMode: PfSenseAuthMode.jwtPassword,
            password: 'test-password',
          ),
        );

  final bool readOnly;
  final bool includeRollback;
  final List<_Request> requests = [];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(_Request('GET', path, queryParameters: queryParameters));
    if (path == pfRestOpenApiSchemaPath) {
      return _response(path, _schema(
        readOnly: readOnly,
        includeRollback: includeRollback,
      ));
    }
    if (path == '/api/v2/diagnostics/arp_table') {
      return _response(path, {
        'data': [
          {
            'id': 3,
            'ip-address': '192.168.1.20',
            'mac-address': '00:11:22:33:44:55',
            'hostname': 'switch.local',
            'interface': 'lan',
          },
        ],
      });
    }
    if (path == '/api/v2/diagnostics/tables') {
      return _response(path, {
        'data': [
          {
            'name': 'blocked_hosts',
            'entries': ['192.0.2.10'],
          },
        ],
      });
    }
    if (path == '/api/v2/diagnostics/config_history/revisions') {
      return _response(path, {
        'data': [
          {
            'id': 7,
            'time': 1760000000,
            'description': 'Before change',
            'version': '2.8.0',
            'filesize': 4096,
          },
        ],
      });
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    requests.add(_Request('POST', path, data: data));
    if (path == '/api/v2/diagnostics/command_prompt') {
      return _response(path, {
        'data': {
          'output':
              'password=test-password\nX-API-Key: header-secret\ncommand completed',
          'result_code': 0,
        },
      });
    }
    return _response(path, {'data': data ?? true});
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    requests.add(_Request('PATCH', path, data: data));
    return _response(path, {'data': data ?? true});
  }

  @override
  Future<Response<dynamic>> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(_Request('DELETE', path, queryParameters: queryParameters));
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

Map<String, dynamic> _schema({
  required bool readOnly,
  required bool includeRollback,
}) {
  return {
    'data': {
      'openapi': '3.0.3',
      'paths': {
        '/api/v2/diagnostics/arp_table': {
          'get': _operation(),
          if (!readOnly) 'delete': _operation(),
        },
        if (!readOnly)
          '/api/v2/diagnostics/arp_table/entry': {
            'delete': _operation(idQuery: true),
          },
        '/api/v2/diagnostics/tables': {'get': _operation()},
        '/api/v2/diagnostics/table': {
          'get': _operation(idQuery: true),
          if (!readOnly) 'delete': _operation(idQuery: true),
        },
        '/api/v2/diagnostics/config_history/revisions': {
          'get': _operation(),
        },
        '/api/v2/diagnostics/config_history/revision': {
          'get': _operation(idQuery: true),
          if (!readOnly) 'delete': _operation(idQuery: true),
        },
        if (!readOnly && includeRollback)
          '/api/v2/diagnostics/config_history/revision/restore': {
            'post': _operation(
              fields: const {'id': 0},
              requiredFields: const ['id'],
            ),
          },
        if (!readOnly)
          '/api/v2/diagnostics/halt_system': {'post': _operation()},
        if (!readOnly)
          '/api/v2/diagnostics/command_prompt': {
            'post': _operation(
              fields: const {'command': ''},
              requiredFields: const ['command'],
            ),
          },
      },
    },
  };
}

Map<String, dynamic> _operation({
  bool idQuery = false,
  Map<String, dynamic>? fields,
  List<String> requiredFields = const [],
}) {
  return {
    'tags': ['DIAGNOSTICS'],
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
                  entry.key: _property(entry.value),
              },
            },
          },
        },
      },
  };
}

Map<String, dynamic> _property(Object? value) {
  if (value is int) return {'type': 'integer'};
  return {'type': 'string'};
}