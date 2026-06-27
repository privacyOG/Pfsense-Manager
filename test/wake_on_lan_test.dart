import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/services/pfsense_service.dart';

void main() {
  group('Wake-on-LAN payload', () {
    test('uses pfrest endpoint field names', () {
      final payload = buildWakeOnLanPayload(
        mac: ' AA:BB:CC:DD:EE:FF ',
        interface: ' lan ',
      );

      expect(payload, {
        'interface': 'lan',
        'mac_addr': 'AA:BB:CC:DD:EE:FF',
      });
    });
  });
}
