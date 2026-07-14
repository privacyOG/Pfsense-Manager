import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/administration_management.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/administration_management_service.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfrest_capability_service.dart';

void main() {
  test('certificate revocation uses the exact reported CRL endpoint', () async {
    final client = _CrlApiClient();
    final capabilityService = PfRestCapabilityService(
      client,
      profileId: 'administration-crl-test',
    );
    final service = AdministrationManagementService(
      client,
      capabilityService: capabilityService,
    );
    addTearDown(() {
      capabilityService.dispose();
      client.dispose();
    });
    await capabilityService.refresh();
    client.requests.clear();

    await service.runAction(
      AdministrationActionKind.revokeCertificate,
      const {
        'parent_id': 3,
        'certref': 'certificate-ref',
        'reason': 1,
      },
    );

    expect(client.requests.single.method, 'POST');
    expect(
      client.requests.single.path,
      '/api/v2/system/crl/revoked_certificate',
    );
    expect(
      client.requests.single.data,
      {
        'parent_id': 3,
        'certref': 'certificate-ref',
        'reason': 1,
      },
    );
  });
}

class _CrlApiClient extends PfSenseApiClient {
  _CrlApiClient()
      : super(
          PfSenseProfile(
            id: 'administration-crl-test',
            name: 'Administration CRL test',
            host: 'firewall.example.test',
            username: 'admin',
            authMode: PfSenseAuthMode.apiKey,
            apiKey: 'test-key',
          ),
        );

  final List<_Request> requests = [];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    requests.add(_Request('GET', path, queryParameters: queryParameters));
    if (path == pfRestOpenApiSchemaPath) {
      return _response(path, {
        'data': {
          'openapi': '3.0.3',
          'paths': {
            '/api/v2/system/crl/revoked_certificate': {
              'post': {
                'tags': ['SYSTEM'],
                'requestBody': {
                  'content': {
                    'application/json': {
                      'schema': {
                        'type': 'object',
                        'required': ['parent_id', 'certref'],
                        'properties': {
                          'parent_id': {'type': 'integer'},
                          'certref': {'type': 'string'},
                          'reason': {'type': 'integer'},
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      });
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    requests.add(_Request('POST', path, data: data));
    return _response(path, {'data': data});
  }
}

class _Request {
  const _Request(
    this.method,
    this.path, {
    this.data,
    this.queryParameters,
  });

  final String method;
  final String path;
  final dynamic data;
  final Map<String, dynamic>? queryParameters;
}

Response<dynamic> _response(String path, dynamic data) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: data,
  );
}