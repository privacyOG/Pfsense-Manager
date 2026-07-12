import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_nat.dart';

void main() {
  test('port forward preserves unknown editable fields while stripping metadata', () {
    final rule = NatPortForward.fromJson({
      'id': 7,
      'interface': 'wan',
      'ipprotocol': 'inet',
      'protocol': 'tcp',
      'source': 'any',
      'destination': 'wanip',
      'destination_port': '443',
      'target': '192.168.1.20',
      'local_port': '8443',
      'associated_rule_id': 'new',
      'descr': 'HTTPS proxy',
      'custom_option': 'keep-me',
      'created_time': 123,
      'updated_by': 'admin',
    });

    final payload = rule.copyWith(disabled: true).toPayload(includeId: true);

    expect(payload['id'], 7);
    expect(payload['disabled'], isTrue);
    expect(payload['custom_option'], 'keep-me');
    expect(payload['associated_rule_id'], 'new');
    expect(payload, isNot(contains('created_time')));
    expect(payload, isNot(contains('updated_by')));
  });

  test('1:1 mapping preserves explicit false and unknown fields', () {
    final mapping = NatOneToOneMapping.fromJson({
      'id': '4',
      'interface': 'wan',
      'disabled': 'false',
      'nobinat': true,
      'natreflection': null,
      'ipprotocol': 'inet',
      'external': '203.0.113.10',
      'source': '192.168.10.10',
      'destination': 'any',
      'descr': 'Mail server',
      'ordering_hint': 9,
    });

    final payload = mapping.toPayload(includeId: true);

    expect(mapping.enabled, isTrue);
    expect(payload['id'], 4);
    expect(payload['nobinat'], isTrue);
    expect(payload['natreflection'], isNull);
    expect(payload['ordering_hint'], 9);
  });

  test('outbound no-NAT mapping clears translation-only fields', () {
    final mapping = NatOutboundMapping(
      id: 8,
      interface: 'wan',
      protocol: null,
      noNat: true,
      source: '192.168.0.0/16',
      destination: '10.0.0.0/8',
      target: 'wanip',
      targetSubnet: 32,
      natPort: '40000-50000',
      staticNatPort: true,
      poolOptions: 'source-hash',
      sourceHashKey: '0x0123456789abcdef0123456789abcdef',
      raw: const {'custom_option': 'preserved'},
    );

    final payload = mapping.toPayload(includeId: true);

    expect(payload['nonat'], isTrue);
    expect(payload['target'], isNull);
    expect(payload['target_subnet'], isNull);
    expect(payload['nat_port'], isNull);
    expect(payload['static_nat_port'], isFalse);
    expect(payload['poolopts'], isNull);
    expect(payload['source_hash_key'], isNull);
    expect(payload['custom_option'], 'preserved');
  });

  test('translated outbound mappings receive safe default subnet values', () {
    final ipv4 = NatOutboundMapping(
      interface: 'wan',
      source: '192.168.0.0/16',
      destination: 'any',
      target: '203.0.113.10',
    ).toPayload();
    final alias = NatOutboundMapping(
      interface: 'wan',
      source: '192.168.0.0/16',
      destination: 'any',
      target: 'PublicAddresses',
    ).toPayload();

    expect(ipv4['target_subnet'], 32);
    expect(alias['target_subnet'], 128);
  });

  test('outbound mode exposes pfSense manual wording without changing API value', () {
    expect(OutboundNatMode.parse('advanced'), OutboundNatMode.advanced);
    expect(OutboundNatMode.advanced.name, 'advanced');
    expect(OutboundNatMode.advanced.label, 'Manual');
    expect(OutboundNatMode.hybrid.description, contains('manual mappings'));
  });
}
