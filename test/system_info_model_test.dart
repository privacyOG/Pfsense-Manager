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

  test('parses nested pfSense Plus fields and numeric uptime', () {
    final info = SystemInfo.fromJson({
      'data': {
        'system': {
          'product_name': 'pfSense Plus',
          'firmware_version': '24.11.1-RELEASE',
          'machine_arch': 'amd64',
          'hostname': 'edge-firewall',
          'platform': 'FreeBSD 15.0-CURRENT',
          'kernel_release': '15.0-CURRENT',
          'uptime_seconds': 183845,
        },
      },
    });

    expect(info.systemType, 'pfSense Plus');
    expect(info.version, '24.11.1-RELEASE');
    expect(info.architecture, 'amd64');
    expect(info.hostname, 'edge-firewall');
    expect(info.platform, 'FreeBSD 15.0-CURRENT');
    expect(info.kernelVersion, '15.0-CURRENT');
    expect(info.uptime, '2 days, 3 hours, 4 minutes');
  });

  test('uses application repository and mirror defaults when omitted', () {
    final info = SystemInfo.fromJson({
      'data': {
        'version': '2.8.0-RELEASE',
      },
    });

    expect(info.packageMirrorUrl, 'https://cloud.privacyx.co/');
    expect(info.repositories, hasLength(1));
    expect(info.repositories.single.name, 'pfSense Manager');
    expect(info.repositories.single.url, 'https://cloud.privacyx.co/');
    expect(info.repositories.single.priority, 1);
    expect(info.repositories.single.enabled, isTrue);
  });

  test('parses repository aliases and sorts by priority', () {
    final info = SystemInfo.fromJson({
      'data': {
        'repos': [
          {
            'id': 'secondary',
            'mirror': 'https://secondary.example/',
            'order': '20',
            'active': 'false',
          },
          {
            'name': 'primary',
            'url': 'https://primary.example/',
            'priority': 10,
            'enabled': true,
          },
        ],
      },
    });

    expect(info.repositories.map((item) => item.name), [
      'primary',
      'secondary',
    ]);
    expect(info.repositories.first.priority, 10);
    expect(info.repositories.last.priority, 20);
    expect(info.repositories.last.enabled, isFalse);
  });
}
