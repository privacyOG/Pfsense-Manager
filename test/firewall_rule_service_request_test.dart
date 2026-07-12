import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_rule.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/firewall_rule_service.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  FirewallRule rule({String? id = '4'}) => FirewallRule(
        id: id,
        interface: 'lan',
        protocol: 'tcp',
        sourceNetwork: 'any',
        destinationNetwork: '192.168.1.10',
        destinationPort: '443',
        description: 'HTTPS',
      );

  test('list uses the plural endpoint and exact interface filter', () async {
    final adapter = _RecordingAdapter();
    final client = _client(adapter);
    final service = FirewallRuleService(client);
    addTearDown(client.dispose);

    final rules = await service.list(interface: 'lan');

    expect(rules, hasLength(1));
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, FirewallRuleService.rulesPath);
    expect(adapter.requests.single.queryParameters, {'interface': 'lan'});
  });

  test('create uses singular endpoint and applies exactly once', () async {
    final adapter = _RecordingAdapter();
    final client = _client(adapter);
    final service = FirewallRuleService(client);
    addTearDown(client.dispose);

    await service.create(rule(id: null));

    expect(adapter.requests.map((request) => request.method), ['POST', 'POST']);
    expect(adapter.requests.map((request) => request.path), [
      FirewallRuleService.rulePath,
      '/api/v2/firewall/apply',
    ]);
    expect(adapter.requests.first.data['interface'], ['lan']);
    expect(adapter.requests.first.data['destination_port'], '443');
  });

  test('update sends the numeric ID and applies exactly once', () async {
    final adapter = _RecordingAdapter();
    final client = _client(adapter);
    final service = FirewallRuleService(client);
    addTearDown(client.dispose);

    await service.update(rule().copyWith(gateway: 'WAN_GW'));

    expect(adapter.requests.map((request) => request.method), ['PATCH', 'POST']);
    expect(adapter.requests.first.path, FirewallRuleService.rulePath);
    expect(adapter.requests.first.data['id'], 4);
    expect(adapter.requests.first.data['gateway'], 'WAN_GW');
    expect(adapter.requests.last.path, '/api/v2/firewall/apply');
  });

  test('delete uses singular endpoint and applies exactly once', () async {
    final adapter = _RecordingAdapter();
    final client = _client(adapter);
    final service = FirewallRuleService(client);
    addTearDown(client.dispose);

    await service.delete(rule());

    expect(adapter.requests.map((request) => request.method), ['DELETE', 'POST']);
    expect(adapter.requests.first.path, FirewallRuleService.rulePath);
    expect(adapter.requests.first.queryParameters, {'id': '4'});
    expect(adapter.requests.last.path, '/api/v2/firewall/apply');
  });

  test('a rejected write never triggers firewall apply', () async {
    final adapter = _RecordingAdapter(failRuleWrites: true);
    final client = _client(adapter);
    final service = FirewallRuleService(client);
    addTearDown(client.dispose);

    await expectLater(
      service.create(rule(id: null)),
      throwsA(isA<ApiException>()),
    );

    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.path, FirewallRuleService.rulePath);
    expect(
      adapter.requests.any((request) => request.path == '/api/v2/firewall/apply'),
      isFalse,
    );
  });

  test('invalid advanced combinations are rejected before HTTP', () async {
    final adapter = _RecordingAdapter();
    final client = _client(adapter);
    final service = FirewallRuleService(client);
    addTearDown(client.dispose);

    await expectLater(
      service.create(
        rule(id: null).copyWith(
          interfaces: const ['wan', 'lan'],
          floating: false,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(adapter.requests, isEmpty);
  });
}

PfSenseApiClient _client(_RecordingAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return PfSenseApiClient(
    PfSenseProfile(
      id: 'firewall-rule-request-test',
      name: 'Firewall rule request test',
      host: 'firewall.example.test',
      username: 'api-user',
      apiKey: 'test-key',
    ),
    dio: dio,
  );
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.data,
  });

  final String method;
  final String path;
  final Map<String, dynamic> queryParameters;
  final dynamic data;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.failRuleWrites = false});

  final bool failRuleWrites;
  final List<_RecordedRequest> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      _RecordedRequest(
        method: options.method,
        path: options.path,
        queryParameters: Map<String, dynamic>.from(options.queryParameters),
        data: options.data,
      ),
    );

    if (failRuleWrites &&
        options.path == FirewallRuleService.rulePath &&
        options.method != 'GET') {
      return _jsonBody(
        {'message': 'Rule validation failed'},
        statusCode: 400,
      );
    }

    if (options.path == FirewallRuleService.rulesPath) {
      return _jsonBody({
        'data': [
          {
            'id': 4,
            'type': 'pass',
            'interface': ['lan'],
            'ipprotocol': 'inet',
            'protocol': 'tcp',
            'source': 'any',
            'destination': '192.168.1.10',
            'destination_port': '443',
          },
        ],
      });
    }

    if (options.path == FirewallRuleService.rulePath) {
      final data = options.data is Map
          ? Map<String, dynamic>.from(options.data as Map)
          : <String, dynamic>{};
      data.putIfAbsent('id', () => 4);
      return _jsonBody({'data': data});
    }

    if (options.path == '/api/v2/firewall/apply') {
      return _jsonBody({'data': <String, dynamic>{'applied': true}});
    }

    return _jsonBody({'message': 'Unexpected path'}, statusCode: 404);
  }

  ResponseBody _jsonBody(
    Map<String, dynamic> value, {
    int statusCode = 200,
  }) {
    return ResponseBody.fromString(
      jsonEncode(value),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
