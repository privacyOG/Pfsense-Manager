import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/system_service.dart';

void main() {
  group('SystemService', () {
    test('uses status to decide whether a service is running', () {
      final service = SystemService.fromJson({
        'id': 12,
        'name': 'unbound',
        'description': 'DNS Resolver',
        'enabled': true,
        'status': false,
      });

      expect(service.id, 12);
      expect(service.displayName, 'DNS Resolver');
      expect(service.running, isFalse);
    });

    test('treats enabled configuration as separate from running state', () {
      final stopped = SystemService.fromJson({
        'name': 'openvpn',
        'enabled': true,
        'status': 'stopped',
      });
      final running = SystemService.fromJson({
        'name': 'dhcpd',
        'enabled': false,
        'status': true,
      });

      expect(stopped.running, isFalse);
      expect(running.running, isTrue);
    });
  });
}
