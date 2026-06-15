import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/system_info.dart';

void main() {
  test('parses expanded system information fields', () {
    final info = SystemInfo.fromJson({
      'data': {
        'system_type': 'pfSense',
        'version': '1.7.1',
        'architecture': 'amd64',
        'git_commit': 'abc123',
        'hostname': 'firewall',
        'freebsd_version': 'FreeBSD 15.0',
        'uptime': '4 days',
        'repositories': [
          {'name': 'primary', 'priority': 1, 'enabled': true},
        ],
      },
    });

    expect(info.systemType, 'pfSense');
    expect(info.version, '1.7.1');
    expect(info.architecture, 'amd64');
    expect(info.gitCommit, 'abc123');
    expect(info.hostname, 'firewall');
    expect(info.platform, 'FreeBSD 15.0');
    expect(info.uptime, '4 days');
    expect(info.repositories.single.priority, 1);
  });
}
