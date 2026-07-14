import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dhcp_management.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/dhcp_management_service.dart';
import 'package:pfsense_manager/services/pfrest_capability_service.dart';

void main() {
  late _DhcpApiClient client;
  late PfRestCapabilityService capabilityService;
  late DhcpManagementService service;

  setUp(() async {
    client = _DhcpApiClient();
    capabilityService = PfRestCapabilityService(
      client,
      profileId: 'dhcp-request-test',
    );
    service = DhcpManagementService(
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

  test('lists DHCP resources from exact plural endpoints', () async {
    for (final kind in DhcpResourceKind.values) {
      client.requests.clear();
      final resources = await service.list(kind);

      expect(client.requests.single.method, 'GET');
      expect(client.requests.single.path, kind.collectionPath);
      expect(resources.single.kind, kind);
    }
  });

  test('server writes preserve schema fields and require explicit apply', () async {
    final server = ManagedDhcpResource(
      kind: DhcpResourceKind.server,
      raw: _serverData,
    );
    await service.update(server, const {'domain': 'internal.test'});

    expect(client.requests.single.method, 'PATCH');
    expect(client.requests.single.path, DhcpResourceKind.server.itemPath);
    expect(client.requests.single.data, containsPair('id', 'lan'));
    expect(client.requests.single.data, containsPair('domain', 'internal.test'));
    expect(
      client.requests.single.data,
      containsPair('future_setting', 'preserve-me'),
    );

    client.requests.clear();
    await service.apply();
    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, dhcpApplyPath);
  });

  test('child writes send parent and resource identifiers in the body', () async {
    await service.create(
      DhcpResourceKind.staticMapping,
      const {
        'parent_id': 'lan',
        'mac': '11:22:33:44:55:66',
        'ipaddr': '192.168.1.150',
      },
    );
    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, DhcpResourceKind.staticMapping.itemPath);
    expect(client.requests.single.data, containsPair('parent_id', 'lan'));

    client.requests.clear();
    final mapping = ManagedDhcpResource(
      kind: DhcpResourceKind.staticMapping,
      raw: _mappingData,
    );
    await service.update(mapping, const {'hostname': 'printer'});
    expect(client.requests.single.method, 'PATCH');
    expect(client.requests.single.data, containsPair('id', 4));
    expect(client.requests.single.data, containsPair('parent_id', 'lan'));
    expect(client.requests.single.data, containsPair('hostname', 'printer'));
  });

  test('child deletes send parent and resource identifiers as query values', () async {
    final mapping = ManagedDhcpResource(
      kind: DhcpResourceKind.staticMapping,
      raw: _mappingData,
    );
    await service.delete(mapping);

    expect(client.requests.single.method, 'DELETE');
    expect(client.requests.single.path, DhcpResourceKind.staticMapping.itemPath);
    expect(client.requests.single.queryParameters, {
      'parent_id': 'lan',
      'id': '4',
    });
  });

  test('relay and backend changes use immediate dedicated endpoints', () async {
    final relay = await service.getRelay();
    expect(client.requests.single.path, dhcpRelayPath);
    expect(relay.enabled, isFalse);

    client.requests.clear();
    await service.updateRelay(
      relay,
      const {
        'enable': true,
        'interface': ['lan'],
        'server': ['192.0.2.2'],
      },
    );
    expect(client.requests.single.method, 'PATCH');
    expect(client.requests.single.path, dhcpRelayPath);

    client.requests.clear();
    await service.switchBackend('kea');
    expect(client.requests.single.method, 'PATCH');
    expect(client.requests.single.path, dhcpBackendPath);
    expect(client.requests.single.data, {'dhcpbackend': 'kea'});
  });

  test('pending status and apply use the DHCP apply endpoint', () async {
    expect(await service.hasPendingChanges(), isTrue);
    expect(client.requests.single.method, 'GET');
    expect(client.requests.single.path, dhcpApplyPath);

    client.requests.clear();
    await service.apply();
    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, dhcpApplyPath);
  });

  test('read-only schema exposes collections and disables writes', () async {
    final readOnlyClient = _DhcpApiClient(readOnly: true);
    final readOnlyCapabilities = PfRestCapabilityService(
      readOnlyClient,
      profileId: 'dhcp-read-only',
    );
    final readOnlyService = DhcpManagementService(
      readOnlyClient,
      capabilityService: readOnlyCapabilities,
    );
    addTearDown(() {
      readOnlyCapabilities.dispose();
      readOnlyClient.dispose();
    });
    await readOnlyCapabilities.refresh();

    expect(
      readOnlyService.capabilities.readableKinds,
      DhcpResourceKind.values,
    );
    expect(readOnlyService.capabilities.canApply, isFalse);
    expect(readOnlyService.capabilities.canUpdateRelay, isFalse);
    expect(readOnlyService.capabilities.canSwitchBackend, isFalse);
    expect(
      readOnlyService.capabilities.resources.values.every(
        (capability) =>
            !capability.canCreate &&
            !capability.canUpdate &&
            !capability.canDelete,
      ),
      isTrue,
    );
    expect(await readOnlyService.list(DhcpResourceKind.server), isNotEmpty);
  });
}

class _DhcpApiClient extends PfSenseApiClient {
  _DhcpApiClient({this.readOnly = false})
      : super(
          PfSenseProfile(
            id: 'dhcp-request-test',
            name: 'DHCP request test',
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
    if (path == DhcpResourceKind.server.collectionPath) {
      return _response(path, {
        'data': [_serverData],
      });
    }
    if (path == DhcpResourceKind.staticMapping.collectionPath) {
      return _response(path, {
        'data': [_mappingData],
      });
    }
    if (path == DhcpResourceKind.addressPool.collectionPath) {
      return _response(path, {
        'data': [_poolData],
      });
    }
    if (path == dhcpRelayPath) {
      return _response(path, {
        'data': {
          'enable': false,
          'interface': <String>[],
          'server': <String>[],
          'agentoption': false,
          'carpstatusvip': 'none',
        },
      });
    }
    if (path == dhcpApplyPath) {
      return _response(path, {
        'data': {'pending': true},
      });
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    requests.add(_Request('POST', path, data: data));
    if (path == dhcpApplyPath) return _response(path, {'data': true});
    if (DhcpResourceKind.values.any((kind) => kind.itemPath == path)) {
      return _response(path, {'data': data});
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    requests.add(_Request('PATCH', path, data: data));
    if (path == dhcpRelayPath || path == dhcpBackendPath) {
      return _response(path, {'data': data});
    }
    if (DhcpResourceKind.values.any((kind) => kind.itemPath == path)) {
      return _response(path, {'data': data});
    }
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
    dhcpRelayPath: {
      'get': _operation(),
      if (!readOnly)
        'patch': _operation(
          fields: const {
            'enable': false,
            'interface': <String>[],
            'agentoption': false,
            'carpstatusvip': 'none',
            'server': <String>[],
          },
          requiredFields: const ['server'],
        ),
    },
    dhcpBackendPath: {
      if (!readOnly)
        'patch': _operation(
          fields: const {'dhcpbackend': 'isc'},
          requiredFields: const ['dhcpbackend'],
          enums: const {
            'dhcpbackend': ['isc', 'kea'],
          },
        ),
    },
    dhcpApplyPath: {
      'get': _operation(),
      if (!readOnly) 'post': _operation(),
    },
  };
  for (final kind in DhcpResourceKind.values) {
    paths[kind.collectionPath] = {'get': _operation()};
    paths[kind.itemPath] = {
      'get': _operation(queryIdentifiers: kind != DhcpResourceKind.server),
      if (!readOnly)
        'post': _operation(
          fields: _writableData(kind, create: true),
          requiredFields: _requiredFields(kind, create: true),
        ),
      if (!readOnly)
        'patch': _operation(
          fields: _writableData(kind),
          requiredFields: _requiredFields(kind),
        ),
      if (!readOnly)
        'delete': _operation(
          queryIdentifiers: true,
          child: kind != DhcpResourceKind.server,
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
  Map<String, dynamic>? fields,
  List<String> requiredFields = const [],
  Map<String, List<String>> enums = const {},
  bool queryIdentifiers = false,
  bool child = false,
}) {
  return {
    'tags': ['SERVICES'],
    if (queryIdentifiers)
      'parameters': [
        if (child)
          {
            'name': 'parent_id',
            'in': 'query',
            'required': true,
            'schema': {'type': 'string'},
          },
        {
          'name': 'id',
          'in': 'query',
          'required': true,
          'schema': {'type': 'integer'},
        },
      ],
    if (fields != null)
      'requestBody': {
        'required': true,
        'content': {
          'application/json': {
            'schema': {
              'type': 'object',
              'required': requiredFields,
              'properties': {
                for (final entry in fields.entries)
                  entry.key: {
                    ..._property(entry.value),
                    if (enums.containsKey(entry.key))
                      'enum': enums[entry.key],
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
  if (value is List) {
    return {
      'type': 'array',
      'items': {'type': 'string'},
    };
  }
  return {'type': 'string'};
}

List<String> _requiredFields(
  DhcpResourceKind kind, {
  bool create = false,
}) {
  return switch (kind) {
    DhcpResourceKind.server => const ['id'],
    DhcpResourceKind.staticMapping => create
        ? const ['parent_id', 'mac']
        : const ['parent_id', 'id'],
    DhcpResourceKind.addressPool => create
        ? const ['parent_id', 'range_from', 'range_to']
        : const ['parent_id', 'id'],
  };
}

Map<String, dynamic> _writableData(
  DhcpResourceKind kind, {
  bool create = false,
}) {
  final data = Map<String, dynamic>.from(
    switch (kind) {
      DhcpResourceKind.server => _serverData,
      DhcpResourceKind.staticMapping => _mappingData,
      DhcpResourceKind.addressPool => _poolData,
    },
  );
  data.remove('runtime_status');
  if (create && kind != DhcpResourceKind.server) data.remove('id');
  return data;
}

const _serverData = <String, dynamic>{
  'id': 'lan',
  'interface': 'lan',
  'enable': true,
  'range_from': '192.168.1.10',
  'range_to': '192.168.1.100',
  'domain': 'example.test',
  'dnsserver': ['1.1.1.1'],
  'defaultleasetime': 7200,
  'maxleasetime': 86400,
  'future_setting': 'preserve-me',
  'runtime_status': 'running',
};

const _mappingData = <String, dynamic>{
  'id': 4,
  'parent_id': 'lan',
  'mac': '11:22:33:44:55:66',
  'ipaddr': '192.168.1.150',
  'hostname': 'client',
  'descr': 'Client mapping',
};

const _poolData = <String, dynamic>{
  'id': 2,
  'parent_id': 'lan',
  'range_from': '192.168.1.180',
  'range_to': '192.168.1.190',
  'domain': 'pool.example.test',
};
