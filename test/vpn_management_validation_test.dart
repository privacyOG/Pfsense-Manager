import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/models/vpn_management.dart';
import 'package:pfsense_manager/utils/vpn_management_validation.dart';

void main() {
  test(
    'OpenVPN server validation enforces ports networks and new TLS keys',
    () {
      final result = validateVpnResource(
        kind: VpnResourceKind.openVpnServer,
        values: const {
          'mode': 'server_tls',
          'dev_mode': 'tun',
          'protocol': 'UDP4',
          'interface': 'wan',
          'local_port': 70000,
          'use_tls': true,
          'tls': '',
          'tunnel_network': '2001:db8::/64',
        },
        operation: _operation(
          fields: const [
            'mode',
            'dev_mode',
            'protocol',
            'interface',
            'local_port',
            'use_tls',
            'tls',
            'tunnel_network',
          ],
          requiredFields: const ['mode', 'dev_mode', 'protocol', 'interface'],
          secretFields: const ['tls'],
        ),
        editing: false,
      );

      expect(result.errors['local_port'], contains('65535'));
      expect(result.errors['tls'], contains('TLS key'));
      expect(result.errors['tunnel_network'], contains('IPv4'));
    },
  );

  test('OpenVPN client edit preserves absent passwords', () {
    final result = validateVpnResource(
      kind: VpnResourceKind.openVpnClient,
      values: const {
        'mode': 'p2p_tls',
        'dev_mode': 'tun',
        'protocol': 'UDP4',
        'interface': 'wan',
        'server_addr': 'vpn.example.test',
        'server_port': 1194,
        'proxy_authtype': 'basic',
        'proxy_user': 'proxy-user',
        'proxy_passwd': '',
        'auth_user': 'vpn-user',
        'auth_pass': '',
      },
      operation: _operation(
        fields: const [
          'mode',
          'dev_mode',
          'protocol',
          'interface',
          'server_addr',
          'server_port',
          'proxy_authtype',
          'proxy_user',
          'proxy_passwd',
          'auth_user',
          'auth_pass',
        ],
        requiredFields: const [
          'mode',
          'dev_mode',
          'protocol',
          'interface',
          'server_addr',
          'server_port',
          'proxy_passwd',
        ],
        secretFields: const ['proxy_passwd', 'auth_pass'],
      ),
      editing: true,
    );

    expect(result.isValid, isTrue);
  });

  test('IPsec Phase 1 validates gateway secret encryption and timers', () {
    final result = validateVpnResource(
      kind: VpnResourceKind.ipsecPhase1,
      values: const {
        'iketype': 'ikev2',
        'protocol': 'inet',
        'interface': 'wan',
        'remote_gateway': 'not a gateway',
        'authentication_method': 'pre_shared_key',
        'pre_shared_key': '',
        'lifetime': 3600,
        'rekey_time': 4000,
        'encryption': <dynamic>[],
      },
      operation: _operation(
        fields: const [
          'iketype',
          'protocol',
          'interface',
          'remote_gateway',
          'authentication_method',
          'pre_shared_key',
          'lifetime',
          'rekey_time',
          'encryption',
        ],
        requiredFields: const [
          'iketype',
          'protocol',
          'interface',
          'remote_gateway',
          'authentication_method',
          'pre_shared_key',
          'encryption',
        ],
        secretFields: const ['pre_shared_key'],
        objectArrayFields: const ['encryption'],
      ),
      editing: false,
    );

    expect(result.errors['remote_gateway'], contains('valid'));
    expect(result.errors['pre_shared_key'], contains('pre-shared'));
    expect(result.errors['encryption'], contains('at least one'));
    expect(result.errors['rekey_time'], contains('cannot exceed'));
  });

  test('IPsec duplicate gateways are rejected unless explicitly allowed', () {
    final existing = ManagedVpnResource(
      kind: VpnResourceKind.ipsecPhase1,
      raw: const {
        'id': 1,
        'ikeid': 10,
        'disabled': false,
        'remote_gateway': '198.51.100.10',
      },
    );
    final result = validateVpnResource(
      kind: VpnResourceKind.ipsecPhase1,
      values: const {
        'remote_gateway': '198.51.100.10',
        'gw_duplicates': false,
        'authentication_method': 'cert',
        'encryption': [
          {'encryption_algorithm': 'aes', 'key_length': 256},
        ],
      },
      operation: _operation(
        fields: const [
          'remote_gateway',
          'gw_duplicates',
          'authentication_method',
          'encryption',
        ],
        objectArrayFields: const ['encryption'],
      ),
      editing: false,
      context: VpnValidationContext(resources: [existing]),
    );

    expect(result.errors['remote_gateway'], contains('already uses'));
  });

  test('WireGuard tunnel validates keys nested addresses and ports', () {
    final result = validateVpnResource(
      kind: VpnResourceKind.wireGuardTunnel,
      values: const {
        'enabled': true,
        'listenport': 0,
        'privatekey': 'invalid',
        'addresses': [
          {'address': '10.10.0.1', 'mask': 0},
        ],
      },
      operation: _operation(
        fields: const ['enabled', 'listenport', 'privatekey', 'addresses'],
        requiredFields: const ['privatekey'],
        secretFields: const ['privatekey'],
        objectArrayFields: const ['addresses'],
      ),
      editing: false,
    );

    expect(result.errors['listenport'], contains('65535'));
    expect(result.errors['privatekey'], contains('valid'));
    expect(result.errors['addresses'], contains('between 1'));
  });

  test('WireGuard peer validates endpoint keys allowed IPs and duplicates', () {
    final existing = ManagedVpnResource(
      kind: VpnResourceKind.wireGuardPeer,
      raw: const {
        'id': 3,
        'publickey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        'descr': 'Existing peer',
      },
    );
    final result = validateVpnResource(
      kind: VpnResourceKind.wireGuardPeer,
      values: const {
        'tun': 'tun_wg0',
        'endpoint': 'bad endpoint',
        'port': 51820,
        'publickey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        'presharedkey': 'invalid',
        'persistentkeepalive': 70000,
        'allowedips': [
          {'address': '10.0.0.0', 'mask': 33},
        ],
      },
      operation: _operation(
        fields: const [
          'tun',
          'endpoint',
          'port',
          'publickey',
          'presharedkey',
          'persistentkeepalive',
          'allowedips',
        ],
        requiredFields: const ['publickey'],
        secretFields: const ['presharedkey'],
        objectArrayFields: const ['allowedips'],
      ),
      editing: false,
      context: VpnValidationContext(resources: [existing]),
    );

    expect(result.errors['endpoint'], contains('valid'));
    expect(result.errors['publickey'], contains('already'));
    expect(result.errors['presharedkey'], contains('valid'));
    expect(result.errors['persistentkeepalive'], contains('65535'));
    expect(result.errors['allowedips'], contains('between 0 and 32'));
  });

  test('child WireGuard addresses require parent and valid prefix', () {
    final result = validateVpnResource(
      kind: VpnResourceKind.wireGuardTunnelAddress,
      values: const {'parent_id': '', 'address': '2001:db8::1', 'mask': 129},
      operation: _operation(
        fields: const ['parent_id', 'address', 'mask'],
        requiredFields: const ['parent_id', 'address', 'mask'],
      ),
      editing: false,
    );

    expect(result.errors['parent_id'], contains('parent'));
    expect(result.errors['mask'], contains('128'));
  });

  test('WireGuard settings validate the active resolve interval', () {
    final operation = PfRestOperationCapability(
      path: VpnTechnology.wireGuard.settingsPath!,
      method: 'PATCH',
      requestFields: const {
        'body:resolve_interval_track': PfRestFieldConstraint(
          name: 'resolve_interval_track',
          location: 'body',
          required: false,
          type: 'boolean',
        ),
        'body:resolve_interval': PfRestFieldConstraint(
          name: 'resolve_interval',
          location: 'body',
          required: false,
          type: 'integer',
        ),
      },
      tags: const {'VPN'},
    );

    final direct = validateVpnSettings(
      technology: VpnTechnology.wireGuard,
      values: const {'resolve_interval_track': false, 'resolve_interval': 0},
      operation: operation,
    );
    final tracked = validateVpnSettings(
      technology: VpnTechnology.wireGuard,
      values: const {'resolve_interval_track': true, 'resolve_interval': 0},
      operation: operation,
    );

    expect(direct.errors['resolve_interval'], contains('at least 1'));
    expect(tracked.isValid, isTrue);
  });

  test('normalisation parses numeric and nested JSON values', () {
    final operation = _operation(
      fields: const ['listenport', 'addresses', 'data_ciphers'],
      objectArrayFields: const ['addresses'],
      arrayFields: const ['data_ciphers'],
    );
    final values = normaliseVpnValues(
      values: const {
        'listenport': '51820',
        'addresses': '[{"address":"10.0.0.1","mask":24}]',
        'data_ciphers': 'AES-256-GCM, AES-128-GCM',
      },
      operation: operation,
    );

    expect(values['listenport'], 51820);
    expect(values['addresses'], [
      {'address': '10.0.0.1', 'mask': 24},
    ]);
    expect(values['data_ciphers'], ['AES-256-GCM', 'AES-128-GCM']);
  });
}

PfRestOperationCapability _operation({
  required List<String> fields,
  List<String> requiredFields = const [],
  List<String> secretFields = const [],
  List<String> arrayFields = const [],
  List<String> objectArrayFields = const [],
}) {
  return PfRestOperationCapability(
    path: '/api/v2/vpn/test',
    method: 'PATCH',
    requestFields: {
      for (final name in fields)
        'body:$name': PfRestFieldConstraint(
          name: name,
          location: 'body',
          required: requiredFields.contains(name),
          type:
              name == 'enabled' ||
                  name == 'disable' ||
                  name == 'disabled' ||
                  name == 'use_tls' ||
                  name == 'gw_duplicates'
              ? 'boolean'
              : name.contains('port') ||
                    name == 'lifetime' ||
                    name == 'rekey_time' ||
                    name == 'persistentkeepalive' ||
                    name == 'mask'
              ? 'integer'
              : arrayFields.contains(name) || objectArrayFields.contains(name)
              ? 'array'
              : 'string',
          writeOnly: secretFields.contains(name),
        ),
    },
    tags: const {'VPN'},
  );
}
