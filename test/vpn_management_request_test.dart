import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/models/vpn_management.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfrest_capability_service.dart';
import 'package:pfsense_manager/services/vpn_management_service.dart';

void main() {
  late _VpnApiClient client;
  late PfRestCapabilityService capabilityService;
  late VpnManagementService service;

  setUp(() async {
    client = _VpnApiClient();
    capabilityService = PfRestCapabilityService(
      client,
      profileId: 'vpn-request-test',
    );
    service = VpnManagementService(
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

  test('lists every VPN resource from its exact collection endpoint', () async {
    for (final kind in VpnResourceKind.values.where((kind) => !kind.child)) {
      client.requests.clear();
      final resources = await service.list(kind);

      expect(client.requests.single.method, 'GET', reason: kind.name);
      expect(client.requests.single.path, kind.collectionPath, reason: kind.name);
      expect(resources.single.kind, kind);
    }
  });

  test('child collections require and send parent identifiers', () async {
    expect(
      () => service.list(VpnResourceKind.wireGuardTunnelAddress),
      throwsA(isA<ArgumentError>()),
    );

    client.requests.clear();
    final addresses = await service.list(
      VpnResourceKind.wireGuardTunnelAddress,
      parentId: 4,
    );
    expect(addresses.single.parentId, '4');
    expect(
      client.requests.single.path,
      VpnResourceKind.wireGuardTunnelAddress.collectionPath,
    );
    expect(client.requests.single.queryParameters, {'parent_id': '4'});
  });

  test('OpenVPN writes preserve fields omit secrets and need no apply call', () async {
    final server = ManagedVpnResource(
      kind: VpnResourceKind.openVpnServer,
      raw: _openVpnServerData,
    );
    await service.update(server, const {'description': 'Updated server'});

    expect(client.requests.single.method, 'PATCH');
    expect(client.requests.single.path, VpnResourceKind.openVpnServer.itemPath);
    expect(client.requests.single.data, containsPair('id', 1));
    expect(
      client.requests.single.data,
      containsPair('description', 'Updated server'),
    );
    expect(
      client.requests.single.data,
      containsPair('future_setting', 'preserve-me'),
    );
    expect(client.requests.single.data, isNot(contains('tls')));
    expect(client.requests.single.data, isNot(contains('runtime_status')));

    client.requests.clear();
    await service.apply(VpnTechnology.openVpn);
    expect(client.requests, isEmpty);
  });

  test('explicit secret replacements are sent only when provided', () async {
    final tunnel = ManagedVpnResource(
      kind: VpnResourceKind.wireGuardTunnel,
      raw: _wireGuardTunnelData,
    );
    await service.update(
      tunnel,
      const {'privatekey': 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC='},
    );

    expect(
      client.requests.single.data,
      containsPair(
        'privatekey',
        'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=',
      ),
    );
  });

  test('IPsec and WireGuard apply calls stay technology-specific', () async {
    expect(await service.hasPendingChanges(VpnTechnology.ipsec), isTrue);
    expect(client.requests.single.path, VpnTechnology.ipsec.applyPath);

    client.requests.clear();
    expect(await service.hasPendingChanges(VpnTechnology.wireGuard), isFalse);
    expect(client.requests.single.path, VpnTechnology.wireGuard.applyPath);

    client.requests.clear();
    await service.apply(VpnTechnology.ipsec);
    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, VpnTechnology.ipsec.applyPath);

    client.requests.clear();
    await service.apply(VpnTechnology.wireGuard);
    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, VpnTechnology.wireGuard.applyPath);
  });

  test('WireGuard settings use the reported settings and apply endpoints', () async {
    final settings = await service.getSettings(VpnTechnology.wireGuard);
    expect(settings.raw['enable'], isTrue);
    expect(client.requests.single.path, VpnTechnology.wireGuard.settingsPath);

    client.requests.clear();
    await service.updateSettings(
      VpnTechnology.wireGuard,
      settings,
      const {'enable': false},
    );
    expect(client.requests.single.method, 'PATCH');
    expect(client.requests.single.path, VpnTechnology.wireGuard.settingsPath);
    expect(client.requests.single.data, containsPair('enable', false));
  });

  test('child writes and deletes place identifiers correctly', () async {
    await service.create(
      VpnResourceKind.wireGuardPeerAllowedIp,
      const {
        'parent_id': 7,
        'address': '10.20.0.0',
        'mask': 24,
        'descr': 'Remote network',
      },
    );
    expect(client.requests.single.method, 'POST');
    expect(
      client.requests.single.path,
      VpnResourceKind.wireGuardPeerAllowedIp.itemPath,
    );
    expect(client.requests.single.data, containsPair('parent_id', 7));

    client.requests.clear();
    final allowedIp = ManagedVpnResource(
      kind: VpnResourceKind.wireGuardPeerAllowedIp,
      raw: _wireGuardAllowedIpData,
    );
    await service.update(allowedIp, const {'descr': 'Updated network'});
    expect(client.requests.single.method, 'PATCH');
    expect(client.requests.single.data, containsPair('id', 2));
    expect(client.requests.single.data, containsPair('parent_id', 7));

    client.requests.clear();
    await service.delete(allowedIp);
    expect(client.requests.single.method, 'DELETE');
    expect(client.requests.single.queryParameters, {
      'parent_id': '7',
      'id': '2',
    });
  });

  test('OpenVPN client exports are returned without becoming resources', () async {
    final export = await service.exportOpenVpnClient(
      const {
        'server': 1,
        'type': 'confinline',
        'username': 'alice',
        'certref': 'cert-ref',
      },
    );

    expect(client.requests.single.method, 'POST');
    expect(client.requests.single.path, openVpnClientExportPath);
    expect(export.filename, 'alice.ovpn');
    expect(export.data, contains('<ca>'));
  });

  test('read-only schema exposes reported collections but no writes', () async {
    final readOnlyClient = _VpnApiClient(readOnly: true);
    final readOnlyCapabilities = PfRestCapabilityService(
      readOnlyClient,
      profileId: 'vpn-read-only',
    );
    final readOnlyService = VpnManagementService(
      readOnlyClient,
      capabilityService: readOnlyCapabilities,
    );
    addTearDown(() {
      readOnlyCapabilities.dispose();
      readOnlyClient.dispose();
    });
    await readOnlyCapabilities.refresh();

    expect(
      readOnlyService.capabilities.readableTechnologies,
      [VpnTechnology.openVpn],
    );
    expect(
      readOnlyService.capabilities
          .forKind(VpnResourceKind.openVpnServer)
          .canCreate,
      isFalse,
    );
    expect(readOnlyService.capabilities.canExportOpenVpnClient, isFalse);
    expect(
      await readOnlyService.list(VpnResourceKind.openVpnServer),
      isNotEmpty,
    );
  });
}

class _VpnApiClient extends PfSenseApiClient {
  _VpnApiClient({this.readOnly = false})
      : super(
          PfSenseProfile(
            id: 'vpn-request-test',
            name: 'VPN request test',
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
    if (path == VpnTechnology.wireGuard.settingsPath) {
      return _response(path, {'data': _wireGuardSettingsData});
    }
    if (path == VpnTechnology.ipsec.applyPath) {
      return _response(path, {
        'data': {'pending': true},
      });
    }
    if (path == VpnTechnology.wireGuard.applyPath) {
      return _response(path, {
        'data': {'pending': false},
      });
    }
    final kind = VpnResourceKind.values
        .where((item) => item.collectionPath == path)
        .firstOrNull;
    if (kind != null) {
      final data = _resourceData(kind);
      return _response(path, {
        'data': [
          if (kind.child)
            {...data, 'parent_id': queryParameters?['parent_id']}
          else
            data,
        ],
      });
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    requests.add(_Request('POST', path, data: data));
    if (path == VpnTechnology.ipsec.applyPath ||
        path == VpnTechnology.wireGuard.applyPath) {
      return _response(path, {'data': true});
    }
    if (path == openVpnClientExportPath) {
      return _response(path, {
        'data': {
          'filename': 'alice.ovpn',
          'binary_data': 'client\n<ca>certificate</ca>',
        },
      });
    }
    if (VpnResourceKind.values.any((kind) => kind.itemPath == path)) {
      return _response(path, {'data': data});
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    requests.add(_Request('PATCH', path, data: data));
    if (path == VpnTechnology.wireGuard.settingsPath ||
        VpnResourceKind.values.any((kind) => kind.itemPath == path)) {
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
  if (readOnly) {
    return {
      'data': {
        'openapi': '3.0.3',
        'paths': {
          VpnResourceKind.openVpnServer.collectionPath: {
            'get': _operation(),
          },
        },
      },
    };
  }

  final paths = <String, dynamic>{
    VpnTechnology.ipsec.applyPath!: {
      'get': _operation(),
      'post': _operation(),
    },
    VpnTechnology.wireGuard.applyPath!: {
      'get': _operation(),
      'post': _operation(),
    },
    VpnTechnology.wireGuard.settingsPath!: {
      'get': _operation(),
      'patch': _operation(fields: _wireGuardSettingsData),
    },
    openVpnClientExportPath: {
      'post': _operation(
        fields: const {
          'server': 0,
          'type': 'confinline',
          'username': '',
          'certref': '',
          'filename': '',
          'binary_data': '',
        },
        requiredFields: const ['server', 'type'],
        readOnlyFields: const ['filename', 'binary_data'],
      ),
    },
  };

  for (final kind in VpnResourceKind.values) {
    paths[kind.collectionPath] = {
      'get': _operation(parentQuery: kind.child),
    };
    paths[kind.itemPath] = {
      'get': _operation(idQuery: true, parentQuery: kind.child),
      'post': _operation(
        fields: _writableData(kind, create: true),
        requiredFields: _requiredFields(kind, create: true),
        secretFields: _secretFields(kind),
        readOnlyFields: _readOnlyFields(kind),
      ),
      'patch': _operation(
        fields: _writableData(kind),
        requiredFields: _requiredFields(kind),
        secretFields: _secretFields(kind),
        readOnlyFields: _readOnlyFields(kind),
      ),
      'delete': _operation(idQuery: true, parentQuery: kind.child),
    };
  }

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
  List<String> readOnlyFields = const [],
  bool idQuery = false,
  bool parentQuery = false,
}) {
  return {
    'tags': ['VPN'],
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
                    if (readOnlyFields.contains(entry.key)) 'readOnly': true,
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
      'items': value.isNotEmpty && value.first is Map
          ? {'type': 'object'}
          : {'type': 'string'},
    };
  }
  return {'type': 'string'};
}

Map<String, dynamic> _writableData(
  VpnResourceKind kind, {
  bool create = false,
}) {
  final data = Map<String, dynamic>.from(_resourceData(kind));
  data.remove('runtime_status');
  if (create) data.remove('id');
  return data;
}

List<String> _requiredFields(
  VpnResourceKind kind, {
  bool create = false,
}) {
  return switch (kind) {
    VpnResourceKind.openVpnServer => const [
        'mode',
        'dev_mode',
        'protocol',
        'interface',
      ],
    VpnResourceKind.openVpnClient => const [
        'mode',
        'dev_mode',
        'protocol',
        'interface',
        'server_addr',
        'server_port',
      ],
    VpnResourceKind.openVpnCso => const ['common_name'],
    VpnResourceKind.openVpnExportConfig => const ['server'],
    VpnResourceKind.ipsecPhase1 => const [
        'iketype',
        'protocol',
        'interface',
        'remote_gateway',
        'authentication_method',
        'encryption',
      ],
    VpnResourceKind.ipsecPhase2 => const ['ikeid', 'encryption'],
    VpnResourceKind.wireGuardTunnel => create
        ? const ['privatekey']
        : const ['id'],
    VpnResourceKind.wireGuardPeer => const ['publickey'],
    VpnResourceKind.wireGuardTunnelAddress ||
    VpnResourceKind.wireGuardPeerAllowedIp => create
        ? const ['parent_id', 'address', 'mask']
        : const ['parent_id', 'id'],
  };
}

List<String> _secretFields(VpnResourceKind kind) {
  return switch (kind) {
    VpnResourceKind.openVpnServer => const ['tls'],
    VpnResourceKind.openVpnClient => const [
        'tls',
        'proxy_passwd',
        'auth_pass',
      ],
    VpnResourceKind.ipsecPhase1 => const ['pre_shared_key'],
    VpnResourceKind.wireGuardTunnel => const ['privatekey'],
    VpnResourceKind.wireGuardPeer => const ['presharedkey'],
    _ => const [],
  };
}

List<String> _readOnlyFields(VpnResourceKind kind) {
  return switch (kind) {
    VpnResourceKind.openVpnServer ||
    VpnResourceKind.openVpnClient => const ['vpnid', 'vpnif'],
    VpnResourceKind.ipsecPhase1 => const ['ikeid'],
    VpnResourceKind.wireGuardTunnel => const ['name', 'publickey'],
    _ => const [],
  };
}

Map<String, dynamic> _resourceData(VpnResourceKind kind) {
  return switch (kind) {
    VpnResourceKind.openVpnServer => _openVpnServerData,
    VpnResourceKind.openVpnClient => _openVpnClientData,
    VpnResourceKind.openVpnCso => _openVpnCsoData,
    VpnResourceKind.openVpnExportConfig => _openVpnExportConfigData,
    VpnResourceKind.ipsecPhase1 => _ipsecPhase1Data,
    VpnResourceKind.ipsecPhase2 => _ipsecPhase2Data,
    VpnResourceKind.wireGuardTunnel => _wireGuardTunnelData,
    VpnResourceKind.wireGuardPeer => _wireGuardPeerData,
    VpnResourceKind.wireGuardTunnelAddress => _wireGuardAddressData,
    VpnResourceKind.wireGuardPeerAllowedIp => _wireGuardAllowedIpData,
  };
}

const _openVpnServerData = <String, dynamic>{
  'id': 1,
  'vpnid': 10,
  'description': 'Remote access',
  'disable': false,
  'mode': 'server_tls',
  'dev_mode': 'tun',
  'protocol': 'UDP4',
  'interface': 'wan',
  'local_port': 1194,
  'tls': 'must-not-return',
  'future_setting': 'preserve-me',
  'runtime_status': 'running',
};

const _openVpnClientData = <String, dynamic>{
  'id': 2,
  'vpnid': 11,
  'description': 'Provider VPN',
  'disable': false,
  'mode': 'p2p_tls',
  'dev_mode': 'tun',
  'protocol': 'UDP4',
  'interface': 'wan',
  'server_addr': 'vpn.example.test',
  'server_port': 1194,
  'auth_user': 'client',
  'auth_pass': 'must-not-return',
};

const _openVpnCsoData = <String, dynamic>{
  'id': 3,
  'common_name': 'alice',
  'description': 'Alice routes',
  'server_list': [10],
  'remote_network': '10.20.0.0/24',
};

const _openVpnExportConfigData = <String, dynamic>{
  'id': 4,
  'server': 10,
  'description': 'Default inline export',
  'useaddr': 'serveraddr',
};

const _ipsecPhase1Data = <String, dynamic>{
  'id': 5,
  'ikeid': 20,
  'descr': 'Branch office',
  'disabled': false,
  'iketype': 'ikev2',
  'protocol': 'inet',
  'interface': 'wan',
  'remote_gateway': '198.51.100.10',
  'authentication_method': 'pre_shared_key',
  'pre_shared_key': 'must-not-return',
  'encryption': [
    {'encryption_algorithm': 'aes', 'key_length': 256},
  ],
};

const _ipsecPhase2Data = <String, dynamic>{
  'id': 6,
  'ikeid': 20,
  'descr': 'Branch LAN',
  'disabled': false,
  'mode': 'tunnel',
  'localid_address': '192.168.1.0/24',
  'remoteid_address': '10.20.0.0/24',
  'encryption': [
    {'encryption_algorithm': 'aes', 'key_length': 256},
  ],
};

const _wireGuardTunnelData = <String, dynamic>{
  'id': 4,
  'name': 'tun_wg0',
  'enabled': true,
  'descr': 'Site tunnel',
  'listenport': 51820,
  'publickey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  'privatekey': 'must-not-return',
  'mtu': 1420,
  'addresses': [
    {'address': '10.10.0.1', 'mask': 24},
  ],
};

const _wireGuardPeerData = <String, dynamic>{
  'id': 7,
  'enabled': true,
  'tun': 'tun_wg0',
  'endpoint': 'peer.example.test',
  'port': 51820,
  'descr': 'Branch peer',
  'publickey': 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
  'presharedkey': 'must-not-return',
  'allowedips': [
    {'address': '10.20.0.0', 'mask': 24},
  ],
};

const _wireGuardAddressData = <String, dynamic>{
  'id': 1,
  'parent_id': 4,
  'address': '10.10.0.1',
  'mask': 24,
  'descr': 'Tunnel address',
};

const _wireGuardAllowedIpData = <String, dynamic>{
  'id': 2,
  'parent_id': 7,
  'address': '10.20.0.0',
  'mask': 24,
  'descr': 'Remote network',
};

const _wireGuardSettingsData = <String, dynamic>{
  'enable': true,
  'keepalive': 25,
};

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
