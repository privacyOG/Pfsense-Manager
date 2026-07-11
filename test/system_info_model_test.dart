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
        'package_mirror_url': 'https://packages.example.test/',
        'repositories': [
          {
            'name': 'primary',
            'url': 'https://repository.example.test/',
            'priority': 1,
            'enabled': true,
          },
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
    expect(info.packageMirrorUrl, 'https://packages.example.test/');
    expect(info.repositories.single.name, 'primary');
    expect(info.repositories.single.url, 'https://repository.example.test/');
    expect(info.repositories.single.priority, 1);
    expect(info.repositories.single.enabled, isTrue);
    expect(info.repositoryType, 'primary');
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

  test('does not create repository or package mirror metadata when omitted', () {
    final info = SystemInfo.fromJson({
      'data': {
        'version': '2.8.0-RELEASE',
      },
    });

    expect(info.packageMirrorUrl, isNull);
    expect(info.repositories, isEmpty);
    expect(info.repositoryType, isNull);
  });

  test('reported package mirror does not create a repository record', () {
    final info = SystemInfo.fromJson({
      'data': {
        'package_mirror': 'https://packages.example.test/',
      },
    });

    expect(info.packageMirrorUrl, 'https://packages.example.test/');
    expect(info.repositories, isEmpty);
  });

  test('preserves partial repository data without inventing fields', () {
    final info = SystemInfo.fromJson({
      'data': {
        'repositories': [
          {'name': 'primary'},
          {'url': 'https://unnamed.example.test/'},
          {
            'name': 'disabled',
            'enabled': false,
          },
        ],
      },
    });

    expect(info.repositories, hasLength(3));
    expect(info.repositories[0].name, 'primary');
    expect(info.repositories[0].url, isNull);
    expect(info.repositories[0].priority, isNull);
    expect(info.repositories[0].enabled, isNull);
    expect(info.repositories[1].name, isNull);
    expect(info.repositories[1].url, 'https://unnamed.example.test/');
    expect(info.repositories[2].name, 'disabled');
    expect(info.repositories[2].enabled, isFalse);
  });

  test('parses repository aliases and sorts reported priorities', () {
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
            'name': 'unranked',
            'url': 'https://unranked.example/',
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
      'unranked',
    ]);
    expect(info.repositories.first.priority, 10);
    expect(info.repositories[1].priority, 20);
    expect(info.repositories[1].enabled, isFalse);
    expect(info.repositories.last.priority, isNull);
    expect(info.repositories.last.enabled, isNull);
  });

  test('parses keyed repository maps and bare URL values', () {
    final info = SystemInfo.fromJson({
      'data': {
        'repository_info': {
          'primary': {
            'url': 'https://primary.example/',
            'priority': 1,
          },
          'secondary': 'https://secondary.example/',
        },
      },
    });

    expect(info.repositories, hasLength(2));
    expect(info.repositories[0].name, 'primary');
    expect(info.repositories[0].url, 'https://primary.example/');
    expect(info.repositories[0].priority, 1);
    expect(info.repositories[1].name, 'secondary');
    expect(info.repositories[1].url, 'https://secondary.example/');
    expect(info.repositories[1].priority, isNull);
  });

  test('parses explicit flat repository fields without using mirror data', () {
    final info = SystemInfo.fromJson({
      'data': {
        'repository_name': 'primary',
        'repository_url': 'https://primary.example/',
        'repository_priority': '3',
        'repository_enabled': 'yes',
        'package_mirror_url': 'https://packages.example/',
      },
    });

    expect(info.packageMirrorUrl, 'https://packages.example/');
    expect(info.repositories, hasLength(1));
    expect(info.repositories.single.name, 'primary');
    expect(info.repositories.single.url, 'https://primary.example/');
    expect(info.repositories.single.priority, 3);
    expect(info.repositories.single.enabled, isTrue);
  });

  test('ignores empty repository entries', () {
    final info = SystemInfo.fromJson({
      'data': {
        'repositories': [
          <String, dynamic>{},
          null,
          '',
        ],
      },
    });

    expect(info.repositories, isEmpty);
  });
}
