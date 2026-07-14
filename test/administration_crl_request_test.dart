import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/administration_management.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/administration_management_service.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfrest_capability_service.dart';

void main() {
  test('certificate revocation uses the exact reported CRL endpoint', () async {
    final client = _AdministrationActionApiClient();
    final capabilityService = PfRestCapabilityService(
      client,
      profileId: 'administration-action-test',
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

  test('generated private keys are exposed once and excluded from safe data',
      () async {
    final client = _AdministrationActionApiClient();
    final capabilityService = PfRestCapabilityService(
      client,
      profileId: 'administration-certificate-test',
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

    final result = await service.runAction(
      AdministrationActionKind.generateCertificate,
      const {'descr': 'Generated certificate'},
    );

    expect(client.requests.single.path, '/api/v2/system/certificate/generate');
    expect(result.ephemeralSecret, 'private-key-material');
    expect(result.safeData, isNot(contains('prv')));
    expect(result.safeData['crt'], 'certificate-material');
  });
}

class _AdministrationActionApiClient extends PfSenseApiClient {
  _AdministrationActionApiClient()
      : super(
          PfSenseProfile(
            id: 'administration-action-test',
            name: 'Administration action test',
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
              'post': _operation(
                required: const ['parent_id', 'certref'],
                properties: const {
                  'parent_id': {'type': 'integer'},
                  'certref': {'type': 'string'},
                  'reason': {'type': 'integer'},
                },
              ),
            },
            '/api/v2/system/certificate/generate': {
              'post': _operation(
                required: const ['descr'],
                properties: const {
                  'descr': {'type': 'string'},
                },
              ),
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
    if (path == '/api/v2/system/certificate/generate') {
      return _response(path, {
        'data': {
          'descr': data['descr'],
          'crt': 'certificate-material',
          'prv': 'private-key-material',
        },
      });
    }
    return _response(path, {'data': data});
  }
}

Map<String, dynamic> _operation({
  required List<String> required,
  required Map<String, dynamic> properties,
}) {
  return {
    'tags': ['SYSTEM'],
    'requestBody': {
      'content': {
        'application/json': {
          'schema': {
            'type': 'object',
            'required': required,
            'properties': properties,
          },
        },
      },
    },
  };
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