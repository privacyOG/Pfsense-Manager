import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/models/routing_management.dart';
import 'package:pfsense_manager/utils/routing_management_validation.dart';

void main() {
  test('gateway validation enforces address family and threshold ordering', () {
    final result = validateRoutingValues(
      kind: RoutingResourceKind.gateway,
      values: const {
        'name': 'WAN_DHCP',
        'ipprotocol': 'inet',
        'interface': 'wan',
        'gateway': '2001:db8::1',
        'monitor_disable': false,
        'monitor': '2001:4860:4860::8888',
        'latencylow': 500,
        'latencyhigh': 200,
        'losslow': 30,
        'losshigh': 20,
      },
      operation: _operation(
        requiredFields: const ['name', 'ipprotocol', 'interface', 'gateway'],
      ),
    );

    expect(result.errors['gateway'], contains('IPv4'));
    expect(result.errors['monitor'], contains('IPv4'));
    expect(result.errors['latencyhigh'], contains('greater'));
    expect(result.errors['losshigh'], contains('greater'));
  });

  test('gateway group validation rejects duplicate and mixed-family members', () {
    final duplicate = validateRoutingValues(
      kind: RoutingResourceKind.gatewayGroup,
      values: const {
        'name': 'FAILOVER',
        'trigger': 'down',
        'priorities': [
          {'gateway': 'WAN4', 'tier': 1, 'virtual_ip': 'address'},
          {'gateway': 'WAN4', 'tier': 2, 'virtual_ip': 'address'},
        ],
      },
      operation: _operation(
        requiredFields: const ['name', 'priorities'],
      ),
      gatewayFamilies: const {'WAN4': 'inet'},
    );
    expect(duplicate.errors['priorities'], contains('only once'));

    final mixed = validateRoutingValues(
      kind: RoutingResourceKind.gatewayGroup,
      values: const {
        'name': 'MIXED',
        'trigger': 'downloss',
        'priorities': [
          {'gateway': 'WAN4', 'tier': 1, 'virtual_ip': 'address'},
          {'gateway': 'WAN6', 'tier': 2, 'virtual_ip': 'address'},
        ],
      },
      operation: _operation(
        requiredFields: const ['name', 'priorities'],
      ),
      gatewayFamilies: const {'WAN4': 'inet', 'WAN6': 'inet6'},
    );
    expect(mixed.errors['priorities'], contains('same IP version'));
  });

  test('static route validation matches network and gateway families', () {
    final result = validateRoutingValues(
      kind: RoutingResourceKind.staticRoute,
      values: const {
        'network': '10.20.0.0/16',
        'gateway': 'WAN6',
        'disabled': false,
      },
      operation: _operation(
        requiredFields: const ['network', 'gateway'],
      ),
      gatewayFamilies: const {'WAN6': 'inet6'},
    );

    expect(result.errors['gateway'], contains('match'));
  });

  test('default gateway validation rejects the wrong IP family', () {
    final result = validateDefaultGatewayValues(
      values: const {
        'defaultgw4': 'WAN6',
        'defaultgw6': 'WAN6',
      },
      operation: _operation(
        requiredFields: const [],
        fields: const ['defaultgw4', 'defaultgw6'],
      ),
      gatewayFamilies: const {'WAN6': 'inet6'},
    );

    expect(result.errors['defaultgw4'], contains('IPv4'));
    expect(result.errors, isNot(contains('defaultgw6')));
  });

  test('normalisation trims strings and parses gateway numeric settings', () {
    final values = normaliseRoutingValues(
      RoutingResourceKind.gateway,
      const {
        'name': ' WAN_DHCP ',
        'weight': '4',
        'priorities': [
          {'gateway': ' WAN_DHCP ', 'tier': 1},
        ],
      },
    );

    expect(values['name'], 'WAN_DHCP');
    expect(values['weight'], 4);
    expect((values['priorities'] as List).single['gateway'], 'WAN_DHCP');
  });
}

PfRestOperationCapability _operation({
  required List<String> requiredFields,
  List<String>? fields,
}) {
  final names = fields ?? requiredFields;
  return PfRestOperationCapability(
    path: '/api/v2/routing/test',
    method: 'POST',
    requestFields: {
      for (final name in names)
        'body:$name': PfRestFieldConstraint(
          name: name,
          location: 'body',
          required: requiredFields.contains(name),
          type: name == 'priorities' ? 'array' : 'string',
        ),
    },
    tags: const {'ROUTING'},
  );
}
