import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/models/vpn_management.dart';

void main() {
  test('VPN endpoint paths match the pfREST contract', () {
    expect(
      VpnResourceKind.openVpnServer.collectionPath,
      '/api/v2/vpn/openvpn/servers',
    );
    expect(
      VpnResourceKind.openVpnClient.itemPath,
      '/api/v2/vpn/openvpn/client',
    );
    expect(
      VpnResourceKind.openVpnCso.collectionPath,
      '/api/v2/vpn/openvpn/csos',
    );
    expect(
      VpnResourceKind.openVpnExportConfig.itemPath,
      '/api/v2/vpn/openvpn/client_export/config',
    );
    expect(openVpnClientExportPath, '/api/v2/vpn/openvpn/client_export');
    expect(
      VpnResourceKind.ipsecPhase1.itemPath,
      '/api/v2/vpn/ipsec/phase1',
    );
    expect(VpnTechnology.ipsec.applyPath, '/api/v2/vpn/ipsec/apply');
    expect(
      VpnTechnology.wireGuard.settingsPath,
      '/api/v2/vpn/wireguard/settings',
    );
    expect(
      VpnResourceKind.wireGuardPeerAllowedIp.collectionPath,
      '/api/v2/vpn/wireguard/peer/allowed_ips',
    );
  });

  test('managed resources scrub secrets and runtime telemetry deeply', () {
    final source = <String, dynamic>{
      'id': 4,
      'descr': 'Site peer',
      'publickey': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'presharedkey': 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
      'runtime_status': 'up',
      'allowedips': [
        {'address': '10.0.0.0', 'mask': 24},
      ],
    };
    final resource = ManagedVpnResource(
      kind: VpnResourceKind.wireGuardPeer,
      raw: source,
    );

    source['descr'] = 'changed';
    (source['allowedips'] as List).clear();

    expect(resource.description, 'Site peer');
    expect(resource.raw, isNot(contains('presharedkey')));
    expect(resource.raw, isNot(contains('runtime_status')));
    expect(resource.raw['allowedips'], hasLength(1));
    expect(
      () => resource.raw['descr'] = 'mutated',
      throwsUnsupportedError,
    );
  });

  test('write payload preserves configuration but never replays secrets', () {
    final operation = PfRestOperationCapability(
      path: VpnResourceKind.wireGuardTunnel.itemPath,
      method: 'PATCH',
      requestFields: const {
        'body:id': PfRestFieldConstraint(
          name: 'id',
          location: 'body',
          required: true,
          type: 'integer',
        ),
        'body:enabled': PfRestFieldConstraint(
          name: 'enabled',
          location: 'body',
          required: false,
          type: 'boolean',
        ),
        'body:descr': PfRestFieldConstraint(
          name: 'descr',
          location: 'body',
          required: false,
          type: 'string',
        ),
        'body:privatekey': PfRestFieldConstraint(
          name: 'privatekey',
          location: 'body',
          required: true,
          type: 'string',
          writeOnly: true,
        ),
        'body:publickey': PfRestFieldConstraint(
          name: 'publickey',
          location: 'body',
          required: false,
          type: 'string',
          readOnly: true,
        ),
        'body:runtime_status': PfRestFieldConstraint(
          name: 'runtime_status',
          location: 'body',
          required: false,
          type: 'string',
        ),
      },
      tags: const {'VPN'},
    );

    final unchangedSecret = buildVpnWritePayload(
      operation: operation,
      existing: const {
        'id': 4,
        'enabled': true,
        'descr': 'Tunnel',
        'privatekey': 'must-not-replay',
        'publickey': 'generated',
        'runtime_status': 'up',
      },
      changes: const {'descr': 'Updated tunnel'},
      id: 4,
    );
    expect(unchangedSecret, {
      'id': 4,
      'enabled': true,
      'descr': 'Updated tunnel',
    });

    final replacementSecret = buildVpnWritePayload(
      operation: operation,
      existing: const {'id': 4, 'enabled': true, 'descr': 'Tunnel'},
      changes: const {'privatekey': 'replacement-key'},
      id: 4,
    );
    expect(replacementSecret, containsPair('privatekey', 'replacement-key'));
  });

  test('secret-name fallback covers VPN credential fields', () {
    for (final name in const [
      'tls',
      'privatekey',
      'presharedkey',
      'pre_shared_key',
      'proxy_passwd',
      'auth_pass',
      'admin_password',
      'client_secret',
    ]) {
      expect(isVpnSecretFieldName(name), isTrue, reason: name);
    }
    expect(isVpnSecretFieldName('publickey'), isFalse);
    expect(isVpnSecretFieldName('description'), isFalse);
  });

  test('relationship identifiers use pfREST runtime keys', () {
  final phase1 = ManagedVpnResource(
    kind: VpnResourceKind.ipsecPhase1,
    raw: const {'id': 5, 'ikeid': 20, 'descr': 'Branch IPsec'},
  );
  final tunnel = ManagedVpnResource(
    kind: VpnResourceKind.wireGuardTunnel,
    raw: const {'id': 4, 'name': 'tun_wg0', 'descr': 'Branch tunnel'},
  );
  final server = ManagedVpnResource(
    kind: VpnResourceKind.openVpnServer,
    raw: const {'id': 1, 'vpnid': 10, 'description': 'Remote access'},
  );

  expect(vpnRelationshipIdentifier(phase1, 'ikeid'), '20');
  expect(vpnRelationshipIdentifier(tunnel, 'tun'), 'tun_wg0');
  expect(vpnRelationshipIdentifier(server, 'server'), '10');
  expect(vpnRelationshipIdentifier(server, 'server_list'), '10');
});

  test('technology capabilities preserve apply asymmetry', () {
    final openVpnRead = PfRestOperationCapability(
      path: VpnResourceKind.openVpnServer.collectionPath,
      method: 'GET',
      requestFields: const {},
      tags: const {'VPN'},
    );
    final ipsecRead = PfRestOperationCapability(
      path: VpnResourceKind.ipsecPhase1.collectionPath,
      method: 'GET',
      requestFields: const {},
      tags: const {'VPN'},
    );
    final ipsecApply = PfRestOperationCapability(
      path: VpnTechnology.ipsec.applyPath!,
      method: 'POST',
      requestFields: const {},
      tags: const {'VPN'},
    );
    final snapshot = PfRestCapabilities(
      profileId: 'vpn-model-test',
      status: PfRestCapabilityStatus.available,
      operations: {
        PfRestCapabilities.operationKey(openVpnRead.path, openVpnRead.method):
            openVpnRead,
        PfRestCapabilities.operationKey(ipsecRead.path, ipsecRead.method):
            ipsecRead,
        PfRestCapabilities.operationKey(ipsecApply.path, ipsecApply.method):
            ipsecApply,
      },
      packageTags: const {'VPN'},
      loadedAt: DateTime.utc(2026, 7, 14),
    );
    final capabilities = VpnManagementCapabilities.from(snapshot);

    expect(
      capabilities.forTechnology(VpnTechnology.openVpn).canApply,
      isTrue,
    );
    expect(
      capabilities.forTechnology(VpnTechnology.ipsec).canApply,
      isTrue,
    );
    expect(
      capabilities.forTechnology(VpnTechnology.wireGuard).canApply,
      isFalse,
    );
  });
}
