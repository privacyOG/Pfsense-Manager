import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/utils/ping_request_validation.dart';

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

    test('accepts and serialises the minimum and maximum packet counts', () {
      final minimum = buildPingPayload({
        'host': '192.0.2.1',
        'count': pingPacketCountMinimum,
      });
      final maximum = buildPingPayload({
        'host': '192.0.2.1',
        'count': pingPacketCountMaximum,
      });

      expect(minimum['count'], 1);
      expect(maximum['count'], 10);
    });

    test('normalises an integer count supplied as text', () {
      final payload = buildPingPayload({
        'host': '192.0.2.1',
        'count': '10',
      });

      expect(payload['count'], 10);
    });

    test('rejects packet counts below and above the pfREST range', () {
      expect(
        () => buildPingPayload({'host': '192.0.2.1', 'count': 0}),
        throwsRangeError,
      );
      expect(
        () => buildPingPayload({'host': '192.0.2.1', 'count': 11}),
        throwsRangeError,
      );
    });

    test('rejects a non-integer packet count', () {
      expect(
        () => buildPingPayload({'host': '192.0.2.1', 'count': '4.5'}),
        throwsArgumentError,
      );
    });
  });

  group('ping packet count contract', () {
    test('offers only values accepted by pfREST', () {
      expect(pingPacketCountChoices, [1, 4, 8, 10]);
      expect(
        pingPacketCountChoices.every(
          (count) =>
              count >= pingPacketCountMinimum &&
              count <= pingPacketCountMaximum,
        ),
        isTrue,
      );
      expect(pingPacketCountChoices, isNot(contains(16)));
    });

    test('validates the lower and upper boundaries', () {
      expect(validatePingPacketCount(1), 1);
      expect(validatePingPacketCount(10), 10);
      expect(() => validatePingPacketCount(0), throwsRangeError);
      expect(() => validatePingPacketCount(11), throwsRangeError);
    });
  });
}
