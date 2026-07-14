import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dhcp_management.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';

void main() {
  test('DHCP resource paths match the pfREST contract', () {
    expect(
      DhcpResourceKind.server.collectionPath,
      '/api/v2/services/dhcp_servers',
    );
    expect(
      DhcpResourceKind.staticMapping.itemPath,
      '/api/v2/services/dhcp_server/static_mapping',
    );
    expect(
      DhcpResourceKind.addressPool.collectionPath,
      '/api/v2/services/dhcp_server/address_pools',
    );
    expect(dhcpRelayPath, '/api/v2/services/dhcp_relay');
    expect(dhcpBackendPath, '/api/v2/services/dhcp_server/backend');
    expect(dhcpApplyPath, '/api/v2/services/dhcp_server/apply');
  });

  test('resource data is deeply copied and exposed read-only', () {
    final source = <String, dynamic>{
      'id': 3,
      'parent_id': 'lan',
      'mac': '11:22:33:44:55:66',
      'ipaddr': '192.168.1.20',
      'dnsserver': ['1.1.1.1'],
    };
    final resource = ManagedDhcpResource(
      kind: DhcpResourceKind.staticMapping,
      raw: source,
    );

    source['mac'] = '00:00:00:00:00:00';
    (source['dnsserver'] as List).clear();

    expect(resource.macAddress, '11:22:33:44:55:66');
    expect(resource.parentId, 'lan');
    expect(resource.raw['dnsserver'], ['1.1.1.1']);
    expect(
      () => resource.raw['hostname'] = 'changed',
      throwsUnsupportedError,
    );
  });

  test('write payload preserves schema-reported unedited fields', () {
    final operation = PfRestOperationCapability(
      path: DhcpResourceKind.server.itemPath,
      method: 'PATCH',
      requestFields: {
        for (final name in const [
          'id',
          'enable',
          'range_from',
          'range_to',
          'domain',
          'future_setting',
        ])
          'body:$name': PfRestFieldConstraint(
            name: name,
            location: 'body',
            required: name == 'id',
            type: name == 'enable' ? 'boolean' : 'string',
          ),
      },
      tags: const {'SERVICES'},
    );
    final server = ManagedDhcpResource(
      kind: DhcpResourceKind.server,
      raw: const {
        'id': 'lan',
        'enable': true,
        'range_from': '192.168.1.10',
        'range_to': '192.168.1.100',
        'domain': 'example.test',
        'future_setting': 'preserve-me',
        'runtime_status': 'running',
      },
    );

    final payload = server.writablePayload(
      operation,
      changes: const {'domain': 'internal.test'},
      includeIdentifiers: true,
    );

    expect(payload, {
      'id': 'lan',
      'enable': true,
      'range_from': '192.168.1.10',
      'range_to': '192.168.1.100',
      'domain': 'internal.test',
      'future_setting': 'preserve-me',
    });
    expect(payload, isNot(contains('runtime_status')));
  });

  test('child identifiers follow schema-reported body and query locations', () {
    final mapping = ManagedDhcpResource(
      kind: DhcpResourceKind.staticMapping,
      raw: const {
        'id': 7,
        'parent_id': 'lan',
        'mac': '11:22:33:44:55:66',
      },
    );
    final patch = PfRestOperationCapability(
      path: DhcpResourceKind.staticMapping.itemPath,
      method: 'PATCH',
      requestFields: {
        for (final name in const ['id', 'parent_id', 'mac'])
          'body:$name': PfRestFieldConstraint(
            name: name,
            location: 'body',
            required: true,
            type: 'string',
          ),
      },
      tags: const {'SERVICES'},
    );
    final delete = PfRestOperationCapability(
      path: DhcpResourceKind.staticMapping.itemPath,
      method: 'DELETE',
      requestFields: {
        for (final name in const ['id', 'parent_id'])
          'query:$name': PfRestFieldConstraint(
            name: name,
            location: 'query',
            required: true,
            type: 'string',
          ),
      },
      tags: const {'SERVICES'},
    );

    expect(
      mapping.writablePayload(patch, includeIdentifiers: true),
      {
        'id': 7,
        'parent_id': 'lan',
        'mac': '11:22:33:44:55:66',
      },
    );
    expect(mapping.identifierQuery(delete), {'parent_id': 'lan', 'id': '7'});
  });
}
