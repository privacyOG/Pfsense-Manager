import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dhcp_lease.dart';

void main() {
  group('DhcpLease', () {
    test('parses pfrest active and online status fields', () {
      final lease = DhcpLease.fromJson({
        'ip': '192.168.1.50',
        'mac': 'AA:BB:CC:DD:EE:FF',
        'hostname': 'workstation',
        'if': 'lan',
        'starts': '2026/01/01 10:00:00',
        'ends': '2026/01/01 20:00:00',
        'active_status': 'active',
        'online_status': 'online',
        'descr': 'Office desktop',
      });

      expect(lease.ipAddress, '192.168.1.50');
      expect(lease.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(lease.interface, 'lan');
      expect(lease.state, 'active / online');
      expect(lease.description, 'Office desktop');
      expect(lease.active, isTrue);
      expect(lease.online, isTrue);
      expect(lease.expired, isFalse);
    });

    test('detects expired and offline leases from pfrest status fields', () {
      final lease = DhcpLease.fromJson({
        'ip': '192.168.1.51',
        'mac': 'AA:BB:CC:DD:EE:00',
        'hostname': 'tablet',
        'if': 'lan',
        'active_status': 'expired',
        'online_status': 'offline',
      });

      expect(lease.state, 'expired / offline');
      expect(lease.active, isFalse);
      expect(lease.online, isFalse);
      expect(lease.expired, isTrue);
    });

    test('keeps compatibility with legacy status fields', () {
      final lease = DhcpLease.fromJson({
        'ip_address': '192.168.1.52',
        'mac_address': 'AA:BB:CC:DD:EE:11',
        'interface': 'opt1',
        'status': 'active',
        'description': 'Printer',
        'type': 'static',
      });

      expect(lease.ipAddress, '192.168.1.52');
      expect(lease.interface, 'opt1');
      expect(lease.state, 'active');
      expect(lease.description, 'Printer');
      expect(lease.active, isTrue);
      expect(lease.staticMapping, isTrue);
    });
  });
}
