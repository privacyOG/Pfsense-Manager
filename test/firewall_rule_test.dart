import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_rule.dart';

void main() {
  FirewallRule sampleRule({
    String ipProtocol = 'inet',
    String? protocol = 'tcp',
  }) =>
      FirewallRule(
        id: '12',
        section: 'rules',
        type: 'pass',
        interface: 'lan',
        ipProtocol: ipProtocol,
        protocol: protocol,
        sourceType: 'network',
        sourceNetwork: '*',
        destinationType: 'network',
        destinationNetwork: '192.168.1.50',
        destinationPortFrom: 443,
        destinationPortTo: 443,
        description: 'Allow HTTPS to host',
        enabled: true,
        createdTime: '2026-01-01T00:00:00Z',
      );

  Map<String, dynamic> apiRule({Object? protocol = 'tcp'}) => {
        'id': 4,
        'type': 'pass',
        'interface': ['wan'],
        'ipprotocol': 'inet',
        'protocol': protocol,
        'source': 'any',
        'destination': 'any',
        'disabled': false,
      };

  test('serialises a pfrest firewall rule payload', () {
    final payload = sampleRule().toJson();

    expect(payload['type'], 'pass');
    expect(payload['interface'], ['lan']);
    expect(payload['ipprotocol'], 'inet');
    expect(payload['protocol'], 'tcp');
    expect(payload['source'], 'any');
    expect(payload['destination'], '192.168.1.50');
    expect(payload['destination_port'], '443');
    expect(payload['descr'], 'Allow HTTPS to host');
    expect(payload['disabled'], isFalse);
    expect(payload.containsKey('id'), isFalse);
    expect(payload.containsKey('section'), isFalse);
  });

  test('omits protocol when creating an unrestricted rule', () {
    final rule = sampleRule(protocol: null);
    final payload = rule.toJson();

    expect(rule.apiProtocol, isNull);
    expect(rule.protocol, 'any');
    expect(rule.protocolLabel, 'ANY');
    expect(payload.containsKey('protocol'), isFalse);
  });

  test('parses an unrestricted pfrest rule without inventing a protocol', () {
    final rule = FirewallRule.fromJson(apiRule(protocol: null));

    expect(rule.apiProtocol, isNull);
    expect(rule.protocol, 'any');
    expect(rule.toJson().containsKey('protocol'), isFalse);
  });

  test('editing an unrestricted rule keeps protocol omitted', () {
    final rule = FirewallRule.fromJson(apiRule(protocol: null));
    final edited = rule.copyWith(description: 'Updated description');

    expect(edited.description, 'Updated description');
    expect(edited.apiProtocol, isNull);
    expect(edited.toJson().containsKey('protocol'), isFalse);
  });

  test('legacy Any values are treated as unrestricted', () {
    final rule = FirewallRule.fromJson(apiRule(protocol: 'any'));

    expect(rule.apiProtocol, isNull);
    expect(rule.toJson().containsKey('protocol'), isFalse);
  });

  test('copyWith can clear a previously selected protocol', () {
    final cleared = sampleRule().copyWith(protocol: null);

    expect(cleared.apiProtocol, isNull);
    expect(cleared.toJson().containsKey('protocol'), isFalse);
  });

  test('supported pfrest protocol values round-trip unchanged', () {
    const protocols = [
      'tcp',
      'udp',
      'tcp/udp',
      'icmp',
      'esp',
      'ah',
      'gre',
      'ipv6',
      'igmp',
      'pim',
      'ospf',
      'carp',
      'pfsync',
    ];

    for (final protocol in protocols) {
      final rule = FirewallRule.fromJson(apiRule(protocol: protocol));

      expect(rule.apiProtocol, protocol, reason: protocol);
      expect(rule.toJson()['protocol'], protocol, reason: protocol);
    }
  });

  test('preserves pfrest ip protocol values', () {
    final rule = FirewallRule.fromJson({
      'id': 4,
      'type': 'block',
      'interface': ['wan'],
      'ipprotocol': 'inet6',
      'protocol': 'udp',
      'source': 'any',
      'destination': '2001:db8::10',
      'disabled': true,
    });

    expect(rule.ipProtocol, 'inet6');
    expect(rule.enabled, isFalse);
    expect(rule.toJson()['ipprotocol'], 'inet6');
  });

  test('falls back to inet6 when address fields contain IPv6', () {
    final payload = sampleRule(ipProtocol: '').copyWith(
      destinationNetwork: '2001:db8::10',
    ).toJson();

    expect(payload['ipprotocol'], 'inet6');
  });
}
