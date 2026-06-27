import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_rule.dart';

void main() {
  FirewallRule sampleRule({String ipProtocol = 'inet'}) => FirewallRule(
        id: '12',
        section: 'rules',
        type: 'pass',
        interface: 'lan',
        ipProtocol: ipProtocol,
        protocol: 'tcp',
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
