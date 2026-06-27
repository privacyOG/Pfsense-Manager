import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/system_log_source.dart';
import 'package:pfsense_manager/screens/system_logs_screen.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  group('system log sources', () {
    test('uses pfrest DHCP log endpoint name', () {
      final dhcp = systemLogSources.singleWhere((source) => source.label == 'DHCP');

      expect(dhcp.logType, 'dhcp');
      expect(systemLogPath(dhcp.logType), '/api/v2/status/logs/dhcp');
    });

    test('does not map DHCP to the daemon name', () {
      final logTypes = systemLogSources.map((source) => source.logType).toList();

      expect(logTypes, isNot(contains('dhcpd')));
    });

    test('marks missing log endpoints as unsupported', () {
      final source = systemLogSources.singleWhere((item) => item.label == 'Gateway');
      final message = systemLogErrorMessage(source, const ApiException('Not found', 404));

      expect(isUnsupportedSystemLogError(const ApiException('Not found', 404)), isTrue);
      expect(message, contains('Gateway logs are not available'));
    });
  });
}
