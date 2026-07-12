import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_nat.dart';
import 'package:pfsense_manager/utils/firewall_nat_validation.dart';

void main() {
  group('port forward validation', () {
    test('accepts a complete TCP rule with aliases', () {
      final rule = NatPortForward(
        interface: 'wan',
        ipProtocol: 'inet',
        protocol: 'tcp',
        source: 'TrustedHosts',
        sourcePort: 'ClientPorts',
        destination: 'wanip',
        destinationPort: '443',
        target: 'WebServer',
        localPort: '8443',
        associatedRuleId: 'new',
      );

      expect(() => validatePortForward(rule), returnsNormally);
    });

    test('requires a local port for TCP and rejects reversed ranges', () {
      final missingLocal = NatPortForward(
        interface: 'wan',
        ipProtocol: 'inet',
        protocol: 'tcp',
        source: 'any',
        destination: 'wanip',
        destinationPort: '443',
        target: '192.168.1.10',
      );
      final reversed = NatPortForward(
        interface: 'wan',
        ipProtocol: 'inet',
        protocol: 'udp',
        source: 'any',
        destination: 'wanip',
        destinationPort: '9000-8000',
        target: '192.168.1.10',
        localPort: '9000',
      );

      expect(
        () => validatePortForward(missingLocal),
        throwsA(isA<NatValidationException>()),
      );
      expect(
        () => validatePortForward(reversed),
        throwsA(
          isA<NatValidationException>().having(
            (error) => error.message,
            'message',
            contains('range must start'),
          ),
        ),
      );
    });

    test('rejects a literal target from the wrong address family', () {
      final rule = NatPortForward(
        interface: 'wan',
        ipProtocol: 'inet6',
        protocol: 'tcp',
        source: 'any',
        destination: 'wanip',
        destinationPort: '443',
        target: '192.168.1.10',
        localPort: '443',
      );

      expect(
        () => validatePortForward(rule),
        throwsA(
          isA<NatValidationException>().having(
            (error) => error.message,
            'message',
            contains('must use IPv6'),
          ),
        ),
      );
    });
  });

  group('1:1 NAT validation', () {
    test('accepts an IPv4 mapping', () {
      final mapping = NatOneToOneMapping(
        interface: 'wan',
        ipProtocol: 'inet',
        external: '203.0.113.10',
        source: '192.168.1.10',
        destination: 'any',
      );

      expect(() => validateOneToOneMapping(mapping), returnsNormally);
    });

    test('rejects mixed IP families', () {
      final mapping = NatOneToOneMapping(
        interface: 'wan',
        ipProtocol: 'inet',
        external: '2001:db8::10',
        source: '192.168.1.10',
        destination: 'any',
      );

      expect(
        () => validateOneToOneMapping(mapping),
        throwsA(isA<NatValidationException>()),
      );
    });
  });

  group('outbound NAT validation', () {
    test('accepts no-NAT mappings without translation fields', () {
      final mapping = NatOutboundMapping(
        interface: 'wan',
        noNat: true,
        source: '192.168.0.0/16',
        destination: '10.0.0.0/8',
      );

      expect(() => validateOutboundMapping(mapping), returnsNormally);
    });

    test('limits IPv4 target subnet and source-hash key format', () {
      final invalidSubnet = NatOutboundMapping(
        interface: 'wan',
        source: '192.168.0.0/16',
        destination: 'any',
        target: '203.0.113.20',
        targetSubnet: 64,
      );
      final invalidHash = NatOutboundMapping(
        interface: 'wan',
        source: '192.168.0.0/16',
        destination: 'any',
        target: '203.0.113.20',
        targetSubnet: 32,
        poolOptions: 'source-hash',
        sourceHashKey: 'bad-key',
      );

      expect(
        () => validateOutboundMapping(invalidSubnet),
        throwsA(
          isA<NatValidationException>().having(
            (error) => error.message,
            'message',
            contains('32 or less'),
          ),
        ),
      );
      expect(
        () => validateOutboundMapping(invalidHash),
        throwsA(
          isA<NatValidationException>().having(
            (error) => error.message,
            'message',
            contains('32 hexadecimal'),
          ),
        ),
      );
    });
  });
}
