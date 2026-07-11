import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/services/background_alert_diagnostics.dart';
import 'package:pfsense_manager/services/background_alert_runner.dart';
import 'package:pfsense_manager/utils/api_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('successful check records health, sends alerts and closes the client',
      () async {
    final prefs = await _configuredPreferences();
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'profile_api_key_firewall-1': 'saved-key',
    });
    final notifier = _FakeNotifier();
    final client = _FakeAlertClient({
      '/api/v2/status/gateways': {
        'data': [
          {'name': 'WAN_DHCP', 'status': 'offline', 'loss': 0},
        ],
      },
      '/api/v2/status/system': {
        'data': {
          'thermal_sensors': [
            {'name': 'CPU Package', 'temperature_c': 91},
          ],
        },
      },
    });
    PfSenseProfile? resolvedProfile;
    final identities = <_NotificationIdentity>[];
    final clock = _Clock([
      DateTime.utc(2026, 7, 11, 10, 0),
      DateTime.utc(2026, 7, 11, 10, 1),
    ]);

    final result = await BackgroundAlertRunner(
      preferences: prefs,
      secureStorage: const FlutterSecureStorage(),
      notifier: notifier,
      clientFactory: (profile) {
        resolvedProfile = profile;
        return client;
      },
      notificationId: ({
        required String profileId,
        required String monitoredItem,
        required String alertType,
      }) {
        identities.add(
          _NotificationIdentity(
            profileId: profileId,
            monitoredItem: monitoredItem,
            alertType: alertType,
          ),
        );
        return identities.length;
      },
      clock: clock.call,
    ).run();

    expect(result.attempted, isTrue);
    expect(result.succeeded, isTrue);
    expect(client.closed, isTrue);
    expect(resolvedProfile?.apiKey, 'saved-key');
    expect(resolvedProfile?.password, isEmpty);
    expect(notifier.shown, hasLength(2));
    expect(notifier.shown.map((item) => item.title), contains('Gateway Offline'));
    expect(
      notifier.shown.map((item) => item.title),
      contains('High Temperature Alert'),
    );
    expect(
      identities,
      const [
        _NotificationIdentity(
          profileId: 'firewall-1',
          monitoredItem: 'WAN_DHCP',
          alertType: 'down',
        ),
        _NotificationIdentity(
          profileId: 'firewall-1',
          monitoredItem: 'CPU Package',
          alertType: 'temp',
        ),
      ],
    );

    final diagnostics = BackgroundAlertDiagnosticsStore(prefs).read();
    expect(
      diagnostics.lastAttempt?.toUtc(),
      DateTime.utc(2026, 7, 11, 10, 0),
    );
    expect(
      diagnostics.lastSuccess?.toUtc(),
      DateTime.utc(2026, 7, 11, 10, 1),
    );
    expect(diagnostics.hasError, isFalse);
  });

  test('authentication failure returns safely and closes the client', () async {
    final prefs = await _configuredPreferences();
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'profile_api_key_firewall-1': 'private-key',
    });
    final client = _FakeAlertClient({
      '/api/v2/status/gateways': const ApiException(
        'Response contains private-key',
        401,
      ),
      '/api/v2/status/system': const ApiException(
        'Response contains private-key',
        401,
      ),
    });

    final result = await BackgroundAlertRunner(
      preferences: prefs,
      secureStorage: const FlutterSecureStorage(),
      notifier: _FakeNotifier(),
      clientFactory: (_) => client,
      notificationId: _constantNotificationId,
      clock: () => DateTime.utc(2026, 7, 11, 11),
    ).run();

    expect(result.succeeded, isFalse);
    expect(
      result.failure?.category,
      BackgroundAlertFailureCategory.authentication,
    );
    expect(client.closed, isTrue);

    final diagnostics = BackgroundAlertDiagnosticsStore(prefs).read();
    expect(
      diagnostics.lastErrorCategory,
      BackgroundAlertFailureCategory.authentication,
    );
    expect(diagnostics.lastErrorMessage, isNot(contains('private-key')));
  });

  test('notification permission failure does not create a network client',
      () async {
    final prefs = await _configuredPreferences();
    var clientCreated = false;

    final result = await BackgroundAlertRunner(
      preferences: prefs,
      secureStorage: const FlutterSecureStorage(),
      notifier: _FakeNotifier(permissionGranted: false),
      clientFactory: (_) {
        clientCreated = true;
        return _FakeAlertClient(const {});
      },
      notificationId: _constantNotificationId,
      clock: () => DateTime.utc(2026, 7, 11, 12),
    ).run();

    expect(result.succeeded, isFalse);
    expect(clientCreated, isFalse);
    expect(
      result.failure?.category,
      BackgroundAlertFailureCategory.notificationPermission,
    );
  });

  test('notification delivery failure still closes the network client',
      () async {
    final prefs = await _configuredPreferences();
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'profile_api_key_firewall-1': 'saved-key',
    });
    final client = _FakeAlertClient({
      '/api/v2/status/gateways': {
        'data': [
          {'name': 'WAN_DHCP', 'status': 'offline'},
        ],
      },
      '/api/v2/status/system': {'data': <String, dynamic>{}},
    });

    final result = await BackgroundAlertRunner(
      preferences: prefs,
      secureStorage: const FlutterSecureStorage(),
      notifier: _FakeNotifier(throwOnShow: true),
      clientFactory: (_) => client,
      notificationId: _constantNotificationId,
      clock: () => DateTime.utc(2026, 7, 11, 13),
    ).run();

    expect(result.succeeded, isFalse);
    expect(
      result.failure?.category,
      BackgroundAlertFailureCategory.notification,
    );
    expect(client.closed, isTrue);
  });

  test('password profile resolves only the saved password', () async {
    final profile = _profile(authMode: PfSenseAuthMode.jwtPassword);
    final prefs = await _configuredPreferences(profile: profile);
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'profile_api_key_firewall-1': 'unused-key',
      'profile_password_firewall-1': 'saved-password',
    });
    final client = _FakeAlertClient({
      '/api/v2/status/gateways': {'data': <dynamic>[]},
      '/api/v2/status/system': {'data': <String, dynamic>{}},
    });
    PfSenseProfile? resolvedProfile;

    final result = await BackgroundAlertRunner(
      preferences: prefs,
      secureStorage: const FlutterSecureStorage(),
      notifier: _FakeNotifier(),
      clientFactory: (profile) {
        resolvedProfile = profile;
        return client;
      },
      notificationId: _constantNotificationId,
      clock: () => DateTime.utc(2026, 7, 11, 14),
    ).run();

    expect(result.succeeded, isTrue);
    expect(resolvedProfile?.authMode, PfSenseAuthMode.jwtPassword);
    expect(resolvedProfile?.password, 'saved-password');
    expect(resolvedProfile?.apiKey, isEmpty);
    expect(client.closed, isTrue);
  });

  test('disabled checks are skipped without diagnostics or network access',
      () async {
    final prefs = await _configuredPreferences(enabled: false);
    var clientCreated = false;

    final result = await BackgroundAlertRunner(
      preferences: prefs,
      secureStorage: const FlutterSecureStorage(),
      notifier: _FakeNotifier(),
      clientFactory: (_) {
        clientCreated = true;
        return _FakeAlertClient(const {});
      },
      notificationId: _constantNotificationId,
    ).run();

    expect(result.attempted, isFalse);
    expect(result.succeeded, isTrue);
    expect(clientCreated, isFalse);
    expect(BackgroundAlertDiagnosticsStore(prefs).read().hasAttempted, isFalse);
  });
}

int _constantNotificationId({
  required String profileId,
  required String monitoredItem,
  required String alertType,
}) =>
    1;

Future<SharedPreferences> _configuredPreferences({
  bool enabled = true,
  PfSenseProfile? profile,
}) async {
  final selected = profile ?? _profile();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(backgroundAlertsEnabledKey, enabled);
  await prefs.setBool(backgroundAlertGatewayKey, true);
  await prefs.setDouble(backgroundAlertCpuTempKey, 80);
  await prefs.setDouble(backgroundAlertPacketLossKey, 15);
  await prefs.setString('selectedProfileId', selected.id);
  await prefs.setString('profiles', jsonEncode([selected.toJson()]));
  return prefs;
}

PfSenseProfile _profile({
  PfSenseAuthMode authMode = PfSenseAuthMode.apiKey,
}) {
  return PfSenseProfile(
    id: 'firewall-1',
    name: 'Test firewall',
    host: 'firewall.example.test',
    username: 'api-user',
    authMode: authMode,
  );
}

class _FakeAlertClient implements BackgroundAlertApiClient {
  _FakeAlertClient(this.responses);

  final Map<String, Object> responses;
  bool closed = false;

  @override
  Future<dynamic> get(String path) async {
    final value = responses[path];
    if (value == null) throw StateError('No response configured for $path.');
    if (value is Error) throw value;
    if (value is Exception) throw value;
    return value;
  }

  @override
  void close() {
    closed = true;
  }
}

class _FakeNotifier implements BackgroundAlertNotifier {
  _FakeNotifier({
    this.permissionGranted = true,
    this.throwOnShow = false,
  });

  final bool permissionGranted;
  final bool throwOnShow;
  final List<_ShownNotification> shown = [];

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (throwOnShow) throw StateError('Notification plugin failure');
    shown.add(_ShownNotification(id: id, title: title, body: body));
  }
}

class _ShownNotification {
  const _ShownNotification({
    required this.id,
    required this.title,
    required this.body,
  });

  final int id;
  final String title;
  final String body;
}

class _NotificationIdentity {
  const _NotificationIdentity({
    required this.profileId,
    required this.monitoredItem,
    required this.alertType,
  });

  final String profileId;
  final String monitoredItem;
  final String alertType;

  @override
  bool operator ==(Object other) {
    return other is _NotificationIdentity &&
        other.profileId == profileId &&
        other.monitoredItem == monitoredItem &&
        other.alertType == alertType;
  }

  @override
  int get hashCode => Object.hash(profileId, monitoredItem, alertType);
}

class _Clock {
  _Clock(this.values);

  final List<DateTime> values;
  int _index = 0;

  DateTime call() {
    if (_index >= values.length) return values.last;
    return values[_index++];
  }
}
