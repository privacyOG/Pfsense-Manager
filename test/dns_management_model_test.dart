import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dns_management.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';

void main() {
  test('DNS resource paths match the pfREST contract', () {
    expect(dnsResolverSettingsPath, '/api/v2/services/dns_resolver/settings');
    expect(
      DnsServiceKind.resolver.applyPath,
      '/api/v2/services/dns_resolver/apply',
    );
    expect(
      DnsServiceKind.forwarder.applyPath,
      '/api/v2/services/dns_forwarder/apply',
    );
    expect(
      DnsResourceKind.resolverDomainOverride.collectionPath,
      '/api/v2/services/dns_resolver/domain_overrides',
    );
    expect(
      DnsResourceKind.resolverHostAlias.itemPath,
      '/api/v2/services/dns_resolver/host_override/alias',
    );
    expect(
      DnsResourceKind.resolverAccessListNetwork.collectionPath,
      '/api/v2/services/dns_resolver/access_list/networks',
    );
    expect(
      DnsResourceKind.forwarderHostOverride.collectionPath,
      '/api/v2/services/dns_forwarder/host_overrides',
    );
  });

  test('DNS resource data is deeply copied and exposed read-only', () {
    final source = <String, dynamic>{
      'id': 3,
      'host': 'router',
      'domain': 'example.test',
      'ip': ['192.168.1.1'],
      'aliases': [
        {'host': 'gateway', 'domain': 'example.test'},
      ],
    };
    final resource = ManagedDnsResource(
      kind: DnsResourceKind.resolverHostOverride,
      raw: source,
    );

    source['host'] = 'changed';
    (source['ip'] as List).clear();
    (source['aliases'] as List).clear();

    expect(resource.displayName, 'router.example.test');
    expect(resource.ip, '192.168.1.1');
    expect((resource.raw['aliases'] as List), hasLength(1));
    expect(
      () => resource.raw['host'] = 'mutated',
      throwsUnsupportedError,
    );
  });

  test('write payload preserves schema-reported unedited fields', () {
    final operation = PfRestOperationCapability(
      path: DnsResourceKind.resolverHostOverride.itemPath,
      method: 'PATCH',
      requestFields: {
        for (final name in const [
          'id',
          'host',
          'domain',
          'ip',
          'descr',
          'future_setting',
        ])
          'body:$name': PfRestFieldConstraint(
            name: name,
            location: 'body',
            required: name == 'id',
            type: name == 'ip' ? 'array' : 'string',
          ),
      },
      tags: const {'SERVICES'},
    );
    final resource = ManagedDnsResource(
      kind: DnsResourceKind.resolverHostOverride,
      raw: const {
        'id': 2,
        'host': 'router',
        'domain': 'example.test',
        'ip': ['192.168.1.1'],
        'descr': 'Gateway',
        'future_setting': 'preserve-me',
        'runtime_status': 'active',
      },
    );

    final payload = resource.writablePayload(
      operation,
      changes: const {'descr': 'Main gateway'},
      includeIdentifiers: true,
    );

    expect(payload, {
      'id': 2,
      'host': 'router',
      'domain': 'example.test',
      'ip': ['192.168.1.1'],
      'descr': 'Main gateway',
      'future_setting': 'preserve-me',
    });
    expect(payload, isNot(contains('runtime_status')));
  });

  test('child identifiers follow body and query schema locations', () {
    final alias = ManagedDnsResource(
      kind: DnsResourceKind.resolverHostAlias,
      raw: const {
        'id': 5,
        'parent_id': 2,
        'host': 'gateway',
        'domain': 'example.test',
      },
    );
    final patch = PfRestOperationCapability(
      path: DnsResourceKind.resolverHostAlias.itemPath,
      method: 'PATCH',
      requestFields: {
        for (final name in const ['id', 'parent_id', 'host', 'domain'])
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
      path: DnsResourceKind.resolverHostAlias.itemPath,
      method: 'DELETE',
      requestFields: {
        for (final name in const ['id', 'parent_id'])
          'query:$name': PfRestFieldConstraint(
            name: name,
            location: 'query',
            required: true,
            type: 'integer',
          ),
      },
      tags: const {'SERVICES'},
    );

    expect(
      alias.writablePayload(patch, includeIdentifiers: true),
      {
        'id': 5,
        'parent_id': 2,
        'host': 'gateway',
        'domain': 'example.test',
      },
    );
    expect(alias.identifierQuery(delete), {'parent_id': '2', 'id': '5'});
  });

  test('capabilities preserve resolver and forwarder asymmetry', () {
    final settingsRead = PfRestOperationCapability(
      path: dnsResolverSettingsPath,
      method: 'GET',
      requestFields: const {},
      tags: const {'SERVICES'},
    );
    final forwarderRead = PfRestOperationCapability(
      path: DnsResourceKind.forwarderHostOverride.collectionPath,
      method: 'GET',
      requestFields: const {},
      tags: const {'SERVICES'},
    );
    final forwarderApply = PfRestOperationCapability(
      path: DnsServiceKind.forwarder.applyPath,
      method: 'POST',
      requestFields: const {},
      tags: const {'SERVICES'},
    );
    final capabilities = PfRestCapabilities(
      profileId: 'dns-model-test',
      status: PfRestCapabilityStatus.available,
      operations: {
        PfRestCapabilities.operationKey(
          settingsRead.path,
          settingsRead.method,
        ): settingsRead,
        PfRestCapabilities.operationKey(
          forwarderRead.path,
          forwarderRead.method,
        ): forwarderRead,
        PfRestCapabilities.operationKey(
          forwarderApply.path,
          forwarderApply.method,
        ): forwarderApply,
      },
      packageTags: const {'SERVICES'},
      loadedAt: DateTime.utc(2026, 7, 14),
    );
    final dns = DnsManagementCapabilities.from(capabilities);

    expect(dns.canReadSettings, isTrue);
    expect(dns.settingsUpdate, isNull);
    expect(
      dns.forService(DnsServiceKind.forwarder).resources,
      [DnsResourceKind.forwarderHostOverride],
    );
    expect(dns.forService(DnsServiceKind.forwarder).canApply, isTrue);
  });
}
