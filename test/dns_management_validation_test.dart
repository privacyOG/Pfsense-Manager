import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dns_management.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/utils/dns_management_validation.dart';

void main() {
  test('Resolver settings validate ports TLS Python and strict outgoing mode', () {
    final result = validateResolverSettings(
      values: const {
        'enable': true,
        'port': 70000,
        'enablessl': true,
        'sslcertref': '',
        'tlsport': 0,
        'python': true,
        'python_script': '',
        'strictout': true,
        'outgoing_interface': <String>[],
      },
      operation: _operation(
        fields: const [
          'enable',
          'port',
          'enablessl',
          'sslcertref',
          'tlsport',
          'python',
          'python_script',
          'strictout',
          'outgoing_interface',
        ],
      ),
    );

    expect(result.errors['port'], contains('65535'));
    expect(result.errors['sslcertref'], contains('certificate'));
    expect(result.errors['tlsport'], contains('65535'));
    expect(result.errors['python_script'], contains('Python'));
    expect(result.errors['outgoing_interface'], contains('outgoing'));
  });

  test('Resolver host overrides validate addresses and duplicates', () {
    final existing = ManagedDnsResource(
      kind: DnsResourceKind.resolverHostOverride,
      raw: const {
        'id': 1,
        'host': 'router',
        'domain': 'example.test',
        'ip': ['192.168.1.1'],
      },
    );
    final result = validateDnsResource(
      kind: DnsResourceKind.resolverHostOverride,
      values: const {
        'host': 'router',
        'domain': 'example.test',
        'ip': ['not-an-address'],
        'aliases': [
          {'host': 'gateway', 'domain': 'example.test'},
          {'host': 'gateway', 'domain': 'example.test'},
        ],
      },
      operation: _operation(
        fields: const ['host', 'domain', 'ip', 'aliases'],
        requiredFields: const ['domain', 'ip'],
      ),
      context: DnsValidationContext(resources: [existing]),
    );

    expect(result.errors['host'], contains('already'));
    expect(result.errors['ip'], contains('valid'));
    expect(result.errors['aliases'], contains('only once'));
  });

  test('Forwarder host overrides accept only one address', () {
    final result = validateDnsResource(
      kind: DnsResourceKind.forwarderHostOverride,
      values: const {
        'host': 'router',
        'domain': 'example.test',
        'ip': ['192.168.1.1', '192.168.1.2'],
      },
      operation: _operation(
        fields: const ['host', 'domain', 'ip'],
        requiredFields: const ['host', 'domain', 'ip'],
      ),
    );

    expect(result.errors['ip'], contains('one IP address'));
  });

  test('Domain override TLS requires an upstream hostname', () {
    final result = validateDnsResource(
      kind: DnsResourceKind.resolverDomainOverride,
      values: const {
        'domain': 'corp.example',
        'ip': '192.0.2.53',
        'forward_tls_upstream': true,
        'tls_hostname': '',
      },
      operation: _operation(
        fields: const [
          'domain',
          'ip',
          'forward_tls_upstream',
          'tls_hostname',
        ],
        requiredFields: const ['domain', 'ip'],
      ),
    );

    expect(result.errors['tls_hostname'], contains('TLS hostname'));
  });

  test('Access lists validate actions unique networks and prefix lengths', () {
    final result = validateDnsResource(
      kind: DnsResourceKind.resolverAccessList,
      values: const {
        'name': 'clients',
        'action': 'unsupported',
        'networks': [
          {'network': '192.168.1.0', 'mask': 33},
          {'network': '192.168.1.0', 'mask': 33},
        ],
      },
      operation: _operation(
        fields: const ['name', 'action', 'networks'],
        requiredFields: const ['name', 'action', 'networks'],
      ),
    );

    expect(result.errors['action'], contains('supported'));
    expect(result.errors['networks'], contains('between 0 and 32'));
  });

  test('Child alias and network resources require valid parents', () {
    final alias = validateDnsResource(
      kind: DnsResourceKind.resolverHostAlias,
      values: const {
        'parent_id': '',
        'host': 'gateway',
        'domain': 'example.test',
      },
      operation: _operation(
        fields: const ['parent_id', 'host', 'domain'],
        requiredFields: const ['parent_id', 'host', 'domain'],
      ),
    );
    final network = validateDnsResource(
      kind: DnsResourceKind.resolverAccessListNetwork,
      values: const {
        'parent_id': '',
        'network': '2001:db8::',
        'mask': 129,
      },
      operation: _operation(
        fields: const ['parent_id', 'network', 'mask'],
        requiredFields: const ['parent_id', 'network', 'mask'],
      ),
    );

    expect(alias.errors['parent_id'], contains('parent'));
    expect(network.errors['parent_id'], contains('parent'));
    expect(network.errors['mask'], contains('128'));
  });

  test('DNS normalisation trims nested data and parses numeric settings', () {
    final values = normaliseDnsValues(
      const {
        'host': ' router ',
        'port': '53',
        'aliases': [
          {'host': ' gateway ', 'domain': ' example.test '},
        ],
      },
    );

    expect(values['host'], 'router');
    expect(values['port'], 53);
    expect((values['aliases'] as List).single, {
      'host': 'gateway',
      'domain': 'example.test',
    });
  });
}

PfRestOperationCapability _operation({
  required List<String> fields,
  List<String> requiredFields = const [],
}) {
  return PfRestOperationCapability(
    path: '/api/v2/services/dns_test',
    method: 'PATCH',
    requestFields: {
      for (final name in fields)
        'body:$name': PfRestFieldConstraint(
          name: name,
          location: 'body',
          required: requiredFields.contains(name),
          type: name == 'enable' ||
                  name == 'enablessl' ||
                  name == 'python' ||
                  name == 'strictout' ||
                  name == 'forward_tls_upstream'
              ? 'boolean'
              : name == 'port' || name == 'tlsport' || name == 'mask'
                  ? 'integer'
                  : name == 'ip' ||
                          name == 'aliases' ||
                          name == 'networks' ||
                          name == 'outgoing_interface'
                      ? 'array'
                      : 'string',
        ),
    },
    tags: const {'SERVICES'},
  );
}
