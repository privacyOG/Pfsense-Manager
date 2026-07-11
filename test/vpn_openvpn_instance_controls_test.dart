import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/l10n/app_strings.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/models/system_service.dart';
import 'package:pfsense_manager/models/wireguard_tunnel.dart';
import 'package:pfsense_manager/providers/session_provider.dart';
import 'package:pfsense_manager/screens/vpn_screen.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfsense_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('OpenVPN restart controls identify exact service instances',
      (tester) async {
    final service = _VpnFixtureService();
    final session = _ConnectedSessionProvider(service);
    addTearDown(service.dispose);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<PfSenseSessionProvider>.value(
        value: session,
        child: MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          supportedLocales: AppStrings.supportedLocales,
          home: const Scaffold(body: VpnScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('VPN ID 1'), findsOneWidget);
    expect(find.textContaining('Service #5'), findsOneWidget);
    expect(find.textContaining('VPN ID 2'), findsOneWidget);
    expect(find.textContaining('Service #8'), findsOneWidget);

    expect(
      find.byTooltip(
        'Restart OpenVPN server (server · VPN ID 1 · Service #5)',
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip(
        'Restart OpenVPN server (server · VPN ID 2 · Service #8)',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Restart OpenVPN'), findsNothing);
  });
}

class _ConnectedSessionProvider extends PfSenseSessionProvider {
  _ConnectedSessionProvider(this._testService);

  final PfSenseService _testService;

  @override
  bool get connected => true;

  @override
  PfSenseService? get service => _testService;
}

class _VpnFixtureService extends PfSenseService {
  _VpnFixtureService() : super(_NoopApiClient());

  @override
  Future<List<Map<String, dynamic>>> getOpenVPNStatus() async {
    return [
      {
        'name': 'Branch VPN',
        'mode': 'server',
        'port': '1194',
        'vpnid': '1',
        'conns': <dynamic>[],
      },
      {
        'name': 'Staff VPN',
        'mode': 'server',
        'port': '1195',
        'vpnid': '2',
        'conns': <dynamic>[],
      },
    ];
  }

  @override
  Future<List<SystemService>> getServices() async {
    return [
      SystemService(
        id: 5,
        name: 'openvpn',
        displayName: 'OpenVPN server',
        running: true,
        mode: 'server',
        vpnId: '1',
      ),
      SystemService(
        id: 8,
        name: 'openvpn',
        displayName: 'OpenVPN server',
        running: true,
        mode: 'server',
        vpnId: '2',
      ),
    ];
  }

  @override
  Future<List<WireGuardTunnel>> getWireGuardStatus() async => [];
}

class _NoopApiClient extends PfSenseApiClient {
  _NoopApiClient()
      : super(
          PfSenseProfile(
            id: 'vpn-instance-ui-test',
            name: 'VPN instance UI test',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <String, dynamic>{'data': <dynamic>[]},
    );
  }
}
