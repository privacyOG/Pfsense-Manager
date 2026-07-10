import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_rule.dart';
import 'package:pfsense_manager/utils/firewall_port_validation.dart';

void main() {
  group('firewall destination port validation', () {
    test('accepts empty ports for a port-capable protocol', () {
      final result = validateFirewallDestinationPortRange(
        protocol: 'tcp',
        from: '',
        to: '',
      );

      expect(result.isValid, isTrue);
    });

    test('accepts a single starting port', () {
      final result = validateFirewallDestinationPortRange(
        protocol: 'udp',
        from: '53',
        to: '',
      );

      expect(result.isValid, isTrue);
    });

    test('accepts an ordered port range', () {
      final result = validateFirewallDestinationPortRange(
        protocol: 'tcp/udp',
        from: '1000',
        to: '2000',
      );

      expect(result.isValid, isTrue);
    });

    test('requires a starting port when only ending port is entered', () {
      final result = validateFirewallDestinationPortRange(
        protocol: 'tcp',
        from: '',
        to: '443',
      );

      expect(result.fromError, 'Enter a starting port.');
      expect(result.isValid, isFalse);
    });

    test('rejects a reversed port range', () {
      final result = validateFirewallDestinationPortRange(
        protocol: 'tcp',
        from: '2000',
        to: '1000',
      );

      expect(
        result.toError,
        'Ending port must be greater than or equal to starting port.',
      );
      expect(result.isValid, isFalse);
    });

    test('rejects ports outside the valid range', () {
      final low = validateFirewallDestinationPortRange(
        protocol: 'tcp',
        from: '0',
        to: '',
      );
      final high = validateFirewallDestinationPortRange(
        protocol: 'tcp',
        from: '1',
        to: '65536',
      );

      expect(low.fromError, 'Enter a port from 1 to 65535.');
      expect(high.toError, 'Enter a port from 1 to 65535.');
    });

    test('ignores port text for protocols that do not support ports', () {
      for (final protocol in ['any', 'icmp', 'esp']) {
        final result = validateFirewallDestinationPortRange(
          protocol: protocol,
          from: '2000',
          to: '1000',
        );

        expect(result.isValid, isTrue, reason: protocol);
      }
    });
  });

  group('firewall destination port payloads', () {
    test('serialises a single port and a valid range', () {
      expect(_rule(protocol: 'tcp', from: 443).toJson()['destination_port'], '443');
      expect(
        _rule(protocol: 'udp', from: 1000, to: 2000)
            .toJson()['destination_port'],
        '1000:2000',
      );
    });

    test('omits destination ports for unrestricted and ICMP rules', () {
      for (final protocol in <String?>[null, 'icmp']) {
        final payload = _rule(
          protocol: protocol,
          from: 443,
          to: 443,
        ).toJson();

        expect(payload.containsKey('destination_port'), isFalse);
      }
    });
  });
}

FirewallRule _rule({
  required String? protocol,
  int? from,
  int? to,
}) {
  return FirewallRule(
    section: 'rules',
    type: 'pass',
    interface: 'wan',
    protocol: protocol,
    sourceType: 'network',
    sourceNetwork: 'any',
    destinationType: 'network',
    destinationNetwork: 'any',
    destinationPortFrom: from,
    destinationPortTo: to,
    description: 'Port validation test',
    enabled: true,
    createdTime: '2026-07-11T00:00:00Z',
  );
}
