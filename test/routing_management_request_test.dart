import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/models/routing_management.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfrest_capability_service.dart';
import 'package:pfsense_manager/services/routing_management_service.dart';

void main() {
  late _RoutingApiClient client;
  late PfRestCapabilityService capabilityService;
  late RoutingManagementService service;

  setUp(() async {
    client = _RoutingApiClient();
    capabilityService = PfRestCapabilityService(
      client,
      profileId: 'routing-request-test',
    );
    service = RoutingManagementService(
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

  test('lists routing resources from exact plural endpoints', () async {
    for (final kind in RoutingResourceKind.values) {
      client.requests.clear();
      final resources = await service.list(kind);

      expect(client.requests.single.method, 'GET');
      expect(client.requests.single.path, kind.collectionPath);
      expect(resources.single.kind, kind);
    }
  });

  test('gateway create update and delete use the singular endpoint', () async {
    await service.create(RoutingResourceKind.gateway, _gatewayData);
    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, RoutingResourceKind.gateway.itemPath);
    expect(client.requests.single.data, isNot(contains('runtime_status')));

    client.requests.clear();
    final existing = ManagedRoutingResource(
      kind: RoutingResourceKind.gateway,
      raw: _gatewayData,
    );
    await service.update(existing, const {'descr': 'Internet uplink'});
    final update = client.requests.single;
    expect(update.method, 'PATCH');
    expect(update.path, RoutingResourceKind.gateway.itemPath);
    expect(update.data, containsPair('id', 0));
    expect(update.data, containsPair('descr', 'Internet uplink'));
    expect(update.data, containsPair('future_setting', 'preserve-me'));

    client.requests.clear();
    await service.delete(existing);
    expect(client.requests.single.method, 'DELETE');
    expect(client.requests.single.path, RoutingResourceKind.gateway.itemPath);
    expect(client.requests.single.queryParameters, {'id': '0'});
  });

  test('default gateway reads and writes use their dedicated endpoint', () async {
    final defaults = await service.getDefaults();
    expect(defaults.ipv4, 'WAN_DHCP');
    expect(client.requests.single.path, routingDefaultGatewayPath);

    client.requests.clear();
    final updated = await service.updateDefaults(
      defaults,
      const {'defaultgw4': 'FAILOVER'},
    );
    expect(client.requests.single.method, 'PATCH');
    expect(client.requests.single.path, routingDefaultGatewayPath);
    expect(client.requests.single.data, {
      'defaultgw4': 'FAILOVER',
      'defaultgw6': '',
    });
    expect(updated.ipv4, 'FAILOVER');
  });

  test('routing apply is explicit and only uses the apply endpoint', () async {
    expect(await service.hasPendingChanges(), isTrue);
    expect(client.requests.single.method, 'GET');
    expect(client.requests.single.path, routingApplyPath);

    client.requests.clear();
    await service.apply();
    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, routingApplyPath);
    expect(client.requests.single.data, isNull);
  });

  test('gateway dependency scan reports groups routes rules and defaults', () async {
    final report = await service.findGatewayDependencies('WAN_DHCP');

    expect(report.gatewayGroups, ['FAILOVER']);
    expect(report.staticRoutes, ['10.20.0.0/16']);
    expect(report.firewallRules, ['Send traffic through WAN']);
    expect(report.defaultAssignments, ['IPv4']);
    expect(report.complete, isTrue);
    expect(
      client.requests.map((request) => request.path),
      containsAll([
        RoutingResourceKind.gatewayGroup.collectionPath,
        RoutingResourceKind.staticRoute.collectionPath,
        routingDefaultGatewayPath,
        routingFirewallRulesPath,
      ]),
    );
  });

  test('read-only schema exposes lists while disabling writes and apply', () async {
    final readOnlyClient = _RoutingApiClient(readOnly: true);
    final readOnlyCapabilities = PfRestCapabilityService(
      readOnlyClient,
      profileId: 'routing-read-only',
    );
    final readOnlyService = RoutingManagementService(
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
      RoutingResourceKind.values,
    );
    expect(readOnlyService.capabilities.canApply, isFalse);
    expect(readOnlyService.capabilities.canUpdateDefaults, isFalse);
    expect(
      readOnlyService.capabilities.resources.values.every(
        (capability) =>
            !capability.canCreate &&
            !capability.canUpdate &&
            !capability.canDelete,
      ),
      isTrue,
    );
    expect(
      await readOnlyService.list(RoutingResourceKind.gateway),
      isNotEmpty,
    );
  });
}

class _RoutingApiClient extends PfSenseApiClient {
  _RoutingApiClient({this.readOnly = false})
      : super(
          PfSenseProfile(
            id: 'routing-request-test',
            name: 'Routing request test',
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
    if (path == RoutingResourceKind.gateway.collectionPath) {
      return _response(path, {
        'data': [_gatewayData],
      });
    }
    if (path == RoutingResourceKind.gatewayGroup.collectionPath) {
      return _response(path, {
        'data': [_groupData],
      });
    }
    if (path == RoutingResourceKind.staticRoute.collectionPath) {
      return _response(path, {
        'data': [_routeData],
      });
    }
    if (path == routingDefaultGatewayPath) {
      return _response(path, {
        'data': {'defaultgw4': 'WAN_DHCP', 'defaultgw6': ''},
      });
    }
    if (path == routingApplyPath) {
      return _response(path, {
        'data': {'pending': true},
      });
    }
    if (path == routingFirewallRulesPath) {
      return _response(path, {
        'data': [
          {
            'id': 4,
            'descr': 'Send traffic through WAN',
            'gateway': 'WAN_DHCP',
          },
        ],
      });
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    requests.add(_Request('POST', path, data: data));
    if (path == routingApplyPath) return _response(path, {'data': true});
    if (RoutingResourceKind.values.any((kind) => kind.itemPath == path)) {
      return _response(path, {'data': data});
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    requests.add(_Request('PATCH', path, data: data));
    if (path == routingDefaultGatewayPath) {
      return _response(path, {'data': data});
    }
    if (RoutingResourceKind.values.any((kind) => kind.itemPath == path)) {
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
    routingDefaultGatewayPath: {
      'get': _operation(),
      if (!readOnly)
        'patch': _operation(
          fields: const {
            'defaultgw4': '',
            'defaultgw6': '',
          },
        ),
    },
    routingApplyPath: {
      'get': _operation(),
      if (!readOnly) 'post': _operation(),
    },
    routingFirewallRulesPath: {'get': _operation()},
  };
  for (final kind in RoutingResourceKind.values) {
    paths[kind.collectionPath] = {'get': _operation()};
    paths[kind.itemPath] = {
      'get': _operation(),
      if (!readOnly) 'post': _operation(fields: _writableData(kind)),
      if (!readOnly) 'patch': _operation(fields: _writableData(kind)),
      if (!readOnly) 'delete': _operation(queryId: true),
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
  bool queryId = false,
}) {
  return {
    'tags': ['ROUTING'],
    if (queryId)
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
        'required': true,
        'content': {
          'application/json': {
            'schema': {
              'type': 'object',
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
  if (value is bool) return {'type': 'boolean'};
  if (value is int) return {'type': 'integer'};
  if (value is List) {
    return {
      'type': 'array',
      'items': {'type': 'object'},
    };
  }
  return {'type': 'string'};
}

const _gatewayData = <String, dynamic>{
  'id': 0,
  'name': 'WAN_DHCP',
  'descr': 'Primary WAN',
  'disabled': false,
  'ipprotocol': 'inet',
  'interface': 'wan',
  'gateway': 'dynamic',
  'monitor_disable': false,
  'monitor': '1.1.1.1',
  'latencylow': 200,
  'latencyhigh': 500,
  'losslow': 10,
  'losshigh': 20,
  'future_setting': 'preserve-me',
  'runtime_status': 'online',
};

const _groupData = <String, dynamic>{
  'id': 1,
  'name': 'FAILOVER',
  'descr': 'WAN failover',
  'trigger': 'downloss',
  'ipprotocol': 'inet',
  'priorities': [
    {'gateway': 'WAN_DHCP', 'tier': 1, 'virtual_ip': 'address'},
  ],
};

const _routeData = <String, dynamic>{
  'id': 2,
  'network': '10.20.0.0/16',
  'gateway': 'WAN_DHCP',
  'descr': 'Remote network',
  'disabled': false,
};

Map<String, dynamic> _writableData(RoutingResourceKind kind) {
  final data = Map<String, dynamic>.from(
    switch (kind) {
      RoutingResourceKind.gateway => _gatewayData,
      RoutingResourceKind.gatewayGroup => _groupData,
      RoutingResourceKind.staticRoute => _routeData,
    },
  );
  data.remove('runtime_status');
  data.remove('ipprotocol');
  return data;
}
