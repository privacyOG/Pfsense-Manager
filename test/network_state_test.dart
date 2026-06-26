import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/network_state.dart';

void main() {
  group('NetworkState parsing', () {
    test('reads pfrest total counters and expiry field', () {
      final state = NetworkState.fromJson({
        'interface': 'igb0',
        'protocol': 'tcp',
        'source': '192.168.1.57',
        'destination': '1.1.1.1',
        'bytes_total': 8192,
        'bytes_in': 2048,
        'bytes_out': 6144,
        'packets_total': 24,
        'packets_in': 8,
        'packets_out': 16,
        'expires_in': '00:01:30',
      });

      expect(state.bytes, 8192);
      expect(state.packets, 24);
      expect(state.expires, '00:01:30');
    });

    test('accepts numeric counters returned as strings', () {
      final state = NetworkState.fromJson({
        'bytes_total': '4096',
        'packets_total': '12',
      });

      expect(state.bytes, 4096);
      expect(state.packets, 12);
    });

    test('falls back to directional and legacy counters', () {
      final directional = NetworkState.fromJson({
        'bytes_in': 1000,
        'bytes_out': 2500,
        'packets_in': 4,
        'packets_out': 6,
      });
      final legacy = NetworkState.fromJson({
        'bytes': 750,
        'packets': 3,
        'expires': '00:00:45',
      });

      expect(directional.bytes, 3500);
      expect(directional.packets, 10);
      expect(legacy.bytes, 750);
      expect(legacy.packets, 3);
      expect(legacy.expires, '00:00:45');
    });
  });
}
