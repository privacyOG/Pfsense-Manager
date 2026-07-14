import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/system_log_source.dart';
import 'package:pfsense_manager/screens/system_logs_screen.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  group('system log source discovery', () {
    test('maps standard GET log endpoints in a stable order', () {
      final sources = systemLogSourcesFromOpenApi({
        'openapi': '3.0.0',
        'paths': {
          '/api/v2/status/logs/restapi': {'get': <String, dynamic>{}},
          '/api/v2/status/logs/openvpn': {'get': <String, dynamic>{}},
          '/api/v2/status/logs/auth': {'get': <String, dynamic>{}},
          '/api/v2/status/logs/dhcp': {'get': <String, dynamic>{}},
          '/api/v2/status/logs/services': {'get': <String, dynamic>{}},
          '/api/v2/status/logs/system': {'get': <String, dynamic>{}},
        },
      });

      expect(sources.map((source) => source.label), [
        'System',
        'Services',
        'DHCP',
        'Authentication',
        'OpenVPN',
        'REST API',
      ]);
      expect(sources.map((source) => source.path), [
        '/api/v2/status/logs/system',
        '/api/v2/status/logs/services',
        '/api/v2/status/logs/dhcp',
        '/api/v2/status/logs/auth',
        '/api/v2/status/logs/openvpn',
        '/api/v2/status/logs/restapi',
      ]);
      expect(sources.every((source) => !source.isCustomExtension), isTrue);
    });

    test('hides unsupported DNS and gateway sources', () {
      final sources = systemLogSourcesFromOpenApi({
        'paths': {
          '/api/v2/status/logs/system': {'get': <String, dynamic>{}},
          '/api/v2/status/logs/dhcp': {'get': <String, dynamic>{}},
        },
      });

      expect(sources.map((source) => source.id), ['system', 'dhcp']);
      expect(sources.map((source) => source.label), isNot(contains('DNS')));
      expect(sources.map((source) => source.label), isNot(contains('Gateway')));
    });

    test('labels DNS and gateway endpoints as custom extensions', () {
      final sources = systemLogSourcesFromOpenApi({
        'paths': {
          '/api/v2/status/logs/unbound': {'get': <String, dynamic>{}},
          '/api/v2/status/logs/gateways': {'get': <String, dynamic>{}},
        },
      });

      expect(sources, hasLength(2));
      expect(sources[0].label, 'DNS Resolver (custom)');
      expect(sources[0].path, '/api/v2/status/logs/unbound');
      expect(sources[0].isCustomExtension, isTrue);
      expect(sources[1].label, 'Gateway (custom)');
      expect(sources[1].isCustomExtension, isTrue);
    });

    test('uses returned aliases and preserves the exact schema path', () {
      final sources = systemLogSourcesFromOpenApi({
        'paths': {
          '/custom/prefix/status/logs/service-manager': {
            'get': <String, dynamic>{},
          },
          '/custom/prefix/status/logs/dhcpd/': {'GET': <String, dynamic>{}},
          '/custom/prefix/status/logs/system-auth': {
            'get': <String, dynamic>{},
          },
          '/custom/prefix/status/logs/open-vpn': {
            'get': <String, dynamic>{},
          },
          '/custom/prefix/status/logs/rest_api': {
            'get': <String, dynamic>{},
          },
        },
      });

      expect(sources.map((source) => source.id), [
        'services',
        'dhcp',
        'authentication',
        'openvpn',
        'restapi',
      ]);
      expect(
        sources[0].path,
        '/custom/prefix/status/logs/service-manager',
      );
      expect(sources[0].logType, 'service-manager');
      expect(sources[1].path, '/custom/prefix/status/logs/dhcpd/');
      expect(sources[1].logType, 'dhcpd');
      expect(sources[2].path, '/custom/prefix/status/logs/system-auth');
      expect(sources[3].path, '/custom/prefix/status/logs/open-vpn');
      expect(sources[4].path, '/custom/prefix/status/logs/rest_api');
    });

    test('ignores non-GET operations and unrelated log paths', () {
      final sources = systemLogSourcesFromOpenApi({
        'paths': {
          '/api/v2/status/logs/system': {'post': <String, dynamic>{}},
          '/api/v2/status/logs/dhcp': {'delete': <String, dynamic>{}},
          '/api/v2/status/logs/firewall': {'get': <String, dynamic>{}},
          '/api/v2/status/system': {'get': <String, dynamic>{}},
        },
      });

      expect(sources, isEmpty);
    });

    test('parses wrapped and JSON-encoded OpenAPI documents', () {
      final schema = jsonEncode({
        'paths': {
          '/api/v2/status/logs/system': {'get': <String, dynamic>{}},
        },
      });

      final sources = systemLogSourcesFromOpenApi({'data': schema});

      expect(sources.single.id, 'system');
      expect(sources.single.path, '/api/v2/status/logs/system');
    });

    test('returns no sources for malformed schemas', () {
      expect(systemLogSourcesFromOpenApi('not-json'), isEmpty);
      expect(systemLogSourcesFromOpenApi({'data': <String, dynamic>{}}), isEmpty);
      expect(systemLogSourcesFromOpenApi(null), isEmpty);
    });
  });

  group('system log errors', () {
    const source = SystemLogSource(
      id: 'authentication',
      label: 'Authentication',
      path: '/api/v2/status/logs/auth',
      icon: Icons.verified_user_outlined,
    );

    test('preserves permission failures for supported endpoints', () {
      final message = systemLogErrorMessage(
        source,
        const ApiException('Read privilege required', 403),
      );

      expect(message, contains('Permission denied for Authentication logs (403)'));
      expect(message, contains('endpoint is supported'));
      expect(message, contains('Read privilege required'));
      expect(
        isUnsupportedSystemLogError(const ApiException('Forbidden', 403)),
        isFalse,
      );
    });

    test('distinguishes a stale endpoint from a permission failure', () {
      final message = systemLogErrorMessage(
        source,
        const ApiException('Not found', 404),
      );

      expect(
        isUnsupportedSystemLogError(const ApiException('Not found', 404)),
        isTrue,
      );
      expect(message, contains('reported by the OpenAPI schema'));
      expect(message, contains('Refresh the log sources'));
    });

    test('reports schema permission failures separately', () {
      final message = systemLogDiscoveryErrorMessage(
        const ApiException('Schema privilege required', 403),
      );

      expect(message, contains('OpenAPI schema (403)'));
      expect(message, contains(systemLogSchemaPath));
      expect(message, contains('Schema privilege required'));
    });
  });
}