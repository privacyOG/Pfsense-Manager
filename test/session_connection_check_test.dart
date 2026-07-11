import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/providers/profile_provider.dart';
import 'package:pfsense_manager/providers/session_provider.dart';
import 'package:pfsense_manager/screens/startup_screen.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/connection_check.dart';
import 'package:pfsense_manager/utils/api_exception.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('session accepts a restricted profile with one usable capability',
      () async {
    final client = _SessionProbeClient({
      '/api/v2/status/system': const ApiException('Forbidden', 403),
      '/api/v2/status/interfaces': _success('/api/v2/status/interfaces'),
      '/api/v2/status/gateways': const ApiException('Forbidden', 403),
      '/api/v2/firewall/rules': const ApiException('Not found', 404),
      '/api/v2/status/services': const ApiException('Forbidden', 403),
    });
    final session = _sessionFor(client);
    addTearDown(session.dispose);

    await session.connect(_profile());

    expect(session.connected, isTrue);
    expect(session.connecting, isFalse);
    expect(session.service, isNotNull);
    expect(session.connectionError, isNull);
    expect(session.connectionCheck?.restricted, isTrue);
    expect(session.connectionNotice, contains('Interface status'));
    expect(session.selectedProfile?.apiKey, isEmpty);
    expect(client.closed, isFalse);

    await session.disconnect();
    expect(client.closed, isTrue);
  });

  test('session preserves a permission failure and closes the client',
      () async {
    final client = _SessionProbeClient.allFailed(
      const ApiException('Read permission required', 403),
    );
    final session = _sessionFor(client);
    addTearDown(session.dispose);

    await session.connect(_profile());

    expect(session.connected, isFalse);
    expect(session.connecting, isFalse);
    expect(session.service, isNull);
    expect(
      session.connectionCheck?.failureKind,
      ConnectionFailureKind.permission,
    );
    expect(session.connectionError, contains('Permission denied (403)'));
    expect(session.connectionError, contains('System status'));
    expect(session.connectionError, contains('Read permission required (403)'));
    expect(client.closed, isTrue);
  });

  test('session preserves authentication instead of a generic failure',
      () async {
    final client = _SessionProbeClient.allFailed(
      const ApiException('Invalid API key', 401),
    );
    final session = _sessionFor(client);
    addTearDown(session.dispose);

    await session.connect(_profile());

    expect(session.connected, isFalse);
    expect(
      session.connectionCheck?.failureKind,
      ConnectionFailureKind.authentication,
    );
    expect(session.connectionError, contains('Authentication failed (401)'));
    expect(session.connectionError, contains('Invalid API key (401)'));
    expect(
      session.connectionError,
      isNot(contains('Check credentials, API permissions and network')),
    );
    expect(client.closed, isTrue);
  });

  testWidgets('login screen displays the failed capability and remediation',
      (tester) async {
    final client = _SessionProbeClient.allFailed(
      const ApiException('System status permission missing', 403),
    );
    final session = _sessionFor(client);
    final profiles = ProfileProvider();
    addTearDown(session.dispose);
    addTearDown(profiles.dispose);

    final profile = _profile();
    await profiles.addProfile(profile);
    await session.connect(profile);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileProvider>.value(value: profiles),
          ChangeNotifierProvider<PfSenseSessionProvider>.value(value: session),
        ],
        child: const MaterialApp(home: SecureApiLoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Permission denied (403)'), findsOneWidget);
    expect(find.textContaining('System status'), findsOneWidget);
    expect(find.textContaining('Grant read access'), findsOneWidget);
    expect(find.textContaining('System status permission missing'), findsOneWidget);
  });
}

PfSenseSessionProvider _sessionFor(_SessionProbeClient client) {
  return PfSenseSessionProvider(
    profileResolver: (profile) async => profile,
    apiClientFactory: (_) => client,
  );
}

PfSenseProfile _profile() {
  return PfSenseProfile(
    id: 'session-connection-check',
    name: 'Session connection check',
    host: 'firewall.example.test',
    username: 'api-user',
    apiKey: 'test-key',
  );
}

class _SessionProbeClient extends PfSenseApiClient {
  _SessionProbeClient(this._results) : super(_profile());

  factory _SessionProbeClient.allFailed(Object error) {
    return _SessionProbeClient({
      for (final capability in PfSenseConnectionChecker.capabilities)
        capability.path: error,
    });
  }

  final Map<String, Object> _results;
  bool closed = false;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final result = _results[path];
    if (result == null) throw StateError('No probe result for $path.');
    if (result is Error) throw result;
    if (result is Exception) throw result;
    return result as Response<dynamic>;
  }

  @override
  void dispose() {
    if (closed) return;
    closed = true;
    super.dispose();
  }
}

Response<dynamic> _success(String path) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: <String, dynamic>{'data': <dynamic>[]},
  );
}
