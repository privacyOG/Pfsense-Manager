import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/screens/network_monitor_screen.dart';

void main() {
  group('network monitor polling', () {
    test('keeps interface polling on the selected live interval', () {
      expect(
        networkMonitorInterfacePollInterval(1),
        const Duration(seconds: 1),
      );
      expect(
        networkMonitorInterfacePollInterval(3),
        const Duration(seconds: 3),
      );
      expect(
        networkMonitorInterfacePollInterval(10),
        const Duration(seconds: 10),
      );
    });

    test('polls firewall states less often than interface counters', () {
      expect(networkMonitorStatePollInterval(1), const Duration(seconds: 15));
      expect(networkMonitorStatePollInterval(3), const Duration(seconds: 15));
      expect(networkMonitorStatePollInterval(5), const Duration(seconds: 25));
      expect(networkMonitorStatePollInterval(10), const Duration(seconds: 50));
    });

    test('uses the interface poll interval for traffic history size', () {
      expect(networkMonitorHistorySampleLimit(1), 122);
      expect(networkMonitorHistorySampleLimit(3), 42);
      expect(networkMonitorHistorySampleLimit(10), 14);
      expect(networkMonitorHistorySampleLimit(30), 12);
    });
  });
}
