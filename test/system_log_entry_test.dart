import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/system_log_entry.dart';

void main() {
  group('SystemLogEntry parsing', () {
    test('parses a standard syslog line into time, process and message', () {
      final entry = SystemLogEntry.fromText(
        'Jun 23 14:05:01 firewall dhcpd[2123]: DHCPACK on 192.168.1.40',
      );

      expect(entry.timeLabel, 'Jun 23 14:05:01');
      expect(entry.process, 'dhcpd');
      expect(entry.message, 'DHCPACK on 192.168.1.40');
      expect(entry.raw, contains('DHCPACK'));
    });

    test('handles a process without a pid suffix', () {
      final entry = SystemLogEntry.fromText(
        'Jun 23 09:00:00 fw kernel: pf: state table full',
      );

      expect(entry.timeLabel, 'Jun 23 09:00:00');
      expect(entry.process, 'kernel');
      expect(entry.message, 'pf: state table full');
    });

    test('falls back to raw when the line is not syslog-shaped', () {
      final entry = SystemLogEntry.fromText('a bare unstructured line');

      expect(entry.timeLabel, isEmpty);
      expect(entry.process, isEmpty);
      expect(entry.message, 'a bare unstructured line');
      expect(entry.raw, 'a bare unstructured line');
    });

    test('parses object form with a text field', () {
      final entry = SystemLogEntry.fromJson({
        'text': 'Jun 23 14:05:01 firewall sshd[990]: Accepted publickey',
      });

      expect(entry.process, 'sshd');
      expect(entry.message, 'Accepted publickey');
    });

    test('uses structured time and process fields when present', () {
      final entry = SystemLogEntry.fromJson({
        'time': '2026-06-23T14:05:01Z',
        'process': 'unbound',
        'message': 'reload of zone db complete',
      });

      expect(entry.timeLabel, '2026-06-23T14:05:01Z');
      expect(entry.process, 'unbound');
      expect(entry.message, 'reload of zone db complete');
    });

    test('parses a plain string element', () {
      final entry = SystemLogEntry.fromJson(
        'Jun 23 14:06:10 fw php-fpm[100]: config change',
      );

      expect(entry.process, 'php-fpm');
      expect(entry.message, 'config change');
    });
  });
}
