import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_alias.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/firewall_alias_service.dart';

void main() {
  test('lists aliases from the plural endpoint and sorts by name', () async {
    final client = _AliasApiClient();
    final service = FirewallAliasService(client);
    addTearDown(client.dispose);

    final aliases = await service.list();

    expect(client.calls, hasLength(1));
    expect(client.calls.single.method, 'GET');
    expect(client.calls.single.path, FirewallAliasService.collectionPath);
    expect(aliases.map((alias) => alias.name), ['ALPHA', 'ZULU']);
  });

  test('creates through the singular endpoint then applies the firewall',
      () async {
    final client = _AliasApiClient();
    final service = FirewallAliasService(client);
    addTearDown(client.dispose);
    const alias = FirewallAlias(
      name: 'WEB_HOSTS',
      type: 'host',
      description: 'Web servers',
      entries: [
        FirewallAliasEntry(value: '192.0.2.10', description: 'Primary'),
      ],
    );

    final created = await service.create(alias);

    expect(client.calls.map((call) => '${call.method} ${call.path}'), [
      'POST /api/v2/firewall/alias',
      'POST /api/v2/firewall/apply',
    ]);
    expect(client.calls.first.data, {
      'name': 'WEB_HOSTS',
      'type': 'host',
      'descr': 'Web servers',
      'address': ['192.0.2.10'],
      'detail': ['Primary'],
    });
    expect(created.id, 12);
    expect(created.name, 'WEB_HOSTS');
  });

  test('updates by ID without submitting the immutable name', () async {
    final client = _AliasApiClient();
    final service = FirewallAliasService(client);
    addTearDown(client.dispose);
    const alias = FirewallAlias(
      id: 12,
      name: 'WEB_HOSTS',
      type: 'host',
      description: 'Updated',
      entries: [FirewallAliasEntry(value: '192.0.2.20')],
    );

    await service.update(alias);

    expect(client.calls.map((call) => '${call.method} ${call.path}'), [
      'PATCH /api/v2/firewall/alias',
      'POST /api/v2/firewall/apply',
    ]);
    expect(client.calls.first.data, {
      'id': 12,
      'type': 'host',
      'descr': 'Updated',
      'address': ['192.0.2.20'],
      'detail': [''],
    });
    expect((client.calls.first.data as Map).containsKey('name'), isFalse);
  });

  test('rejects update attempts without an alias ID', () async {
    final client = _AliasApiClient();
    final service = FirewallAliasService(client);
    addTearDown(client.dispose);

    await expectLater(
      service.update(
        const FirewallAlias(
          name: 'NO_ID',
          type: 'host',
          entries: [FirewallAliasEntry(value: '192.0.2.1')],
        ),
      ),
      throwsArgumentError,
    );
    expect(client.calls, isEmpty);
  });

  test('deletes by singular ID then applies the firewall', () async {
    final client = _AliasApiClient();
    final service = FirewallAliasService(client);
    addTearDown(client.dispose);

    await service.delete(18);

    expect(client.calls.map((call) => '${call.method} ${call.path}'), [
      'DELETE /api/v2/firewall/alias',
      'POST /api/v2/firewall/apply',
    ]);
    expect(client.calls.first.queryParameters, {'id': '18'});
  });

  test('does not apply when a write request fails', () async {
    final client = _AliasApiClient(failWrites: true);
    final service = FirewallAliasService(client);
    addTearDown(client.dispose);

    await expectLater(
      service.create(
        const FirewallAlias(
          name: 'FAILED_ALIAS',
          type: 'host',
          entries: [FirewallAliasEntry(value: '192.0.2.1')],
        ),
      ),
      throwsStateError,
    );

    expect(client.calls, hasLength(1));
    expect(client.calls.single.path, FirewallAliasService.itemPath);
  });
}

class _AliasApiClient extends PfSenseApiClient {
  _AliasApiClient({this.failWrites = false})
      : super(
          PfSenseProfile(
            id: 'alias-request-test',
            name: 'Alias request test',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  final bool failWrites;
  final List<_RecordedCall> calls = [];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add(
      _RecordedCall(
        method: 'GET',
        path: path,
        queryParameters: queryParameters,
      ),
    );
    return _response(path, {
      'data': [
        {
          'id': 2,
          'name': 'ZULU',
          'type': 'network',
          'address': ['198.51.100.0/24'],
        },
        {
          'id': 1,
          'name': 'ALPHA',
          'type': 'host',
          'address': ['192.0.2.1'],
        },
      ],
    });
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    calls.add(_RecordedCall(method: 'POST', path: path, data: data));
    if (failWrites && path == FirewallAliasService.itemPath) {
      throw StateError('write failed');
    }
    if (path == FirewallAliasService.itemPath) {
      return _response(path, {
        'data': {
          'id': 12,
          ...Map<String, dynamic>.from(data as Map),
        },
      });
    }
    return _response(path, {'data': <String, dynamic>{}});
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    calls.add(_RecordedCall(method: 'PATCH', path: path, data: data));
    if (failWrites) throw StateError('write failed');
    return _response(path, {'data': data});
  }

  @override
  Future<Response<dynamic>> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add(
      _RecordedCall(
        method: 'DELETE',
        path: path,
        queryParameters: queryParameters,
      ),
    );
    if (failWrites) throw StateError('write failed');
    return _response(path, {'data': <String, dynamic>{}});
  }

  Response<dynamic> _response(String path, dynamic data) {
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: data,
    );
  }
}

class _RecordedCall {
  const _RecordedCall({
    required this.method,
    required this.path,
    this.data,
    this.queryParameters,
  });

  final String method;
  final String path;
  final dynamic data;
  final Map<String, dynamic>? queryParameters;
}
