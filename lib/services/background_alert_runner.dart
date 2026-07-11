import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';
import 'api_client.dart';
import 'background_alert_diagnostics.dart';

const backgroundAlertsEnabledKey = 'alert.enabled';
const backgroundAlertCpuTempKey = 'alert.cpuTempThreshold';
const backgroundAlertPacketLossKey = 'alert.packetLossThreshold';
const backgroundAlertGatewayKey = 'alert.gatewayOffline';

class AlertTemperatureReading {
  const AlertTemperatureReading({required this.name, required this.celsius});

  final String name;
  final double celsius;
}

abstract class BackgroundAlertApiClient {
  Future<dynamic> get(String path);
  void close();
}

class PfSenseBackgroundAlertApiClient implements BackgroundAlertApiClient {
  PfSenseBackgroundAlertApiClient(PfSenseProfile profile)
      : _client = PfSenseApiClient(profile);

  final PfSenseApiClient _client;

  @override
  Future<dynamic> get(String path) async => (await _client.get(path)).data;

  @override
  void close() => _client.dispose();
}

abstract class BackgroundAlertNotifier {
  Future<bool> hasPermission();

  Future<void> show({
    required int id,
    required String title,
    required String body,
  });
}

typedef BackgroundAlertApiClientFactory = BackgroundAlertApiClient Function(
  PfSenseProfile profile,
);
typedef BackgroundAlertNotificationId = int Function({
  required String profileId,
  required String monitoredItem,
  required String alertType,
});

class BackgroundAlertCheckResult {
  const BackgroundAlertCheckResult._({
    required this.attempted,
    required this.succeeded,
    this.failure,
  });

  const BackgroundAlertCheckResult.skipped()
      : this._(attempted: false, succeeded: true);

  const BackgroundAlertCheckResult.success()
      : this._(attempted: true, succeeded: true);

  const BackgroundAlertCheckResult.failure(BackgroundAlertFailure failure)
      : this._(attempted: true, succeeded: false, failure: failure);

  final bool attempted;
  final bool succeeded;
  final BackgroundAlertFailure? failure;
}

class BackgroundAlertRunner {
  BackgroundAlertRunner({
    required this.preferences,
    required this.secureStorage,
    required this.notifier,
    required this.clientFactory,
    required this.notificationId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SharedPreferences preferences;
  final FlutterSecureStorage secureStorage;
  final BackgroundAlertNotifier notifier;
  final BackgroundAlertApiClientFactory clientFactory;
  final BackgroundAlertNotificationId notificationId;
  final DateTime Function() _clock;

  Future<BackgroundAlertCheckResult> run() async {
    await preferences.reload();
    if (!(preferences.getBool(backgroundAlertsEnabledKey) ?? false)) {
      return const BackgroundAlertCheckResult.skipped();
    }

    final diagnostics = BackgroundAlertDiagnosticsStore(preferences);
    await diagnostics.recordAttempt(_clock());

    BackgroundAlertApiClient? client;
    try {
      if (!await notifier.hasPermission()) {
        throw const BackgroundAlertNotificationPermissionException();
      }

      final profile = await _loadSelectedProfile();
      client = clientFactory(profile);

      final responses = await Future.wait<dynamic>([
        client.get('/api/v2/status/gateways'),
        client.get('/api/v2/status/system'),
      ]);

      await _evaluateGateways(profile.id, responses[0]);
      await _evaluateSystem(profile.id, responses[1]);

      await diagnostics.recordSuccess(_clock());
      return const BackgroundAlertCheckResult.success();
    } catch (error) {
      final failure = classifyBackgroundAlertFailure(error);
      await diagnostics.recordFailure(failure, _clock());
      return BackgroundAlertCheckResult.failure(failure);
    } finally {
      client?.close();
    }
  }

  Future<PfSenseProfile> _loadSelectedProfile() async {
    final profilesJson = preferences.getString('profiles');
    final selectedId = preferences.getString('selectedProfileId');
    if (profilesJson == null || selectedId == null || selectedId.isEmpty) {
      throw const BackgroundAlertConfigurationException();
    }

    Map<String, dynamic>? selected;
    try {
      final decoded = jsonDecode(profilesJson);
      if (decoded is! List) {
        throw const BackgroundAlertConfigurationException();
      }
      for (final entry in decoded) {
        if (entry is Map<String, dynamic> && entry['id'] == selectedId) {
          selected = entry;
          break;
        }
      }
    } catch (error) {
      if (error is BackgroundAlertConfigurationException) rethrow;
      throw const BackgroundAlertConfigurationException();
    }

    if (selected == null) {
      throw const BackgroundAlertConfigurationException();
    }

    PfSenseProfile profile;
    try {
      profile = PfSenseProfile.fromJson(selected);
    } catch (_) {
      throw const BackgroundAlertConfigurationException();
    }

    switch (profile.authMode) {
      case PfSenseAuthMode.apiKey:
        final apiKey = await secureStorage.read(
          key: 'profile_api_key_$selectedId',
        );
        if (apiKey == null || apiKey.isEmpty) {
          throw const BackgroundAlertConfigurationException();
        }
        return profile.copyWith(apiKey: apiKey, password: '');
      case PfSenseAuthMode.jwtPassword:
        final password = await secureStorage.read(
          key: 'profile_password_$selectedId',
        );
        if (password == null || password.isEmpty) {
          throw const BackgroundAlertConfigurationException();
        }
        return profile.copyWith(apiKey: '', password: password);
    }
  }

  Future<void> _evaluateGateways(
    String profileId,
    dynamic responseData,
  ) async {
    if (!(preferences.getBool(backgroundAlertGatewayKey) ?? true)) return;
    if (responseData is! Map || responseData['data'] is! List) return;

    final threshold =
        preferences.getDouble(backgroundAlertPacketLossKey) ?? 15.0;
    for (final gateway in responseData['data'] as List) {
      if (gateway is! Map<String, dynamic>) continue;
      final name = gateway['name']?.toString() ?? 'Gateway';
      final status = gateway['status']?.toString().toLowerCase() ?? '';
      final loss = gatewayPacketLossPercent(gateway);

      if (status == 'down' || status == 'offline') {
        await _show(
          id: notificationId(
            profileId: profileId,
            monitoredItem: name,
            alertType: 'down',
          ),
          title: 'Gateway Offline',
          body: '$name is not reachable',
        );
      } else if (loss >= threshold) {
        await _show(
          id: notificationId(
            profileId: profileId,
            monitoredItem: name,
            alertType: 'loss',
          ),
          title: 'High Packet Loss',
          body: '$name: ${loss.toStringAsFixed(1)}% packet loss',
        );
      }
    }
  }

  Future<void> _evaluateSystem(
    String profileId,
    dynamic responseData,
  ) async {
    if (responseData is! Map) return;
    final data = responseData['data'];
    if (data is! Map<String, dynamic>) return;

    final threshold = preferences.getDouble(backgroundAlertCpuTempKey) ?? 80.0;
    for (final reading in systemTemperatureReadings(data)) {
      if (reading.celsius < threshold) continue;
      await _show(
        id: notificationId(
          profileId: profileId,
          monitoredItem: reading.name,
          alertType: 'temp',
        ),
        title: 'High Temperature Alert',
        body:
            '${reading.name} reached ${reading.celsius.toStringAsFixed(1)}°C (limit ${threshold.toStringAsFixed(0)}°C)',
      );
      break;
    }
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await notifier.show(id: id, title: title, body: body);
    } catch (_) {
      throw const BackgroundAlertNotificationException();
    }
  }
}

double gatewayPacketLossPercent(Map<String, dynamic> gateway) {
  return _parseDouble(
    gateway['loss'] ?? gateway['packet_loss'] ?? gateway['packetloss'],
  );
}

List<AlertTemperatureReading> systemTemperatureReadings(
  Map<String, dynamic> data,
) {
  final readings = <AlertTemperatureReading>[];
  final directTemp = _parseNullableDouble(data['temp_c']);
  if (directTemp != null) {
    readings.add(AlertTemperatureReading(name: 'CPU', celsius: directTemp));
  }

  final sensors = _asList(data['thermal_sensors']) ?? _asList(data['thermals']);
  if (sensors != null) {
    for (final sensor in sensors) {
      if (sensor is! Map<String, dynamic>) continue;
      final temp = _parseNullableDouble(
        sensor['temperature_c'] ??
            sensor['temp_c'] ??
            sensor['temp'] ??
            sensor['temperature'],
      );
      if (temp == null) continue;
      final name = sensor['name']?.toString().trim();
      readings.add(
        AlertTemperatureReading(
          name: name == null || name.isEmpty ? 'CPU' : name,
          celsius: temp,
        ),
      );
    }
  }

  return readings;
}

List<dynamic>? _asList(dynamic value) => value is List ? value : null;

double _parseDouble(dynamic value) => _parseNullableDouble(value) ?? 0;

double? _parseNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final str = value.toString().replaceAll('%', '').trim();
  if (str.isEmpty) return null;
  return double.tryParse(str);
}
