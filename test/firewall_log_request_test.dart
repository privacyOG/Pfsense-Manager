import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfsense_service.dart';

const recentBlockLine =
    '2026-07-11T01:00:00Z firewall filterlog: '
    '100,0,,1234,igc0,match,block,in,4,0x0,,64,12345,0,none,6,tcp,'
    '60,192.0.2.10,198.51.100.20,51515,443,0,S,1,0,65535,,mss';

const oldBlockLine =
    '2026-07-10T20:00:00Z firewall filterlog: '
    '101,0,,1235,igc0,match,block,in,4,0x0,,64,12346,0,none,6,tcp,'
    '60,192.0.2.11,198.51.100.21,51516,443,0,S,1,0,65535,,mss';

const recentPassLine =
    '2026-07-11T01:05:00Z firewall filterlog: '
    '102,0,,1236,igc1,match,pass,in,4,0x0,,64,12347,0,none,17,udp,'
    '76,203.0.113.10,203.0.113.20,5353,53,48';

void main() {
  test('firewall log request sends only supported pagination fields', () async {
    final client = _RecordingApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);

    final logs = await service.getFirewallLogs(
      action: 'BLOCK',
      since: DateTime.parse('2026-07-11T00:00:00Z'),
      limit: 50,
      offset: 10,
    );

    expect(client.lastPath, '/api/v2/status/logs/firewall');
    expect(client.lastQueryParameters, {'limit': '50', 'offset': '10'});
    expect(client.lastQueryParameters, isNot(contains('action')));
    expect(client.lastQueryParameters, isNot(contains('since')));
    expect(logs, hasLength(1));
    expect(logs.single.action, 'BLOCK');
    expect(logs.single.sourceIp, '192.0.2.10');
  });

  test('returns newest parsed entries first and malformed entries last', () async {
    final client = _RecordingApiClient();
    final service = PfSenseService(client);
    addTearDown(service.dispose);

    final logs = await service.getFirewallLogs(limit: 100);

    expect(logs.first.action, 'PASS');
    expect(logs[1].action, 'BLOCK');
    expect(logs[2].action, 'BLOCK');
    expect(logs.last.isParsed, isFalse);
  });
}

class _RecordingApiClient extends PfSenseApiClient {
  _RecordingApiClient()
      : super(
          PfSenseProfile(
            id: 'firewall-log-test',
            name: 'Firewall log test',
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
      data: <String, dynamic>{
        'data': <Map<String, dynamic>>[
          {'text': oldBlockLine},
          {'text': 'malformed line'},
          {'text': recentPassLine},
          {'text': recentBlockLine},
        ],
      },
    );
  }
}
