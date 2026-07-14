import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/models/routing_management.dart';

void main() {
  test('routing resource paths match the pfREST routing contract', () {
    expect(
      RoutingResourceKind.gateway.collectionPath,
      '/api/v2/routing/gateways',
    );
    expect(
      RoutingResourceKind.gatewayGroup.itemPath,
      '/api/v2/routing/gateway/group',
    );
    expect(
      RoutingResourceKind.staticRoute.collectionPath,
      '/api/v2/routing/static_routes',
    );
    expect(routingDefaultGatewayPath, '/api/v2/routing/gateway/default');
    expect(routingApplyPath, '/api/v2/routing/apply');
  });

  test('gateway groups expose immutable priority references', () {
    final source = <String, dynamic>{
      'id': 4,
      'name': 'FAILOVER',
      'trigger': 'downloss',
      'priorities': [
        {'gateway': 'WAN_DHCP', 'tier': 1, 'virtual_ip': 'address'},
        {'gateway': 'WAN_BACKUP', 'tier': 2, 'virtual_ip': 'address'},
      ],
    };
    final group = ManagedRoutingResource(
      kind: RoutingResourceKind.gatewayGroup,
      raw: source,
    );

    source['name'] = 'changed';
    (source['priorities'] as List).clear();

    expect(group.displayName, 'FAILOVER');
    expect(group.referencedGateways, {'WAN_DHCP', 'WAN_BACKUP'});
    expect(group.summary, contains('2 gateways'));
    expect(
      () => group.raw['name'] = 'mutated',
      throwsUnsupportedError,
    );
  });

  test('write payload keeps schema-reported fields and omits runtime data', () {
    final operation = PfRestOperationCapability(
      path: RoutingResourceKind.gateway.itemPath,
      method: 'PATCH',
      requestFields: {
        for (final name in const [
          'id',
          'name',
          'descr',
          'gateway',
          'future_setting',
        ])
          'body:$name': PfRestFieldConstraint(
            name: name,
            location: 'body',
            required: false,
            type: 'string',
          ),
      },
      tags: const {'ROUTING'},
    );
    final gateway = ManagedRoutingResource(
      kind: RoutingResourceKind.gateway,
      raw: const {
        'id': 2,
        'name': 'WAN_DHCP',
        'descr': 'Primary WAN',
        'gateway': 'dynamic',
        'future_setting': 'preserve-me',
        'runtime_status': 'online',
      },
    );

    final payload = gateway.writablePayload(
      operation,
      changes: const {'descr': 'Internet uplink'},
      includeIdentifier: true,
    );

    expect(payload, {
      'id': 2,
      'name': 'WAN_DHCP',
      'descr': 'Internet uplink',
      'gateway': 'dynamic',
      'future_setting': 'preserve-me',
    });
    expect(payload, isNot(contains('runtime_status')));
  });

  test('dependency report lists all blocking references', () {
    final report = GatewayDependencyReport(
      gatewayGroups: const ['FAILOVER'],
      staticRoutes: const ['10.20.0.0/16'],
      firewallRules: const ['Send guests over WAN'],
      defaultAssignments: const ['IPv4'],
    );

    expect(report.hasDependencies, isTrue);
    expect(report.complete, isTrue);
    expect(report.descriptions, [
      'Gateway group: FAILOVER',
      'Static route: 10.20.0.0/16',
      'Firewall rule: Send guests over WAN',
      'Default gateway: IPv4',
    ]);
  });
}
