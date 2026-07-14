import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dhcp_management.dart';
import 'package:pfsense_manager/models/interface_management.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/utils/dhcp_management_validation.dart';

void main() {
  final interface = ManagedInterfaceResource(
    kind: InterfaceResourceKind.assigned,
    raw: const {
      'id': 'lan',
      'if': 'igc0',
      'descr': 'LAN',
      'typev4': 'static',
      'ipaddr': '192.168.1.1',
      'subnet': 24,
    },
  );
  final server = ManagedDhcpResource(
    kind: DhcpResourceKind.server,
    raw: const {
      'id': 'lan',
      'enable': true,
      'range_from': '192.168.1.10',
      'range_to': '192.168.1.100',
      'defaultleasetime': 7200,
      'maxleasetime': 86400,
    },
  );

  test('server validation enforces static interface, subnet and lease order', () {
    final dynamicInterface = ManagedInterfaceResource(
      kind: InterfaceResourceKind.assigned,
      raw: const {
        'id': 'wan',
        'typev4': 'dhcp',
        'ipaddr': '192.0.2.10',
        'subnet': 24,
      },
    );
    final result = validateDhcpResourceValues(
      kind: DhcpResourceKind.server,
      values: const {
        'id': 'wan',
        'enable': true,
        'range_from': '198.51.100.10',
        'range_to': '198.51.100.20',
        'defaultleasetime': 9000,
        'maxleasetime': 8000,
      },
      operation: _operation(
        fields: const ['id', 'enable', 'range_from', 'range_to'],
        requiredFields: const ['id'],
      ),
      context: DhcpValidationContext(interfaces: [dynamicInterface]),
    );

    expect(result.errors['enable'], contains('static IPv4'));
    expect(result.errors['range_from'], contains('subnet'));
    expect(result.errors['range_to'], contains('subnet'));
    expect(result.errors['maxleasetime'], contains('less'));
  });

  test('server validation rejects relay conflict and mapped address overlap', () {
    final mapping = ManagedDhcpResource(
      kind: DhcpResourceKind.staticMapping,
      raw: const {
        'id': 1,
        'parent_id': 'lan',
        'mac': '11:22:33:44:55:66',
        'ipaddr': '192.168.1.50',
      },
    );
    final result = validateDhcpResourceValues(
      kind: DhcpResourceKind.server,
      values: const {
        'id': 'lan',
        'enable': true,
        'range_from': '192.168.1.20',
        'range_to': '192.168.1.60',
      },
      operation: _operation(
        fields: const ['id', 'enable', 'range_from', 'range_to'],
        requiredFields: const ['id'],
      ),
      context: DhcpValidationContext(
        interfaces: [interface],
        staticMappings: [mapping],
        relayEnabled: true,
      ),
    );

    expect(result.errors['enable'], contains('relay'));
    expect(result.errors['range_from'], contains('static mapping'));
  });

  test('static mapping validation rejects pool, subnet and duplicate conflicts', () {
    final existing = ManagedDhcpResource(
      kind: DhcpResourceKind.staticMapping,
      raw: const {
        'id': 2,
        'parent_id': 'lan',
        'mac': '11:22:33:44:55:66',
        'ipaddr': '192.168.1.150',
      },
    );
    final pool = ManagedDhcpResource(
      kind: DhcpResourceKind.addressPool,
      raw: const {
        'id': 1,
        'parent_id': 'lan',
        'range_from': '192.168.1.140',
        'range_to': '192.168.1.160',
      },
    );
    final result = validateDhcpResourceValues(
      kind: DhcpResourceKind.staticMapping,
      values: const {
        'parent_id': 'lan',
        'mac': '11:22:33:44:55:66',
        'ipaddr': '192.168.1.150',
        'hostname': 'client-one',
      },
      operation: _operation(
        fields: const ['parent_id', 'mac', 'ipaddr', 'hostname'],
        requiredFields: const ['parent_id', 'mac'],
      ),
      context: DhcpValidationContext(
        interfaces: [interface],
        servers: [server],
        staticMappings: [existing],
        addressPools: [pool],
      ),
    );

    expect(result.errors['mac'], contains('already'));
    expect(result.errors['ipaddr'], anyOf(contains('pool'), contains('mapped')));
  });

  test('additional pool validation rejects overlap with the primary range', () {
    final result = validateDhcpResourceValues(
      kind: DhcpResourceKind.addressPool,
      values: const {
        'parent_id': 'lan',
        'range_from': '192.168.1.80',
        'range_to': '192.168.1.120',
      },
      operation: _operation(
        fields: const ['parent_id', 'range_from', 'range_to'],
        requiredFields: const ['parent_id', 'range_from', 'range_to'],
      ),
      context: DhcpValidationContext(
        interfaces: [interface],
        servers: [server],
      ),
    );

    expect(result.errors['range_from'], contains('primary'));
  });

  test('relay validation enforces mutual exclusion and IPv4 destinations', () {
    final result = validateDhcpRelayValues(
      values: const {
        'enable': true,
        'interface': ['lan'],
        'server': ['2001:db8::1'],
      },
      operation: _operation(
        fields: const ['enable', 'interface', 'server'],
        requiredFields: const ['server'],
      ),
      servers: [server],
      interfaces: [interface],
    );

    expect(result.errors['enable'], contains('Disable'));
    expect(result.errors['server'], contains('IPv4'));
  });

  test('backend validation follows schema choices', () {
    final operation = PfRestOperationCapability(
      path: dhcpBackendPath,
      method: 'PATCH',
      requestFields: const {
        'body:dhcpbackend': PfRestFieldConstraint(
          name: 'dhcpbackend',
          location: 'body',
          required: true,
          type: 'string',
          allowedValues: ['isc', 'kea'],
        ),
      },
      tags: const {'SERVICES'},
    );

    expect(
      validateDhcpBackendValue(backend: 'kea', operation: operation).isValid,
      isTrue,
    );
    expect(
      validateDhcpBackendValue(backend: 'other', operation: operation)
          .errors['dhcpbackend'],
      contains('not supported'),
    );
  });

  test('normalisation trims lists and parses lease times', () {
    final values = normaliseDhcpValues(
      DhcpResourceKind.server,
      const {
        'id': ' lan ',
        'dnsserver': [' 1.1.1.1 ', ''],
        'defaultleasetime': '7200',
      },
    );

    expect(values['id'], 'lan');
    expect(values['dnsserver'], ['1.1.1.1']);
    expect(values['defaultleasetime'], 7200);
  });
}

PfRestOperationCapability _operation({
  required List<String> fields,
  required List<String> requiredFields,
}) {
  return PfRestOperationCapability(
    path: '/api/v2/services/dhcp_test',
    method: 'PATCH',
    requestFields: {
      for (final name in fields)
        'body:$name': PfRestFieldConstraint(
          name: name,
          location: 'body',
          required: requiredFields.contains(name),
          type: name == 'enable'
              ? 'boolean'
              : name == 'interface' || name == 'server'
                  ? 'array'
                  : 'string',
        ),
    },
    tags: const {'SERVICES'},
  );
}
