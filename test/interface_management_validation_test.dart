import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/interface_management.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/utils/interface_management_validation.dart';

void main() {
  group('assigned interface validation', () {
    final operation = _operation(
      InterfaceResourceKind.assigned.itemPath,
      fields: {
        'if': _field('if', required: true),
        'descr': _field('descr', required: true, maxLength: 128),
        'mtu': _field('mtu', type: 'integer', minimum: 1280, maximum: 8192),
        'typev4': _field(
          'typev4',
          required: true,
          allowedValues: const ['static', 'dhcp', 'pppoe', 'none'],
        ),
        'ipaddr': _field('ipaddr'),
        'subnet': _field('subnet', type: 'integer', minimum: 1, maximum: 32),
        'typev6': _field(
          'typev6',
          required: true,
          allowedValues: const ['static', 'dhcp6', 'slaac', 'track6', 'none'],
        ),
        'ipaddrv6': _field('ipaddrv6'),
        'subnetv6': _field(
          'subnetv6',
          type: 'integer',
          minimum: 1,
          maximum: 128,
        ),
        'track6_interface': _field('track6_interface'),
      },
    );

    test('accepts valid static IPv4 and IPv6 settings', () {
      final result = validateInterfaceValues(
        kind: InterfaceResourceKind.assigned,
        values: const {
          'if': 'igc1',
          'descr': 'LAN',
          'mtu': 1500,
          'typev4': 'static',
          'ipaddr': '192.168.7.1',
          'subnet': 24,
          'typev6': 'static',
          'ipaddrv6': '2001:db8:7::1',
          'subnetv6': 64,
        },
        operation: operation,
      );

      expect(result.isValid, isTrue, reason: result.summary);
    });

    test('rejects missing static addresses, invalid prefixes and MTU', () {
      final result = validateInterfaceValues(
        kind: InterfaceResourceKind.assigned,
        values: const {
          'if': 'igc1',
          'descr': 'LAN',
          'mtu': 9000,
          'typev4': 'static',
          'ipaddr': 'not-an-address',
          'subnet': 33,
          'typev6': 'static',
          'ipaddrv6': '192.0.2.1',
          'subnetv6': 129,
        },
        operation: operation,
      );

      expect(result.errorFor('mtu'), contains('outside'));
      expect(result.errorFor('ipaddr'), contains('valid static IPv4'));
      expect(result.errorFor('subnet'), contains('between 1 and 32'));
      expect(result.errorFor('ipaddrv6'), contains('valid static IPv6'));
      expect(result.errorFor('subnetv6'), contains('between 1 and 128'));
    });

    test('normalises mutually exclusive DHCP and dynamic IPv6 fields', () {
      final normalised = normaliseInterfaceValues(
        InterfaceResourceKind.assigned,
        const {
          'typev4': 'dhcp',
          'ipaddr': '192.0.2.10',
          'subnet': 24,
          'gateway': 'OLD_GW',
          'typev6': 'dhcp6',
          'ipaddrv6': '2001:db8::10',
          'subnetv6': 64,
          'gatewayv6': 'OLD_V6_GW',
        },
      );

      expect(normalised['ipaddr'], 'dhcp');
      expect(normalised['subnet'], isNull);
      expect(normalised['gateway'], isNull);
      expect(normalised['ipaddrv6'], 'dhcp6');
      expect(normalised['subnetv6'], isNull);
      expect(normalised['gatewayv6'], isNull);
    });

    test('requires an interface when IPv6 tracking is selected', () {
      final result = validateInterfaceValues(
        kind: InterfaceResourceKind.assigned,
        values: const {
          'if': 'igc1',
          'descr': 'LAN',
          'typev4': 'none',
          'typev6': 'track6',
          'track6_interface': '',
        },
        operation: operation,
      );

      expect(result.errorFor('track6_interface'), contains('required'));
    });
  });

  test('validates VLAN parent, tag and priority', () {
    final operation = _operation(
      InterfaceResourceKind.vlan.itemPath,
      fields: {
        'if': _field('if', required: true),
        'tag': _field('tag', required: true, type: 'integer'),
        'pcp': _field('pcp', type: 'integer'),
      },
    );

    final invalid = validateInterfaceValues(
      kind: InterfaceResourceKind.vlan,
      values: const {'if': '', 'tag': 4095, 'pcp': 8},
      operation: operation,
    );
    final valid = validateInterfaceValues(
      kind: InterfaceResourceKind.vlan,
      values: const {'if': 'igc1', 'tag': 4094, 'pcp': 7},
      operation: operation,
    );

    expect(invalid.errorFor('if'), contains('parent'));
    expect(invalid.errorFor('tag'), contains('1 and 4094'));
    expect(invalid.errorFor('pcp'), contains('0 and 7'));
    expect(valid.isValid, isTrue, reason: valid.summary);
  });

  for (final kind in const [
    InterfaceResourceKind.bridge,
    InterfaceResourceKind.lagg,
  ]) {
    test('${kind.name} requires unique member interfaces', () {
      final operation = _operation(
        kind.itemPath,
        fields: {'members': _field('members', type: 'array', required: true)},
      );
      final empty = validateInterfaceValues(
        kind: kind,
        values: const {'members': <String>[]},
        operation: operation,
      );
      final duplicate = validateInterfaceValues(
        kind: kind,
        values: const {'members': ['igc1', 'igc1']},
        operation: operation,
      );
      final valid = validateInterfaceValues(
        kind: kind,
        values: const {'members': ['igc1', 'igc2']},
        operation: operation,
      );

      expect(empty.errorFor('members'), contains('At least one'));
      expect(duplicate.errorFor('members'), contains('unique'));
      expect(valid.isValid, isTrue, reason: valid.summary);
    });
  }

  for (final kind in const [
    InterfaceResourceKind.gre,
    InterfaceResourceKind.gif,
  ]) {
    test('${kind.name} requires a parent and different tunnel endpoints', () {
      final operation = _operation(
        kind.itemPath,
        fields: {
          'if': _field('if', required: true),
          'local': _field('local', required: true),
          'remote': _field('remote', required: true),
        },
      );
      final invalid = validateInterfaceValues(
        kind: kind,
        values: const {
          'if': '',
          'local': '192.0.2.1',
          'remote': '192.0.2.1',
        },
        operation: operation,
      );
      final valid = validateInterfaceValues(
        kind: kind,
        values: const {
          'if': 'wan',
          'local': '192.0.2.1',
          'remote': '198.51.100.1',
        },
        operation: operation,
      );

      expect(invalid.errorFor('if'), contains('parent'));
      expect(invalid.errorFor('remote'), contains('different'));
      expect(valid.isValid, isTrue, reason: valid.summary);
    });
  }

  group('management path risk', () {
    final resource = ManagedInterfaceResource(
      kind: InterfaceResourceKind.assigned,
      raw: const {
        'id': 'lan',
        'if': 'igc1',
        'descr': 'LAN',
        'ipaddr': '192.168.7.1',
        'ipaddrv6': '2001:db8:7::1',
      },
    );

    test('detects the exact active IPv4 management address', () {
      final risk = interfaceChangeRisk(
        original: resource,
        changes: const {'ipaddr': '192.168.8.1'},
        profile: _profile('192.168.7.1'),
      );
      expect(risk, InterfaceChangeRisk.managementPath);
    });

    test('detects a bracketed active IPv6 management address', () {
      final risk = interfaceChangeRisk(
        original: resource,
        changes: const {'enable': false},
        profile: _profile('[2001:db8:7::1]'),
      );
      expect(risk, InterfaceChangeRisk.managementPath);
    });

    test('does not use substring matching for management addresses', () {
      final risk = interfaceChangeRisk(
        original: resource,
        changes: const {'mtu': 1400},
        profile: _profile('192.168.7.10'),
      );
      expect(risk, InterfaceChangeRisk.connectivity);
    });

    test('description-only edits do not trigger connectivity warnings', () {
      final risk = interfaceChangeRisk(
        original: resource,
        changes: const {'descr': 'Trusted LAN'},
        profile: _profile('192.168.7.1'),
      );
      expect(risk, InterfaceChangeRisk.none);
    });
  });
}

PfSenseProfile _profile(String host) {
  return PfSenseProfile(
    id: 'profile-1',
    name: 'Firewall',
    host: host,
    username: 'api-user',
    apiKey: 'test-key',
  );
}

PfRestOperationCapability _operation(
  String path, {
  required Map<String, PfRestFieldConstraint> fields,
}) {
  return PfRestOperationCapability(
    path: path,
    method: 'PATCH',
    requestFields: {
      for (final entry in fields.entries) 'body:${entry.key}': entry.value,
    },
    tags: const {'INTERFACE'},
  );
}

PfRestFieldConstraint _field(
  String name, {
  String type = 'string',
  bool required = false,
  num? minimum,
  num? maximum,
  int? maxLength,
  List<Object?> allowedValues = const [],
}) {
  return PfRestFieldConstraint(
    name: name,
    location: 'body',
    required: required,
    type: type,
    minimum: minimum,
    maximum: maximum,
    maxLength: maxLength,
    allowedValues: allowedValues,
  );
}
