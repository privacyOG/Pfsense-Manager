import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_alias.dart';

void main() {
  test('parses ordered address and detail lists', () {
    final alias = FirewallAlias.fromJson({
      'id': '7',
      'name': 'WEB_HOSTS',
      'type': 'host',
      'descr': 'Application servers',
      'address': ['192.0.2.10', 'server.example.test'],
      'detail': ['Primary', 'Secondary'],
    });

    expect(alias.id, 7);
    expect(alias.name, 'WEB_HOSTS');
    expect(alias.type, 'host');
    expect(alias.description, 'Application servers');
    expect(alias.entries, hasLength(2));
    expect(alias.entries[0].value, '192.0.2.10');
    expect(alias.entries[0].description, 'Primary');
    expect(alias.entries[1].value, 'server.example.test');
    expect(alias.entries[1].description, 'Secondary');
    expect(alias.isSupportedType, isTrue);
  });

  test('preserves empty detail positions in delimited responses', () {
    final alias = FirewallAlias.fromJson({
      'name': 'MIXED_HOSTS',
      'type': 'host',
      'address': '192.0.2.1 192.0.2.2 192.0.2.3',
      'detail': 'first||||third',
    });

    expect(alias.entries.map((entry) => entry.description), [
      'first',
      '',
      'third',
    ]);
  });

  test('create payload includes immutable name and aligned values', () {
    const alias = FirewallAlias(
      name: 'ADMIN_PORTS',
      type: 'port',
      description: ' Administrative services ',
      entries: [
        FirewallAliasEntry(value: ' 22 ', description: ' SSH '),
        FirewallAliasEntry(value: '8443-8444'),
        FirewallAliasEntry(value: '   ', description: 'ignored blank row'),
      ],
    );

    expect(alias.toCreatePayload(), {
      'name': 'ADMIN_PORTS',
      'type': 'port',
      'descr': 'Administrative services',
      'address': ['22', '8443-8444'],
      'detail': ['SSH', ''],
    });
  });

  test('update payload omits immutable alias name', () {
    const alias = FirewallAlias(
      id: 4,
      name: 'UNCHANGED_NAME',
      type: 'network',
      entries: [
        FirewallAliasEntry(value: '192.0.2.0/24'),
      ],
    );

    final payload = alias.toUpdatePayload();

    expect(payload.containsKey('name'), isFalse);
    expect(payload['type'], 'network');
    expect(payload['address'], ['192.0.2.0/24']);
  });

  test('unknown alias types remain visible but read-only', () {
    final alias = FirewallAlias.fromJson({
      'id': 9,
      'name': 'REMOTE_TABLE',
      'type': 'urltable',
      'address': ['https://example.test/table.txt'],
    });

    expect(alias.isSupportedType, isFalse);
    expect(alias.entries.single.value, 'https://example.test/table.txt');
  });
}
