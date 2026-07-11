import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/system_log_source.dart';

void main() {
  test('rejects absolute, authority-style and traversal log paths', () {
    final sources = systemLogSourcesFromOpenApi({
      'paths': {
        'https://other.example/status/logs/system': {
          'get': <String, dynamic>{},
        },
        '//other.example/status/logs/dhcp': {
          'get': <String, dynamic>{},
        },
        '/api/v2/status/logs/../logs/auth': {
          'get': <String, dynamic>{},
        },
        '/api/v2/status/logs/openvpn?redirect=1': {
          'get': <String, dynamic>{},
        },
        '/api/v2/status/logs/restapi#fragment': {
          'get': <String, dynamic>{},
        },
      },
    });

    expect(sources, isEmpty);
  });

  test('accepts a relative custom prefix without changing the path', () {
    final sources = systemLogSourcesFromOpenApi({
      'paths': {
        '/custom/api/status/logs/system': {
          'get': <String, dynamic>{},
        },
      },
    });

    expect(sources.single.path, '/custom/api/status/logs/system');
  });
}
