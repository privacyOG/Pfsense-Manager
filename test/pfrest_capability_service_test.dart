import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfrest_capability_service.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  test('loads and caches a profile-scoped capability snapshot', () async {
    final client = _CapabilityApiClient([
      _schemaResponse(
        version: '2.4.3',
        paths: {
          '/api/v2/status/system': {'get': <String, dynamic>{}},
        },
      ),
    ]);
    final service = PfRestCapabilityService(
      client,
      profileId: 'profile-a',
      clock: () => DateTime.utc(2026, 7, 12, 12),
    );
    addTearDown(() {
      service.dispose();
      client.dispose();
    });

    final snapshot = await service.refresh();

    expect(client.callCount, 1);
    expect(snapshot.profileId, 'profile-a');
    expect(snapshot.apiVersion, '2.4.3');
    expect(snapshot.loadedAt, DateTime.utc(2026, 7, 12, 12));
    expect(service.current, same(snapshot));
    expect(service.supports('/api/v2/status/system', 'GET'), isTrue);
  });

  test('deduplicates concurrent schema refresh requests', () async {
    final client = _ControlledCapabilityApiClient();
    final service = PfRestCapabilityService(client, profileId: 'profile-a');
    addTearDown(() {
      service.dispose();
      client.dispose();
    });

    final first = service.refresh();
    final duplicate = service.refresh();

    expect(identical(first, duplicate), isTrue);
    expect(client.callCount, 1);

    client.complete(
      _schemaResponse(
        version: '2.4.3',
        paths: {
          '/api/v2/status/system': {'get': <String, dynamic>{}},
        },
      ),
    );
    await first;
  });

  test('permission failure becomes a limited state without throwing', () async {
    final client = _CapabilityApiClient([
      const ApiException('Schema privilege required', 403),
    ]);
    final service = PfRestCapabilityService(client, profileId: 'restricted');
    addTearDown(() {
      service.dispose();
      client.dispose();
    });

    final snapshot = await service.refresh();

    expect(snapshot.isLimited, isTrue);
    expect(snapshot.profileId, 'restricted');
    expect(snapshot.issue, PfRestCapabilityIssue.permissionDenied);
    expect(snapshot.message, contains('(403)'));
    expect(snapshot.message, contains('Basic features remain available'));
    expect(snapshot.operations, isEmpty);
  });

  test('missing and malformed schemas produce distinct limited states',
      () async {
    final unavailableClient = _CapabilityApiClient([
      const ApiException('Not found', 404),
    ]);
    final malformedClient = _CapabilityApiClient([
      Response<dynamic>(
        requestOptions: RequestOptions(path: pfRestOpenApiSchemaPath),
        statusCode: 200,
        data: {'data': 'not-json'},
      ),
    ]);
    final unavailable = PfRestCapabilityService(
      unavailableClient,
      profileId: 'unavailable',
    );
    final malformed = PfRestCapabilityService(
      malformedClient,
      profileId: 'malformed',
    );
    addTearDown(() {
      unavailable.dispose();
      malformed.dispose();
      unavailableClient.dispose();
      malformedClient.dispose();
    });

    expect(
      (await unavailable.refresh()).issue,
      PfRestCapabilityIssue.schemaUnavailable,
    );
    expect(
      (await malformed.refresh()).issue,
      PfRestCapabilityIssue.invalidSchema,
    );
  });

  test('refresh replaces the cache when API or package paths change', () async {
    final client = _CapabilityApiClient([
      _schemaResponse(
        version: '2.4.3',
        paths: {
          '/api/v2/status/system': {'get': <String, dynamic>{}},
        },
      ),
      _schemaResponse(
        version: '2.5.0',
        paths: {
          '/api/v2/status/system': {'get': <String, dynamic>{}},
          '/api/v2/vpn/wireguard/tunnels': {
            'get': {
              'tags': ['WireGuard'],
            },
          },
        },
      ),
    ]);
    final service = PfRestCapabilityService(client, profileId: 'profile-a');
    addTearDown(() {
      service.dispose();
      client.dispose();
    });

    final first = await service.refresh();
    final second = await service.refresh();

    expect(first.apiVersion, '2.4.3');
    expect(second.apiVersion, '2.5.0');
    expect(second.schemaFingerprint, isNot(first.schemaFingerprint));
    expect(
      second.supports('/api/v2/vpn/wireguard/tunnels', 'GET'),
      isTrue,
    );
    expect(second.packageTags, contains('WireGuard'));
    expect(service.current, same(second));
  });

  test('capability data never leaks between profile services', () async {
    final firstClient = _CapabilityApiClient([
      _schemaResponse(
        version: '2.4.3',
        paths: {
          '/api/v2/status/system': {'get': <String, dynamic>{}},
        },
      ),
    ]);
    final secondClient = _CapabilityApiClient([
      _schemaResponse(
        version: '2.4.3',
        paths: {
          '/api/v2/status/interfaces': {'get': <String, dynamic>{}},
        },
      ),
    ]);
    final first = PfRestCapabilityService(firstClient, profileId: 'profile-a');
    final second = PfRestCapabilityService(secondClient, profileId: 'profile-b');
    addTearDown(() {
      first.dispose();
      second.dispose();
      firstClient.dispose();
      secondClient.dispose();
    });

    await first.refresh();
    await second.refresh();

    expect(first.current.profileId, 'profile-a');
    expect(second.current.profileId, 'profile-b');
    expect(first.supports('/api/v2/status/system', 'GET'), isTrue);
    expect(first.supports('/api/v2/status/interfaces', 'GET'), isFalse);
    expect(second.supports('/api/v2/status/system', 'GET'), isFalse);
    expect(second.supports('/api/v2/status/interfaces', 'GET'), isTrue);
  });
}

Response<dynamic> _schemaResponse({
  required String version,
  required Map<String, dynamic> paths,
}) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: pfRestOpenApiSchemaPath),
    statusCode: 200,
    data: {
      'data': {
        'openapi': '3.0.3',
        'info': {'version': version},
        'paths': paths,
      },
    },
  );
}

class _CapabilityApiClient extends PfSenseApiClient {
  _CapabilityApiClient(this.responses)
      : super(
          PfSenseProfile(
            id: 'capability-client',
            name: 'Capability client',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  final List<Object> responses;
  int callCount = 0;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    expect(path, pfRestOpenApiSchemaPath);
    callCount++;
    if (responses.isEmpty) throw StateError('No schema response queued.');
    final response = responses.removeAt(0);
    if (response is Error) throw response;
    if (response is Exception) throw response;
    return response as Response<dynamic>;
  }
}

class _ControlledCapabilityApiClient extends PfSenseApiClient {
  _ControlledCapabilityApiClient()
      : super(
          PfSenseProfile(
            id: 'controlled-capability-client',
            name: 'Controlled capability client',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  final Completer<Response<dynamic>> _completer = Completer<Response<dynamic>>();
  int callCount = 0;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    expect(path, pfRestOpenApiSchemaPath);
    callCount++;
    return _completer.future;
  }

  void complete(Response<dynamic> response) {
    _completer.complete(response);
  }
}
