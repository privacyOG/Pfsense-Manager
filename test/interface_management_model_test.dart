import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/interface_management.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';

void main() {
  test('only schema-reported interface resource types are readable', () {
    final capabilities = PfRestCapabilities(
      profileId: 'profile-1',
      status: PfRestCapabilityStatus.available,
      operations: {
        _key('/api/v2/interfaces', 'GET'):
            _operation('/api/v2/interfaces', 'GET'),
        _key('/api/v2/interface', 'PATCH'):
            _operation('/api/v2/interface', 'PATCH'),
        _key('/api/v2/interface/vlans', 'GET'):
            _operation('/api/v2/interface/vlans', 'GET'),
        _key('/api/v2/interface/vlan', 'POST'):
            _operation('/api/v2/interface/vlan', 'POST'),
        _key(interfaceApplyPath, 'POST'):
            _operation(interfaceApplyPath, 'POST'),
      },
      packageTags: const {'INTERFACE'},
      loadedAt: DateTime.utc(2026, 7, 13),
    );

    final management = InterfaceManagementCapabilities.from(capabilities);

    expect(management.readableKinds, [
      InterfaceResourceKind.assigned,
      InterfaceResourceKind.vlan,
    ]);
    expect(management.forKind(InterfaceResourceKind.assigned).canUpdate, isTrue);
    expect(management.forKind(InterfaceResourceKind.vlan).canCreate, isTrue);
    expect(management.forKind(InterfaceResourceKind.bridge).hasAnyOperation, isFalse);
    expect(management.canApply, isTrue);
  });

  test('assigned interface update preserves every unedited writable field', () {
    final operation = _operation(
      '/api/v2/interface',
      'PATCH',
      fields: {
        'id': _field('id'),
        'if': _field('if', required: true),
        'enable': _field('enable', type: 'boolean'),
        'descr': _field('descr', required: true),
        'typev4': _field('typev4'),
        'ipaddr': _field('ipaddr'),
        'subnet': _field('subnet', type: 'integer'),
        'gateway': _field('gateway'),
        'typev6': _field('typev6'),
        'ipaddrv6': _field('ipaddrv6'),
        'subnetv6': _field('subnetv6', type: 'integer'),
        'blockpriv': _field('blockpriv', type: 'boolean'),
        'advanced_future_field': _field('advanced_future_field'),
      },
    );
    final resource = ManagedInterfaceResource(
      kind: InterfaceResourceKind.assigned,
      raw: {
        'id': 'wan',
        'if': 'igc0',
        'enable': true,
        'descr': 'WAN',
        'typev4': 'static',
        'ipaddr': '192.0.2.10',
        'subnet': 24,
        'gateway': 'WAN_GW',
        'typev6': 'none',
        'ipaddrv6': 'none',
        'subnetv6': null,
        'blockpriv': true,
        'advanced_future_field': 'preserve-me',
        'response_only_field': 'must-not-be-written',
      },
    );

    final payload = resource.writablePayload(
      operation,
      changes: const {'descr': 'Internet uplink'},
      includeIdentifier: true,
    );

    expect(payload, {
      'id': 'wan',
      'if': 'igc0',
      'enable': true,
      'descr': 'Internet uplink',
      'typev4': 'static',
      'ipaddr': '192.0.2.10',
      'subnet': 24,
      'gateway': 'WAN_GW',
      'typev6': 'none',
      'ipaddrv6': 'none',
      'subnetv6': null,
      'blockpriv': true,
      'advanced_future_field': 'preserve-me',
    });
    expect(payload, isNot(contains('response_only_field')));
  });

  for (final scenario in <InterfaceResourceKind, Map<String, dynamic>>{
    InterfaceResourceKind.vlan: {
      'id': 2,
      'if': 'igc1',
      'tag': 30,
      'pcp': 1,
      'descr': 'Guests',
    },
    InterfaceResourceKind.bridge: {
      'id': 3,
      'members': ['igc1', 'igc2'],
      'descr': 'Internal bridge',
    },
    InterfaceResourceKind.lagg: {
      'id': 4,
      'members': ['igc2', 'igc3'],
      'laggproto': 'lacp',
      'descr': 'Core LAGG',
    },
    InterfaceResourceKind.gre: {
      'id': 5,
      'if': 'wan',
      'local': '192.0.2.10',
      'remote': '198.51.100.10',
      'descr': 'GRE site link',
    },
    InterfaceResourceKind.gif: {
      'id': 6,
      'if': 'wan',
      'local': '2001:db8::1',
      'remote': '2001:db8::2',
      'descr': 'GIF site link',
    },
  }.entries) {
    test('${scenario.key.name} payload is filtered by reported writable fields', () {
      final operation = _operation(
        scenario.key.itemPath,
        'PATCH',
        fields: {
          for (final name in scenario.value.keys) name: _field(name),
        },
      );
      final resource = ManagedInterfaceResource(
        kind: scenario.key,
        raw: {
          ...scenario.value,
          'runtime_status': 'up',
        },
      );

      final payload = resource.writablePayload(
        operation,
        changes: const {'descr': 'Updated description'},
        includeIdentifier: true,
      );

      expect(payload['id'], scenario.value['id']);
      expect(payload['descr'], 'Updated description');
      expect(payload, isNot(contains('runtime_status')));
      for (final name in scenario.value.keys) {
        if (name == 'descr') continue;
        expect(payload[name], scenario.value[name]);
      }
    });
  }

  test('available interface aliases parse without inventing assignment state', () {
    final available = AvailableInterface.fromJson({
      'interface': 'igc2',
      'description': 'Unused 2.5G port',
    });

    expect(available.name, 'igc2');
    expect(available.description, 'Unused 2.5G port');
    expect(available.assigned, isFalse);
  });
}

String _key(String path, String method) =>
    PfRestCapabilities.operationKey(path, method);

PfRestOperationCapability _operation(
  String path,
  String method, {
  Map<String, PfRestFieldConstraint> fields = const {},
}) {
  return PfRestOperationCapability(
    path: path,
    method: method,
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
}) {
  return PfRestFieldConstraint(
    name: name,
    location: 'body',
    required: required,
    type: type,
  );
}
