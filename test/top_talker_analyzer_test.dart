import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dashboard.dart';
import 'package:pfsense_manager/models/network_state.dart';
import 'package:pfsense_manager/services/top_talker_analyzer.dart';

void main() {
  InterfaceStatus lanInterface() => InterfaceStatus.fromJson({
        'name': 'lan',
        'descr': 'LAN',
        'hwif': 'igb1',
        'status': 'up',
        'ipaddr': '192.168.1.1',
        'subnet': 24,
      });

  test('selects the local destination instead of the remote source', () {
    final analyzer = TopTalkerAnalyzer();
    final talkers = analyzer.build(
      capturedAt: DateTime.utc(2026, 1, 1),
      interfaces: [lanInterface()],
      states: [
        NetworkState.fromJson({
          'interface': 'lan',
          'protocol': 'tcp',
          'source': '8.8.8.8:443',
          'destination': '192.168.1.57:51888',
          'state': 'ESTABLISHED',
          'bytes_total': 4096,
          'packets_total': 20,
        }),
      ],
    );

    expect(talkers, hasLength(1));
    expect(talkers.single.ipAddress, '192.168.1.57');
    expect(talkers.single.interface, 'LAN');
    expect(talkers.single.bytes, 4096);
  });

  test('supports IPv6 endpoints without splitting on colons', () {
    final analyzer = TopTalkerAnalyzer();
    final talkers = analyzer.build(
      capturedAt: DateTime.utc(2026, 1, 1),
      interfaces: [
        InterfaceStatus.fromJson({
          'name': 'lan',
          'descr': 'LAN',
          'hwif': 'igb1',
          'status': 'up',
          'ipaddrv6': 'fd00::1',
          'subnetv6': 64,
        }),
      ],
      states: [
        NetworkState.fromJson({
          'interface': 'lan',
          'protocol': 'tcp',
          'source': '[2001:4860:4860::8888]:443',
          'destination': '[fd00::57]:51888',
          'state': 'ESTABLISHED',
          'bytes_total': 2048,
          'packets_total': 10,
        }),
      ],
    );

    expect(talkers, hasLength(1));
    expect(talkers.single.ipAddress, 'fd00::57');
    expect(talkers.single.bytes, 2048);
  });

  test('calculates current traffic rate from counter deltas', () {
    final analyzer = TopTalkerAnalyzer();
    final first = analyzer.build(
      capturedAt: DateTime.utc(2026, 1, 1),
      interfaces: [lanInterface()],
      states: [
        NetworkState.fromJson({
          'interface': 'lan',
          'protocol': 'tcp',
          'source': '192.168.1.57:50000',
          'destination': '1.1.1.1:443',
          'state': 'ESTABLISHED',
          'bytes_total': 1000,
          'packets_total': 5,
        }),
      ],
    );

    final second = analyzer.build(
      capturedAt: DateTime.utc(2026, 1, 1, 0, 0, 10),
      interfaces: [lanInterface()],
      states: [
        NetworkState.fromJson({
          'interface': 'lan',
          'protocol': 'tcp',
          'source': '192.168.1.57:50000',
          'destination': '1.1.1.1:443',
          'state': 'ESTABLISHED',
          'bytes_total': 3000,
          'packets_total': 15,
        }),
      ],
    );

    expect(first.single.bytesPerSecond, 0);
    expect(second.single.bytesPerSecond, 200);
  });
}
