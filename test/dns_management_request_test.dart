import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dns_management.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/dns_management_service.dart';
import 'package:pfsense_manager/services/pfrest_capability_service.dart';

void main() {
  late _DnsApiClient client;
  late PfRestCapabilityService capabilityService;
  late DnsManagementService service;

  setUp(() async {
    client = _DnsApiClient();
    capabilityService = PfRestCapabilityService(
      client,
      profileId: 'dns-request-test',
    );
    service = DnsManagementService(
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

  test('reads and updates Resolver settings through the dedicated endpoint', () async {
    final settings = await service.getResolverSettings();
    expect(settings.enabled, isTrue);
    expect(client.requests.single.method, 'GET');
    expect(client.requests.single.path, dnsResolverSettingsPath);

    client.requests.clear();
    await service.updateResolverSettings(
      settings,
      const {'forwarding': true},
    );
    final update = client.requests.single;
    expect(update.method, 'PATCH');
    expect(update.path, dnsResolverSettingsPath);
    expect(update.data, containsPair('forwarding', true));
    expect(update.data, containsPair('future_setting', 'preserve-me'));
    expect(update.data, isNot(contains('runtime_status')));
  });

  test('lists top-level resources from exact collection endpoints', () async {
    for (final kind in DnsResourceKind.values.where((kind) => !kind.child)) {
      client.requests.clear();
      final resources = await service.list(kind);

      expect(client.requests.single.method, 'GET');
      expect(client.requests.single.path, kind.collectionPath);
      expect(resources.single.kind, kind);
    }
  });

  test('child collections require and send parent identifiers', () async {
    expect(
      () => service.list(DnsResourceKind.resolverHostAlias),
      throwsA(isA<ArgumentError>()),
    );

    client.requests.clear();
    final aliases = await service.list(
      DnsResourceKind.resolverHostAlias,
      parentId: 2,
    );
    expect(aliases.single.parentId, '2');
    expect(client.requests.single.path,
        DnsResourceKind.resolverHostAlias.collectionPath);
    expect(client.requests.single.queryParameters, {'parent_id': '2'});
  });

  test('resource writes preserve fields and use singular endpoints', () async {
    final resource = ManagedDnsResource(
      kind: DnsResourceKind.resolverHostOverride,
      raw: _resolverHostData,
    );
    await service.update(resource, const {'descr': 'Main gateway'});

    final update = client.requests.single;
    expect(update.method, 'PATCH');
    expect(update.path, DnsResourceKind.resolverHostOverride.itemPath);
    expect(update.data, containsPair('id', 2));
    expect(update.data, containsPair('descr', 'Main gateway'));
    expect(update.data, containsPair('future_setting', 'preserve-me'));

    client.requests.clear();
    await service.create(
      DnsResourceKind.forwarderHostOverride,
      const {
        'host': 'printer',
        'domain': 'example.test',
        'ip': '192.168.1.50',
      },
    );
    expect(client.requests.single.method, 'POST');
    expect(
      client.requests.single.path,
      DnsResourceKind.forwarderHostOverride.itemPath,
    );
  });

  test('child writes and deletes place identifiers correctly', () async {
    await service.create(
      DnsResourceKind.resolverHostAlias,
      const {
        'parent_id': 2,
        'host': 'gateway',
        'domain': 'example.test',
      },
    );
    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.data, containsPair('parent_id', 2));

    client.requests.clear();
    final alias = ManagedDnsResource(
      kind: DnsResourceKind.resolverHostAlias,
      raw: _resolverAliasData,
    );
    await service.update(alias, const {'descr': 'Alias'});
    expect(client.requests.single.method, 'PATCH');
    expect(client.requests.single.data, containsPair('id', 4));
    expect(client.requests.single.data, containsPair('parent_id', 2));

    client.requests.clear();
    await service.delete(alias);
    expect(client.requests.single.method, 'DELETE');
    expect(client.requests.single.queryParameters, {
      'parent_id': '2',
      'id': '4',
    });
  });

  test('pending checks and apply remain service-specific', () async {
    expect(await service.hasPendingChanges(DnsServiceKind.resolver), isTrue);
    expect(client.requests.single.path, DnsServiceKind.resolver.applyPath);

    client.requests.clear();
    expect(await service.hasPendingChanges(DnsServiceKind.forwarder), isFalse);
    expect(client.requests.single.path, DnsServiceKind.forwarder.applyPath);

    client.requests.clear();
    await service.apply(DnsServiceKind.resolver);
    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, DnsServiceKind.resolver.applyPath);

    client.requests.clear();
    await service.apply(DnsServiceKind.forwarder);
    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, DnsServiceKind.forwarder.applyPath);
  });

  test('read-only asymmetric schema exposes only reported operations', () async {
    final readOnlyClient = _DnsApiClient(readOnly: true);
    final readOnlyCapabilities = PfRestCapabilityService(
      readOnlyClient,
      profileId: 'dns-read-only',
    );
    final readOnlyService = DnsManagementService(
      readOnlyClient,
      capabilityService: readOnlyCapabilities,
    );
    addTearDown(() {
      readOnlyCapabilities.dispose();
      readOnlyClient.dispose();
    });
    await readOnlyCapabilities.refresh();

    expect(readOnlyService.capabilities.canReadSettings, isTrue);
    expect(readOnlyService.capabilities.canUpdateSettings, isFalse);
    expect(
      readOnlyService.capabilities.forService(DnsServiceKind.resolver).canApply,
      isFalse,
    );
    expect(
      readOnlyService.capabilities
          .forService(DnsServiceKind.forwarder)
          .resources,
      [DnsResourceKind.forwarderHostOverride],
    );
    expect(
      readOnlyService.capabilities
          .forKind(DnsResourceKind.forwarderHostOverride)
          .canCreate,
      isFalse,
    );
    expect(
      await readOnlyService.list(DnsResourceKind.forwarderHostOverride),
      isNotEmpty,
    );
  });
}

class _DnsApiClient extends PfSenseApiClient {
  _DnsApiClient({this.readOnly = false})
      : super(
          PfSenseProfile(
            id: 'dns-request-test',
            name: 'DNS request test',
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
    if (path == pfRestOpenApiSchemaPath) {
      return _response(path, _schema(readOnly));
    }
    if (path == dnsResolverSettingsPath) {
      return _response(path, {'data': _resolverSettingsData});
    }
    if (path == DnsResourceKind.resolverHostOverride.collectionPath) {
      return _response(path, {
        'data': [_resolverHostData],
      });
    }
    if (path == DnsResourceKind.resolverDomainOverride.collectionPath) {
      return _response(path, {
        'data': [_domainData],
      });
    }
    if (path == DnsResourceKind.resolverAccessList.collectionPath) {
      return _response(path, {
        'data': [_accessListData],
      });
    }
    if (path == DnsResourceKind.resolverHostAlias.collectionPath) {
      return _response(path, {
        'data': [
          {..._resolverAliasData, 'parent_id': queryParameters?['parent_id']},
        ],
      });
    }
    if (path == DnsResourceKind.resolverAccessListNetwork.collectionPath) {
      return _response(path, {
        'data': [
          {..._networkData, 'parent_id': queryParameters?['parent_id']},
        ],
      });
    }
    if (path == DnsResourceKind.forwarderHostOverride.collectionPath) {
      return _response(path, {
        'data': [_forwarderHostData],
      });
    }
    if (path == DnsResourceKind.forwarderHostAlias.collectionPath) {
      return _response(path, {
        'data': [
          {..._forwarderAliasData, 'parent_id': queryParameters?['parent_id']},
        ],
      });
    }
    if (path == DnsServiceKind.resolver.applyPath) {
      return _response(path, {
        'data': {'pending': true},
      });
    }
    if (path == DnsServiceKind.forwarder.applyPath) {
      return _response(path, {
        'data': {'pending': false},
      });
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    requests.add(_Request('POST', path, data: data));
    if (path == DnsServiceKind.resolver.applyPath ||
        path == DnsServiceKind.forwarder.applyPath) {
      return _response(path, {'data': true});
    }
    if (DnsResourceKind.values.any((kind) => kind.itemPath == path)) {
      return _response(path, {'data': data});
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    requests.add(_Request('PATCH', path, data: data));
    if (path == dnsResolverSettingsPath ||
        DnsResourceKind.values.any((kind) => kind.itemPath == path)) {
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
    dnsResolverSettingsPath: {
      'get': _operation(),
      if (!readOnly)
        'patch': _operation(
          fields: _resolverSettingsData,
          requiredFields: const ['enable'],
        ),
    },
    DnsServiceKind.resolver.applyPath: {
      'get': _operation(),
      if (!readOnly) 'post': _operation(),
    },
    DnsServiceKind.forwarder.applyPath: {
      if (!readOnly) 'get': _operation(),
      if (!readOnly) 'post': _operation(),
    },
  };

  final includedKinds = readOnly
      ? const [DnsResourceKind.forwarderHostOverride]
      : DnsResourceKind.values;
  for (final kind in includedKinds) {
    paths[kind.collectionPath] = {
      'get': _operation(parentQuery: kind.child),
    };
    paths[kind.itemPath] = {
      'get': _operation(
        idQuery: true,
        parentQuery: kind.child,
      ),
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
          idQuery: true,
          parentQuery: kind.child,
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
  bool idQuery = false,
  bool parentQuery = false,
}) {
  return {
    'tags': ['SERVICES'],
    if (idQuery || parentQuery)
      'parameters': [
        if (parentQuery)
          {
            'name': 'parent_id',
            'in': 'query',
            'required': true,
            'schema': {'type': 'integer'},
          },
        if (idQuery)
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
      'items': value.isNotEmpty && value.first is Map
          ? {'type': 'object'}
          : {'type': 'string'},
    };
  }
  return {'type': 'string'};
}

List<String> _requiredFields(
  DnsResourceKind kind, {
  bool create = false,
}) {
  return switch (kind) {
    DnsResourceKind.resolverHostOverride => const ['domain', 'ip'],
    DnsResourceKind.forwarderHostOverride => const ['host', 'domain', 'ip'],
    DnsResourceKind.resolverDomainOverride => const ['domain', 'ip'],
    DnsResourceKind.resolverAccessList => const ['name', 'action', 'networks'],
    DnsResourceKind.resolverHostAlias ||
    DnsResourceKind.forwarderHostAlias => create
        ? const ['parent_id', 'host', 'domain']
        : const ['parent_id', 'id'],
    DnsResourceKind.resolverAccessListNetwork => create
        ? const ['parent_id', 'network', 'mask']
        : const ['parent_id', 'id'],
  };
}

Map<String, dynamic> _writableData(
  DnsResourceKind kind, {
  bool create = false,
}) {
  final data = Map<String, dynamic>.from(
    switch (kind) {
      DnsResourceKind.resolverHostOverride => _resolverHostData,
      DnsResourceKind.resolverDomainOverride => _domainData,
      DnsResourceKind.resolverAccessList => _accessListData,
      DnsResourceKind.resolverHostAlias => _resolverAliasData,
      DnsResourceKind.resolverAccessListNetwork => _networkData,
      DnsResourceKind.forwarderHostOverride => _forwarderHostData,
      DnsResourceKind.forwarderHostAlias => _forwarderAliasData,
    },
  );
  data.remove('runtime_status');
  if (create) data.remove('id');
  return data;
}

const _resolverSettingsData = <String, dynamic>{
  'enable': true,
  'port': 53,
  'enablessl': false,
  'sslcertref': '',
  'tlsport': 853,
  'active_interface': ['all'],
  'outgoing_interface': ['all'],
  'strictout': false,
  'dnssec': true,
  'forwarding': false,
  'custom_options': '',
  'future_setting': 'preserve-me',
  'runtime_status': 'running',
};

const _resolverHostData = <String, dynamic>{
  'id': 2,
  'host': 'router',
  'domain': 'example.test',
  'ip': ['192.168.1.1'],
  'descr': 'Gateway',
  'aliases': <Map<String, dynamic>>[],
  'future_setting': 'preserve-me',
};

const _domainData = <String, dynamic>{
  'id': 3,
  'domain': 'corp.example',
  'ip': '192.0.2.53',
  'descr': 'Corporate DNS',
  'forward_tls_upstream': false,
  'tls_hostname': '',
};

const _accessListData = <String, dynamic>{
  'id': 6,
  'name': 'clients',
  'action': 'allow',
  'description': 'Client networks',
  'networks': [
    {
      'network': '192.168.1.0',
      'mask': 24,
      'description': 'LAN',
    },
  ],
};

const _resolverAliasData = <String, dynamic>{
  'id': 4,
  'parent_id': 2,
  'host': 'gateway',
  'domain': 'example.test',
  'descr': 'Alias',
};

const _networkData = <String, dynamic>{
  'id': 7,
  'parent_id': 6,
  'network': '192.168.1.0',
  'mask': 24,
  'description': 'LAN',
};

const _forwarderHostData = <String, dynamic>{
  'id': 8,
  'host': 'printer',
  'domain': 'example.test',
  'ip': '192.168.1.50',
  'description': 'Printer',
  'aliases': <Map<String, dynamic>>[],
};

const _forwarderAliasData = <String, dynamic>{
  'id': 9,
  'parent_id': 8,
  'host': 'laser',
  'domain': 'example.test',
  'description': 'Printer alias',
};
