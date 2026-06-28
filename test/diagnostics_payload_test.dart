import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/services/api_client.dart';

void main() {
  group('diagnostics payloads', () {
    test('maps ping interface source to pfrest source address field', () {
      final payload = buildPingPayload({
        'host': '8.8.8.8',
        'count': 4,
        'interface': ' 192.168.1.1 ',
      });

      expect(payload['host'], '8.8.8.8');
      expect(payload['count'], 4);
      expect(payload['source_address'], '192.168.1.1');
      expect(payload.containsKey('interface'), isFalse);
    });

    test('preserves explicit source address', () {
      final payload = buildPingPayload({
        'host': 'example.com',
        'count': 1,
        'interface': 'wan',
        'source_address': '10.0.0.1',
      });

      expect(payload['source_address'], '10.0.0.1');
      expect(payload.containsKey('interface'), isFalse);
    });
  });
}
