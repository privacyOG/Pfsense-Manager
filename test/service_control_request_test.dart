import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/models/system_service.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfsense_service.dart';

void main() {
  test('selected OpenVPN instance sends its exact pfREST service ID', () async {
    final client = _RecordingApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);

    final services = await service.getServices();
    final selected = services.singleWhere(
      (entry) => entry.name == 'openvpn' && entry.vpnId == '2',
    );

    await service.restartServiceInstance(selected);

    expect(client.postCalls, 1);
    expect(client.lastPostPath, '/api/v2/status/service');
    expect(
      client.lastPostData,
      {'id': 8, 'name': 'openvpn', 'action': 'restart'},
    );
  });

  test('duplicate OpenVPN names are not resolved arbitrarily', () async {
    final client = _RecordingApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);

    await service.getServices();
    client.resetPost();

    await expectLater(
      service.restartService('openvpn'),
      throwsA(isA<StateError>()),
    );
    expect(client.postCalls, 0);
  });

  test('unique service names continue to resolve to their service ID', () async {
    final client = _RecordingApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);

    await service.restartService('unbound');

    expect(client.postCalls, 1);
    expect(
      client.lastPostData,
      {'id': 2, 'name': 'unbound', 'action': 'restart'},
    );
  });

  test('instance start and stop actions keep the selected ID', () async {
    final client = _RecordingApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);
    final selected = (await service.getServices()).singleWhere(
      (entry) => entry.name == 'openvpn' && entry.vpnId == '1',
    );

    await service.startServiceInstance(selected);
    expect(
      client.lastPostData,
      {'id': 5, 'name': 'openvpn', 'action': 'start'},
    );

    await service.stopServiceInstance(selected);
    expect(
      client.lastPostData,
      {'id': 5, 'name': 'openvpn', 'action': 'stop'},
    );
  });

  test('an instance without a pfREST ID is rejected before dispatch', () async {
    final client = _RecordingApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);
    final unsafe = SystemService(
      name: 'openvpn',
      displayName: 'OpenVPN',
      running: true,
      mode: 'server',
      vpnId: '4',
    );

    await expectLater(
      service.restartServiceInstance(unsafe),
      throwsA(isA<StateError>()),
    );
    expect(client.postCalls, 0);
  });
}

class _RecordingApiClient extends PfSenseApiClient {
  _RecordingApiClient()
      : super(
          PfSenseProfile(
            id: 'service-instance-test',
            name: 'Service instance test',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  int postCalls = 0;
  String? lastPostPath;
  dynamic lastPostData;

  void resetPost() {
    postCalls = 0;
    lastPostPath = null;
    lastPostData = null;
  }

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path == '/api/v2/status/services') {
      return Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: <String, dynamic>{
          'data': <Map<String, dynamic>>[
            {
              'id': 5,
              'name': 'openvpn',
              'description': 'OpenVPN server',
              'enabled': true,
              'status': true,
              'mode': 'server',
              'vpnid': 1,
            },
            {
              'id': 8,
              'name': 'openvpn',
              'description': 'OpenVPN server',
              'enabled': true,
              'status': true,
              'mode': 'server',
              'vpnid': 2,
            },
            {
              'id': 2,
              'name': 'unbound',
              'description': 'DNS Resolver',
              'enabled': true,
              'status': true,
            },
          ],
        },
      );
    }
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <String, dynamic>{'data': <dynamic>[]},
    );
  }

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    postCalls++;
    lastPostPath = path;
    lastPostData = data;
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <String, dynamic>{'data': <String, dynamic>{}},
    );
  }
}
