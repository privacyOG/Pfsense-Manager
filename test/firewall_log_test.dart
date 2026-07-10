import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_log.dart';

const ipv4BlockLine =
    '2026-07-11T08:15:30+10:00 firewall filterlog[123]: '
    '100,0,,1234,igc0,match,block,in,4,0x0,,64,12345,0,none,6,tcp,'
    '60,192.0.2.10,198.51.100.20,51515,443,0,S,1,0,65535,,mss';

const ipv6PassLine =
    '2026-07-11T08:16:30+10:00 firewall filterlog: '
    '200,0,,5678,igc1,match,pass,in,6,0x00,12345,64,tcp,6,80,'
    '2001:db8::10,2001:db8::20,53000,443,20,SA,1,0,65535,,mss';

const rejectLine =
    '2026-07-11T00:17:30Z firewall filterlog: '
    '300,0,,9012,igc2,match,reject,in,4,0x0,,64,222,0,none,17,udp,'
    '76,203.0.113.10,203.0.113.20,5353,53,48';

void main() {
  group('raw firewall log parsing', () {
    test('parses an IPv4 TCP filterlog entry', () {
      final log = FirewallLog.fromJson({'text': ipv4BlockLine});

      expect(log.isParsed, isTrue);
      expect(log.hasTimestamp, isTrue);
      expect(log.timestamp.toUtc(), DateTime.utc(2026, 7, 10, 22, 15, 30));
      expect(log.action, 'BLOCK');
      expect(log.interface, 'igc0');
      expect(log.reason, 'match');
      expect(log.protocol, 'TCP');
      expect(log.length, 60);
      expect(log.sourceIp, '192.0.2.10');
      expect(log.destinationIp, '198.51.100.20');
      expect(log.sourcePort, 51515);
      expect(log.destinationPort, 443);
      expect(log.tcpFlags, 'S');
      expect(log.rawText, ipv4BlockLine);
    });

    test('uses the IPv6 field layout', () {
      final log = FirewallLog.fromJson({'text': ipv6PassLine});

      expect(log.isParsed, isTrue);
      expect(log.action, 'PASS');
      expect(log.interface, 'igc1');
      expect(log.protocol, 'TCP');
      expect(log.length, 80);
      expect(log.sourceIp, '2001:db8::10');
      expect(log.destinationIp, '2001:db8::20');
      expect(log.sourcePort, 53000);
      expect(log.destinationPort, 443);
      expect(log.tcpFlags, 'SA');
    });

    test('parses raw CSV without a syslog prefix', () {
      final rawCsv = ipv4BlockLine.split('filterlog[123]: ').last;
      final log = FirewallLog.fromJson({'text': rawCsv});

      expect(log.isParsed, isTrue);
      expect(log.hasTimestamp, isFalse);
      expect(log.action, 'BLOCK');
      expect(log.formattedTime, '--:--:--');
    });

    test('handles malformed and empty entries safely', () {
      final malformed = FirewallLog.fromJson({'text': 'not a filter log'});
      final empty = FirewallLog.fromJson({'text': ''});

      expect(malformed.isParsed, isFalse);
      expect(malformed.action, 'UNKNOWN');
      expect(malformed.sourceIp, isEmpty);
      expect(empty.action, 'UNKNOWN');
      expect(empty.sourceIp, isEmpty);
    });

    test('uses deterministic identifiers for the same raw entry', () {
      final first = FirewallLog.fromJson({'text': ipv4BlockLine});
      final second = FirewallLog.fromJson({'text': ipv4BlockLine});

      expect(first.id, second.id);
      expect(first.id, hasLength(8));
    });
  });

  group('local firewall log filtering', () {
    final logs = [
      FirewallLog.fromJson({'text': ipv4BlockLine}),
      FirewallLog.fromJson({'text': ipv6PassLine}),
      FirewallLog.fromJson({'text': rejectLine}),
      FirewallLog.fromJson({'text': 'malformed entry'}),
    ];

    test('filters PASS, BLOCK and REJECT actions consistently', () {
      expect(filterFirewallLogs(logs, action: 'PASS').single.action, 'PASS');
      expect(filterFirewallLogs(logs, action: 'BLOCK').single.action, 'BLOCK');
      expect(filterFirewallLogs(logs, action: 'REJECT').single.action, 'REJECT');
    });

    test('searches parsed fields and raw text', () {
      expect(filterFirewallLogs(logs, query: '2001:db8::20').single.action, 'PASS');
      expect(filterFirewallLogs(logs, query: 'igc0').single.action, 'BLOCK');
      expect(filterFirewallLogs(logs, query: 'malformed entry').single.isParsed,
          isFalse);
    });

    test('filters by parsed timestamp and excludes unknown timestamps', () {
      final filtered = filterFirewallLogs(
        logs,
        since: DateTime.parse('2026-07-10T22:16:00Z'),
      );

      expect(filtered.map((log) => log.action), containsAll(['PASS', 'REJECT']));
      expect(filtered.map((log) => log.action), isNot(contains('BLOCK')));
      expect(filtered.every((log) => log.hasTimestamp), isTrue);
    });
  });
}
