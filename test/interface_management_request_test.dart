import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/interface_management.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/interface_management_service.dart';
import 'package:pfsense_manager/services/pfrest_capability_service.dart';

void main() {
  late _InterfaceApiClient client;
  late PfRestCapabilityService capabilityService;
  late InterfaceManagementService service;

  setUp(() async {
    client = _InterfaceApiClient();
    capabilityService = PfRestCapabilityService(
      client,
      profileId: 'interface-request-test',
    );
    service = InterfaceManagementService(
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

  test('lists assigned and virtual resources from exact collection paths',
      () async {
    for (final kind in InterfaceResourceKind.values) {
      client.requests.clear();
      final resources = await service.list(kind);

      expect(client.requests.single.method, 'GET');
      expect(client.requests.single.path, kind.collectionPath);
      expect(resources.single.kind, kind);
    }
  });

  test('loads available interface assignments from the reported endpoint',
      () async {
    final available = await service.listAvailableInterfaces();

    expect(client.requests.single.method, 'GET');
    expect(client.requests.single.path, interfaceAvailablePath);
    expect(available.map((item) => item.name), ['igc0', 'igc1', 'igc2']);
  });

  test('assigned interface update preserves unmodified writable settings',
      () async {
    final original = (await service.list(InterfaceResourceKind.assigned)).single;
    client.requests.clear();

    final updated = await service.update(
      original,
      const {'descr': 'Internet uplink'},
    );

    final request = client.requests.single;
    expect(request.method, 'PATCH');
    expect(request.path, '/api/v2/interface');
    expect(request.data, {
      'id': 'wan',
      'if': 'igc0',
      'enable': true,
      'descr': 'Internet uplink',
      'typev4': 'dhcp',
      'ipaddr': 'dhcp',
      'typev6': 'none',
      'ipaddrv6': 'none',
      'mtu': 1500,
      'blockpriv': true,
      'future_setting': 'keep-this',
    });
    expect(updated.description, 'Internet uplink');
    expect(client.requests, hasLength(1));
    expect(client.requests.map((item) => item.path), isNot(contains(interfaceApplyPath)));
  });

  for (final kind in const [
    InterfaceResourceKind.vlan,
    InterfaceResourceKind.bridge,
    InterfaceResourceKind.lagg,
    InterfaceResourceKind.gre,
    InterfaceResourceKind.gif,
  ]) {
    test('${kind.name} create, update and delete use singular endpoints', () async {
      final values = _resourceData(kind);

      await service.create(kind, values);
      expect(client.requests.single.method, 'POST');
      expect(client.requests.single.path, kind.itemPath);
      expect(client.requests.single.data, _writableData(kind));

      client.requests.clear();
      final existing = ManagedInterfaceResource(kind: kind, raw: values);
      await service.update(existing, const {'descr': 'Updated'});
      expect(client.requests.single.method, 'PATCH');
      expect(client.requests.single.path, kind.itemPath);
      expect((client.requests.single.data as Map)['descr'], 'Updated');
      expect((client.requests.single.data as Map)['id'], values['id']);

      client.requests.clear();
      await service.delete(existing);
      expect(client.requests.single.method, 'DELETE');
      expect(client.requests.single.path, kind.itemPath);
      expect(client.requests.single.queryParameters, {
        'id': values['id'].toString(),
      });
    });
  }

  test('apply and pending-status checks use the dedicated apply endpoint',
      () async {
    expect(await service.hasPendingChanges(), isTrue);
    expect(client.requests.single.method, 'GET');
    expect(client.requests.single.path, interfaceApplyPath);

    client.requests.clear();
    await service.apply();
    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, interfaceApplyPath);
    expect(client.requests.single.data, isNull);
  });

  test('read-only schema keeps resources visible and blocks writes', () async {
    final readOnlyClient = _InterfaceApiClient(readOnly: true);
    final readOnlyCapabilities = PfRestCapabilityService(
      readOnlyClient,
      profileId: 'read-only',
    );
    final readOnlyService = InterfaceManagementService(
      readOnlyClient,
      capabilityService: readOnlyCapabilities,
    );
    addTearDown(() {
      readOnlyCapabilities.dispose();
      readOnlyClient.dispose();
    });
    await readOnlyCapabilities.refresh();

    expect(readOnlyService.capabilities.readableKinds, [
      InterfaceResourceKind.assigned,
      InterfaceResourceKind.vlan,
      InterfaceResourceKind.bridge,
      InterfaceResourceKind.lagg,
      InterfaceResourceKind.gre,
      InterfaceResourceKind.gif,
    ]);
    expect(
      readOnlyService.capabilities.resources.values
          .every((capability) => !capability.canCreate && !capability.canUpdate && !capability.canDelete),
      isTrue,
    );
    expect(readOnlyService.capabilities.canApply, isFalse);
    expect(await readOnlyService.list(InterfaceResourceKind.assigned), isNotEmpty);
    await expectLater(
      readOnlyService.create(
        InterfaceResourceKind.vlan,
        _resourceData(InterfaceResourceKind.vlan),
      ),
      throwsA(isA<Exception>()),
    );
  });
}

class _InterfaceApiClient extends PfSenseApiClient {
  _InterfaceApiClient({this.readOnly = false})
      : super(
          PfSenseProfile(
            id: 'interface-request-test',
            name: 'Interface request test',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  final bool readOnly;
  final List<_Request> requests = [];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(_Request('GET', path, queryParameters: queryParameters));
    if (path == pfRestOpenApiSchemaPath) return _response(path, _schema(readOnly));
    if (path == interfaceAvailablePath) {
      return _response(path, {
        'data': [
          {'if': 'igc0', 'descr': 'WAN', 'assigned': true},
          {'if': 'igc1', 'descr': 'LAN', 'assigned': true},
          {'if': 'igc2', 'descr': 'Unused', 'assigned': false},
        ],
      });
    }
    if (path == interfaceApplyPath) {
      return _response(path, {
        'data': {'pending': true},
      });
    }
    final kind = InterfaceResourceKind.values
        .where((candidate) => candidate.collectionPath == path)
        .firstOrNull;
    if (kind != null) {
      return _response(path, {
        'data': [_resourceData(kind)],
      });
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    requests.add(_Request('POST', path, data: data));
    if (path == interfaceApplyPath) return _response(path, {'data': true});
    final kind = InterfaceResourceKind.values
        .where((candidate) => candidate.itemPath == path)
        .firstOrNull;
    if (kind != null) return _response(path, {'data': data});
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    requests.add(_Request('PATCH', path, data: data));
    final kind = InterfaceResourceKind.values
        .where((candidate) => candidate.itemPath == path)
        .firstOrNull;
    if (kind != null) return _response(path, {'data': data});
    throw StateError('Unexpected PATCH $path');
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

Map<String, dynamic> _schema(bool readOnly) {
  final paths = <String, dynamic>{
    interfaceAvailablePath: {'get': _operation()},
    interfaceApplyPath: {
      'get': _operation(),
      if (!readOnly) 'post': _operation(),
    },
  };
  for (final kind in InterfaceResourceKind.values) {
    paths[kind.collectionPath] = {'get': _operation()};
    paths[kind.itemPath] = {
      'get': _operation(),
      if (!readOnly) 'post': _operation(kind: kind),
      if (!readOnly) 'patch': _operation(kind: kind),
      if (!readOnly)
        'delete': _operation(
          queryId: true,
        ),
    };
  }
  return {
    'data': {
      'openapi': '3.0.0',
      'paths': paths,
    },
  };
}

Map<String, dynamic> _operation({
  InterfaceResourceKind? kind,
  bool queryId = false,
}) {
  return {
    'tags': ['INTERFACE'],
    if (queryId)
      'parameters': [
        {
          'name': 'id',
          'in': 'query',
          'required': true,
          'schema': {'type': 'string'},
        },
      ],
    if (kind != null)
      'requestBody': {
        'required': true,
        'content': {
          'application/json': {
            'schema': {
              'type': 'object',
              'properties': {
                for (final entry in _writableData(kind).entries)
                  entry.key: _property(entry.value),
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
  if (value is List) {
    return {
      'type': 'array',
      'items': {'type': 'string'},
    };
  }
  return {'type': 'string'};
}

Map<String, dynamic> _resourceData(InterfaceResourceKind kind) {
  return switch (kind) {
    InterfaceResourceKind.assigned => {
        'id': 'wan',
        'if': 'igc0',
        'enable': true,
        'descr': 'WAN',
        'typev4': 'dhcp',
        'ipaddr': 'dhcp',
        'typev6': 'none',
        'ipaddrv6': 'none',
        'mtu': 1500,
        'blockpriv': true,
        'future_setting': 'keep-this',
        'runtime_status': 'up',
      },
    InterfaceResourceKind.vlan => {
        'id': 20,
        'if': 'igc1',
        'tag': 20,
        'pcp': 0,
        'descr': 'Guests',
      },
    InterfaceResourceKind.bridge => {
        'id': 21,
        'members': ['igc1', 'igc2'],
        'descr': 'LAN bridge',
      },
    InterfaceResourceKind.lagg => {
        'id': 22,
        'members': ['igc2', 'igc3'],
        'laggproto': 'lacp',
        'descr': 'Core LAGG',
      },
    InterfaceResourceKind.gre => {
        'id': 23,
        'if': 'wan',
        'local': '192.0.2.10',
        'remote': '198.51.100.10',
        'descr': 'GRE link',
      },
    InterfaceResourceKind.gif => {
        'id': 24,
        'if': 'wan',
        'local': '2001:db8::1',
        'remote': '2001:db8::2',
        'descr': 'GIF link',
      },
  };
}

Map<String, dynamic> _writableData(InterfaceResourceKind kind) {
  final data = Map<String, dynamic>.from(_resourceData(kind));
  data.remove('runtime_status');
  return data;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
