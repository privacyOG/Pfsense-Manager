import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfsense_service.dart';

void main() {
  group('firewall rule interface filter', () {
    test('sends the pfREST interface field as the query parameter', () async {
      final client = _RecordingApiClient();
      final service = PfSenseService(client);
      addTearDown(service.dispose);

      await service.getFirewallRules(interface: 'wan');

      expect(client.lastPath, '/api/v2/firewall/rules');
      expect(client.lastQueryParameters, {'interface': 'wan'});
      expect(client.lastQueryParameters, isNot(contains('if')));
    });

    test('keeps the unfiltered request unchanged for All interfaces', () async {
      final client = _RecordingApiClient();
      final service = PfSenseService(client);
      addTearDown(service.dispose);

      await service.getFirewallRules();

      expect(client.lastPath, '/api/v2/firewall/rules');
      expect(client.lastQueryParameters, isEmpty);
    });
  });
}

class _RecordingApiClient extends PfSenseApiClient {
  _RecordingApiClient()
      : super(
          PfSenseProfile(
            id: 'firewall-filter-test',
            name: 'Firewall filter test',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  String? lastPath;
  Map<String, dynamic>? lastQueryParameters;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    lastPath = path;
    lastQueryParameters = queryParameters == null
        ? null
        : Map<String, dynamic>.from(queryParameters);
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <String, dynamic>{'data': <dynamic>[]},
    );
  }
}
