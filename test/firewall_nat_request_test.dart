import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_nat.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/firewall_nat_service.dart';
import 'package:pfsense_manager/utils/api_exception.dart';

void main() {
  test('uses plural GET endpoints for each NAT collection', () async {
    final client = _NatApiClient();
    final service = FirewallNatService(client);
    addTearDown(client.dispose);

    await service.listPortForwards();
    await service.listOneToOneMappings();
    await service.listOutboundMappings();
    await service.getOutboundMode();

    expect(client.requests.map((request) => request.path), [
      FirewallNatService.portForwardsPath,
      FirewallNatService.oneToOneMappingsPath,
      FirewallNatService.outboundMappingsPath,
      FirewallNatService.outboundModePath,
    ]);
    expect(client.requests.every((request) => request.method == 'GET'), isTrue);
  });

  test('creates a port forward then applies only after the write succeeds',
      () async {
    final client = _NatApiClient();
    final service = FirewallNatService(client);
    addTearDown(client.dispose);
    final rule = NatPortForward(
      interface: 'wan',
      ipProtocol: 'inet',
      protocol: 'tcp',
      source: 'any',
      destination: 'wanip',
      destinationPort: '443',
      target: '192.168.1.20',
      localPort: '8443',
      associatedRuleId: 'new',
    );

    await service.createPortForward(rule);

    expect(client.requests, hasLength(2));
    expect(client.requests[0].method, 'POST');
    expect(client.requests[0].path, FirewallNatService.portForwardPath);
    expect(client.requests[0].data['associated_rule_id'], 'new');
    expect(client.requests[0].data['destination_port'], '443');
    expect(client.requests[1].method, 'POST');
    expect(client.requests[1].path, FirewallNatService.applyPath);
  });

  test('does not apply when a NAT write fails', () async {
    final client = _NatApiClient(failPath: FirewallNatService.portForwardPath);
    final service = FirewallNatService(client);
    addTearDown(client.dispose);
    final rule = NatPortForward(
      interface: 'wan',
      ipProtocol: 'inet',
      protocol: 'tcp',
      source: 'any',
      destination: 'wanip',
      destinationPort: '443',
      target: '192.168.1.20',
      localPort: '443',
    );

    await expectLater(
      service.createPortForward(rule),
      throwsA(isA<ApiException>()),
    );

    expect(client.requests, hasLength(1));
    expect(client.requests.single.path, FirewallNatService.portForwardPath);
    expect(
      client.requests.where((request) => request.path == FirewallNatService.applyPath),
      isEmpty,
    );
  });

  test('updates 1:1 mapping with ID and preserves unknown editable fields',
      () async {
    final client = _NatApiClient();
    final service = FirewallNatService(client);
    addTearDown(client.dispose);
    final mapping = NatOneToOneMapping.fromJson({
      'id': 11,
      'interface': 'wan',
      'ipprotocol': 'inet',
      'external': '203.0.113.11',
      'source': '192.168.1.11',
      'destination': 'any',
      'custom_option': 'keep',
    });

    await service.updateOneToOneMapping(mapping);

    expect(client.requests[0].method, 'PATCH');
    expect(client.requests[0].path, FirewallNatService.oneToOneMappingPath);
    expect(client.requests[0].data['id'], 11);
    expect(client.requests[0].data['custom_option'], 'keep');
    expect(client.requests[1].path, FirewallNatService.applyPath);
  });

  test('changes outbound mode using the pfREST advanced value then applies',
      () async {
    final client = _NatApiClient();
    final service = FirewallNatService(client);
    addTearDown(client.dispose);

    final result = await service.updateOutboundMode(OutboundNatMode.advanced);

    expect(result, OutboundNatMode.advanced);
    expect(client.requests[0].method, 'PATCH');
    expect(client.requests[0].path, FirewallNatService.outboundModePath);
    expect(client.requests[0].data, {'mode': 'advanced'});
    expect(client.requests[1].path, FirewallNatService.applyPath);
  });

  test('deletes outbound mapping with query ID then applies', () async {
    final client = _NatApiClient();
    final service = FirewallNatService(client);
    addTearDown(client.dispose);

    await service.deleteOutboundMapping(19);

    expect(client.requests[0].method, 'DELETE');
    expect(client.requests[0].path, FirewallNatService.outboundMappingPath);
    expect(client.requests[0].queryParameters, {'id': '19'});
    expect(client.requests[1].path, FirewallNatService.applyPath);
  });

  test('toggle updates the complete existing mapping instead of a partial patch',
      () async {
    final client = _NatApiClient();
    final service = FirewallNatService(client);
    addTearDown(client.dispose);
    final mapping = NatOutboundMapping.fromJson({
      'id': 5,
      'interface': 'wan',
      'protocol': 'udp',
      'source': '192.168.50.0/24',
      'destination': 'any',
      'target': 'wanip',
      'target_subnet': 128,
      'poolopts': 'round-robin',
      'custom_option': 'preserve',
    });

    await service.setOutboundMappingEnabled(mapping, false);

    final payload = client.requests[0].data;
    expect(payload['id'], 5);
    expect(payload['disabled'], isTrue);
    expect(payload['source'], '192.168.50.0/24');
    expect(payload['target'], 'wanip');
    expect(payload['poolopts'], 'round-robin');
    expect(payload['custom_option'], 'preserve');
  });
}

class _NatApiClient extends PfSenseApiClient {
  _NatApiClient({this.failPath})
      : super(
          PfSenseProfile(
            id: 'nat-test',
            name: 'NAT test',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  final String? failPath;
  final List<_Request> requests = [];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    _record('GET', path, queryParameters: queryParameters);
    if (path == FirewallNatService.outboundModePath) {
      return _response(path, {'data': {'mode': 'hybrid'}});
    }
    return _response(path, {'data': <dynamic>[]});
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    _record('POST', path, data: data);
    _fail(path);
    if (path == FirewallNatService.applyPath) {
      return _response(path, {'data': <String, dynamic>{}});
    }
    return _response(path, {
      'data': {
        'id': 1,
        if (data is Map) ...Map<String, dynamic>.from(data),
      },
    });
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    _record('PATCH', path, data: data);
    _fail(path);
    return _response(path, {
      'data': data is Map ? Map<String, dynamic>.from(data) : data,
    });
  }

  @override
  Future<Response<dynamic>> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    _record('DELETE', path, queryParameters: queryParameters);
    _fail(path);
    return _response(path, {'data': <String, dynamic>{}});
  }

  void _record(
    String method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) {
    requests.add(
      _Request(
        method: method,
        path: path,
        data: data is Map ? Map<String, dynamic>.from(data) : data,
        queryParameters: queryParameters == null
            ? null
            : Map<String, dynamic>.from(queryParameters),
      ),
    );
  }

  void _fail(String path) {
    if (path == failPath) {
      throw const ApiException('NAT write rejected', 422);
    }
  }

  Response<dynamic> _response(String path, dynamic data) {
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: data,
    );
  }
}

class _Request {
  const _Request({
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
