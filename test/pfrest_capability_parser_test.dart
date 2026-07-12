import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/services/pfrest_capability_parser.dart';

void main() {
  test('parses methods, request fields, constraints and package tags', () {
    final capabilities = parsePfRestCapabilities(
      profileId: 'firewall-a',
      loadedAt: DateTime.utc(2026, 7, 12, 10),
      document: _representativeSchema(),
    );

    expect(capabilities.isAvailable, isTrue);
    expect(capabilities.profileId, 'firewall-a');
    expect(capabilities.apiVersion, '2.4.3');
    expect(capabilities.openApiVersion, '3.0.3');
    expect(capabilities.schemaFingerprint, hasLength(64));
    expect(capabilities.packageTags, containsAll(['Diagnostics', 'Firewall']));

    expect(
      capabilities.supports('/api/v2/diagnostics/ping', 'post'),
      isTrue,
    );
    expect(
      capabilities.supports('/api/v2/diagnostics/ping', 'get'),
      isFalse,
    );
    expect(
      capabilities.methodsForPath('/api/v2/firewall/rules'),
      {'GET', 'POST'},
    );

    final count = capabilities.requestField(
      '/api/v2/diagnostics/ping',
      'POST',
      'count',
      location: 'body',
    );
    expect(count, isNotNull);
    expect(count!.type, 'integer');
    expect(count.minimum, 1);
    expect(count.maximum, 10);
    expect(count.defaultValue, 4);
    expect(count.required, isFalse);
    expect(count.permitsNumber(1), isTrue);
    expect(count.permitsNumber(10), isTrue);
    expect(count.permitsNumber(11), isFalse);

    final host = capabilities.requestField(
      '/api/v2/diagnostics/ping',
      'POST',
      'host',
    );
    expect(host?.required, isTrue);
    expect(host?.minLength, 1);
    expect(host?.maxLength, 255);

    final limit = capabilities.requestField(
      '/api/v2/firewall/rules',
      'GET',
      'limit',
      location: 'query',
    );
    expect(limit?.minimum, 1);
    expect(limit?.maximum, 100);

    final ruleType = capabilities.requestField(
      '/api/v2/firewall/rules',
      'POST',
      'type',
      location: 'body',
    );
    expect(ruleType?.required, isTrue);
    expect(ruleType?.allowedValues, ['pass', 'block', 'reject']);

    final interface = capabilities.requestField(
      '/api/v2/firewall/rules',
      'POST',
      'interface',
      location: 'body',
    );
    expect(interface?.required, isTrue);
    expect(interface?.pattern, r'^[a-zA-Z0-9_]+$');
  });

  test('resolves wrapped JSON documents and parameter references', () {
    final document = jsonEncode({
      'openapi': '3.0.1',
      'info': {'version': '2.3.0'},
      'paths': {
        '/api/v2/status/system': {
          'parameters': [
            {'\$ref': '#/components/parameters/Limit'},
          ],
          'get': {
            'parameters': [
              {
                'name': 'limit',
                'in': 'query',
                'schema': {'type': 'integer', 'maximum': 25},
              },
            ],
          },
        },
      },
      'components': {
        'parameters': {
          'Limit': {
            'name': 'limit',
            'in': 'query',
            'schema': {'type': 'integer', 'minimum': 1, 'maximum': 200},
          },
        },
      },
    });

    final capabilities = parsePfRestCapabilities(
      profileId: 'wrapped',
      document: {'data': document},
    );

    final limit = capabilities.requestField(
      '/api/v2/status/system',
      'GET',
      'limit',
      location: 'query',
    );
    expect(limit?.minimum, isNull);
    expect(limit?.maximum, 25);
  });

  test('fingerprint is stable across map key ordering', () {
    final first = parsePfRestCapabilities(
      profileId: 'one',
      document: {
        'openapi': '3.0.0',
        'info': {'title': 'pfREST', 'version': '2.4.3'},
        'paths': {
          '/api/v2/status/system': {'get': <String, dynamic>{}},
        },
      },
    );
    final second = parsePfRestCapabilities(
      profileId: 'two',
      document: {
        'paths': {
          '/api/v2/status/system': {'get': <String, dynamic>{}},
        },
        'info': {'version': '2.4.3', 'title': 'pfREST'},
        'openapi': '3.0.0',
      },
    );

    expect(first.schemaFingerprint, second.schemaFingerprint);
    expect(first.profileId, isNot(second.profileId));
  });

  test('ignores unsafe paths and unsupported path-item keys', () {
    final capabilities = parsePfRestCapabilities(
      profileId: 'safe',
      document: {
        'paths': {
          'https://other.example/api/v2/status/system': {
            'get': <String, dynamic>{},
          },
          '//other.example/api/v2/status/interfaces': {
            'get': <String, dynamic>{},
          },
          '/api/v2/status/../status/gateways': {
            'get': <String, dynamic>{},
          },
          '/api/v2/status/services': {
            'summary': 'Path summary',
            'parameters': <dynamic>[],
            'get': <String, dynamic>{},
          },
        },
      },
    );

    expect(capabilities.operations, hasLength(1));
    expect(capabilities.supports('/api/v2/status/services', 'GET'), isTrue);
  });

  test('rejects missing or malformed OpenAPI paths', () {
    expect(
      () => parsePfRestCapabilities(profileId: 'bad', document: 'not-json'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parsePfRestCapabilities(
        profileId: 'bad',
        document: {'openapi': '3.0.0'},
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

Map<String, dynamic> _representativeSchema() {
  return {
    'openapi': '3.0.3',
    'info': {'title': 'pfREST', 'version': '2.4.3'},
    'tags': [
      {'name': 'Diagnostics'},
    ],
    'paths': {
      '/api/v2/diagnostics/ping': {
        'post': {
          'operationId': 'postDiagnosticsPing',
          'summary': 'Run ping',
          'tags': ['Diagnostics'],
          'requestBody': {
            'required': true,
            'content': {
              'application/json': {
                'schema': {
                  'type': 'object',
                  'required': ['host'],
                  'properties': {
                    'host': {
                      'type': 'string',
                      'minLength': 1,
                      'maxLength': 255,
                    },
                    'count': {
                      'type': 'integer',
                      'minimum': 1,
                      'maximum': 10,
                      'default': 4,
                    },
                    'source_address': {
                      'type': 'string',
                      'format': 'ip',
                    },
                  },
                },
              },
            },
          },
        },
      },
      '/api/v2/firewall/rules': {
        'get': {
          'tags': ['Firewall'],
          'parameters': [
            {
              'name': 'limit',
              'in': 'query',
              'schema': {
                'type': 'integer',
                'minimum': 1,
                'maximum': 100,
              },
            },
          ],
        },
        'post': {
          'tags': ['Firewall'],
          'requestBody': {
            'content': {
              'application/json': {
                'schema': {'\$ref': '#/components/schemas/FirewallRule'},
              },
            },
          },
        },
      },
    },
    'components': {
      'schemas': {
        'FirewallRuleBase': {
          'type': 'object',
          'required': ['type'],
          'properties': {
            'type': {
              'type': 'string',
              'enum': ['pass', 'block', 'reject'],
            },
          },
        },
        'FirewallRule': {
          'allOf': [
            {'\$ref': '#/components/schemas/FirewallRuleBase'},
            {
              'type': 'object',
              'required': ['interface'],
              'properties': {
                'interface': {
                  'type': 'string',
                  'pattern': r'^[a-zA-Z0-9_]+$',
                },
              },
            },
          ],
        },
      },
    },
  };
}
