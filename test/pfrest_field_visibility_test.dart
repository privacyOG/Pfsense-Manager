import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/services/pfrest_capability_parser.dart';

void main() {
  test('parses descriptions and read-only or write-only field metadata', () {
    final capabilities = parsePfRestCapabilities(
      profileId: 'visibility-test',
      loadedAt: DateTime.utc(2026, 7, 14),
      document: {
        'openapi': '3.0.3',
        'paths': {
          '/api/v2/vpn/wireguard/tunnel': {
            'patch': {
              'requestBody': {
                'content': {
                  'application/json': {
                    'schema': {
                      'type': 'object',
                      'required': ['id'],
                      'properties': {
                        'id': {
                          'type': 'integer',
                          'readOnly': true,
                          'description': 'Server-generated identifier.',
                        },
                        'privatekey': {
                          'type': 'string',
                          'writeOnly': true,
                          'format': 'password',
                          'description': 'WireGuard private key.',
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    );

    final id = capabilities.requestField(
      '/api/v2/vpn/wireguard/tunnel',
      'PATCH',
      'id',
      location: 'body',
    );
    final privateKey = capabilities.requestField(
      '/api/v2/vpn/wireguard/tunnel',
      'PATCH',
      'privatekey',
      location: 'body',
    );

    expect(id?.readOnly, isTrue);
    expect(id?.writeOnly, isFalse);
    expect(id?.description, 'Server-generated identifier.');
    expect(privateKey?.readOnly, isFalse);
    expect(privateKey?.writeOnly, isTrue);
    expect(privateKey?.format, 'password');
    expect(privateKey?.description, 'WireGuard private key.');
  });
}
