import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_alias.dart';
import 'package:pfsense_manager/utils/firewall_alias_validation.dart';

void main() {
  const hostAlias = FirewallAlias(
    id: 1,
    name: 'KNOWN_HOSTS',
    type: 'host',
    entries: [FirewallAliasEntry(value: '192.0.2.1')],
  );
  const networkAlias = FirewallAlias(
    id: 2,
    name: 'KNOWN_NETWORKS',
    type: 'network',
    entries: [FirewallAliasEntry(value: '198.51.100.0/24')],
  );
  const portAlias = FirewallAlias(
    id: 3,
    name: 'KNOWN_PORTS',
    type: 'port',
    entries: [FirewallAliasEntry(value: '443')],
  );
  const existing = [hostAlias, networkAlias, portAlias];

  test('accepts host IPs, FQDNs and non-port nested aliases', () {
    const alias = FirewallAlias(
      name: 'WEB_HOSTS',
      type: 'host',
      entries: [
        FirewallAliasEntry(value: '203.0.113.10'),
        FirewallAliasEntry(value: '2001:db8::10'),
        FirewallAliasEntry(value: 'www.example.test'),
        FirewallAliasEntry(value: 'KNOWN_NETWORKS'),
      ],
    );

    expect(
      validateFirewallAlias(alias, existingAliases: existing).isValid,
      isTrue,
    );
  });

  test('accepts network CIDRs, FQDNs and non-port nested aliases', () {
    const alias = FirewallAlias(
      name: 'SITE_NETWORKS',
      type: 'network',
      entries: [
        FirewallAliasEntry(value: '203.0.113.0/24'),
        FirewallAliasEntry(value: '2001:db8::/64'),
        FirewallAliasEntry(value: 'branch.example.test'),
        FirewallAliasEntry(value: 'KNOWN_HOSTS'),
      ],
    );

    expect(
      validateFirewallAlias(alias, existingAliases: existing).isValid,
      isTrue,
    );
  });

  test('accepts ports, ascending ranges and port aliases', () {
    const alias = FirewallAlias(
      name: 'SERVICE_PORTS',
      type: 'port',
      entries: [
        FirewallAliasEntry(value: '22'),
        FirewallAliasEntry(value: '8000-8080'),
        FirewallAliasEntry(value: '8443:8444'),
        FirewallAliasEntry(value: 'KNOWN_PORTS'),
      ],
    );

    expect(
      validateFirewallAlias(alias, existingAliases: existing).isValid,
      isTrue,
    );
  });

  test('rejects invalid, reserved-shape and duplicate names', () {
    const aliases = [
      FirewallAlias(
        id: 10,
        name: 'EXISTING_ALIAS',
        type: 'host',
        entries: [FirewallAliasEntry(value: '192.0.2.1')],
      ),
    ];

    String? nameError(String name) => validateFirewallAlias(
          FirewallAlias(
            name: name,
            type: 'host',
            entries: const [FirewallAliasEntry(value: '192.0.2.2')],
          ),
          existingAliases: aliases,
        ).nameError;

    expect(nameError(''), contains('required'));
    expect(nameError('bad-name'), contains('letters'));
    expect(nameError('12345'), contains('numeric'));
    expect(nameError('pkg_managed'), contains('pkg_'));
    expect(nameError('existing_alias'), contains('already exists'));
    expect(nameError('A' * 32), contains('31'));
  });

  test('allows the current alias name during edits', () {
    const alias = FirewallAlias(
      id: 1,
      name: 'KNOWN_HOSTS',
      type: 'host',
      entries: [FirewallAliasEntry(value: '192.0.2.20')],
    );

    expect(
      validateFirewallAlias(alias, existingAliases: existing).nameError,
      isNull,
    );
  });

  test('rejects duplicate values, self references and invalid details', () {
    const alias = FirewallAlias(
      name: 'WEB_HOSTS',
      type: 'host',
      entries: [
        FirewallAliasEntry(value: '192.0.2.1'),
        FirewallAliasEntry(value: '192.0.2.1'),
        FirewallAliasEntry(value: 'WEB_HOSTS'),
        FirewallAliasEntry(value: '192.0.2.3', description: 'bad||detail'),
      ],
    );

    final result = validateFirewallAlias(alias, existingAliases: existing);

    expect(result.entryErrors[1], contains('Duplicate'));
    expect(result.entryErrors[2], contains('itself'));
    expect(result.entryErrors[3], contains('cannot contain'));
  });

  test('rejects type-specific invalid values and wrong nested alias types', () {
    final host = validateFirewallAlias(
      const FirewallAlias(
        name: 'HOST_TEST',
        type: 'host',
        entries: [
          FirewallAliasEntry(value: 'not a host'),
          FirewallAliasEntry(value: 'KNOWN_PORTS'),
        ],
      ),
      existingAliases: existing,
    );
    final network = validateFirewallAlias(
      const FirewallAlias(
        name: 'NETWORK_TEST',
        type: 'network',
        entries: [
          FirewallAliasEntry(value: '192.0.2.0/33'),
          FirewallAliasEntry(value: 'KNOWN_PORTS'),
        ],
      ),
      existingAliases: existing,
    );
    final port = validateFirewallAlias(
      const FirewallAlias(
        name: 'PORT_TEST',
        type: 'port',
        entries: [
          FirewallAliasEntry(value: '70000'),
          FirewallAliasEntry(value: '9000-8000'),
          FirewallAliasEntry(value: 'KNOWN_HOSTS'),
        ],
      ),
      existingAliases: existing,
    );

    expect(host.entryErrors, hasLength(2));
    expect(network.entryErrors, hasLength(2));
    expect(port.entryErrors, hasLength(3));
  });

  test('requires at least one value and rejects description-only rows', () {
    const alias = FirewallAlias(
      name: 'EMPTY_ALIAS',
      type: 'host',
      entries: [
        FirewallAliasEntry(value: '', description: 'Missing value'),
      ],
    );

    final result = validateFirewallAlias(alias, existingAliases: existing);

    expect(result.entryErrors[0], contains('Enter a value'));
    expect(result.generalError, contains('at least one'));
  });

  test('unknown types are visible but fail edit validation', () {
    const alias = FirewallAlias(
      id: 9,
      name: 'URL_TABLE',
      type: 'urltable',
      entries: [FirewallAliasEntry(value: 'https://example.test/table.txt')],
    );

    expect(
      validateFirewallAlias(alias, existingAliases: existing).typeError,
      contains('not supported'),
    );
  });
}
