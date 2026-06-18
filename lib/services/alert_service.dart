import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const _taskUniqueName = 'pfsense_alert_check';
const _notificationChannelId = 'pfsense_alerts';
const _notificationChannelName = 'pfSense Alerts';
const _enabledKey = 'alert.enabled';
const _cpuTempKey = 'alert.cpuTempThreshold';
const _packetLossKey = 'alert.packetLossThreshold';
const _gatewayAlertsKey = 'alert.gatewayOffline';

@pragma('vm:entry-point')
void alertCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await AlertService._performBackgroundCheck();
    } catch (_) {}
    return true;
  });
}

class AlertService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_launcher'),
      ),
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await Workmanager().initialize(
      alertCallbackDispatcher,
      isInDebugMode: false,
    );
  }

  static Future<void> setAlertsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (enabled) {
      await Workmanager().registerPeriodicTask(
        _taskUniqueName,
        _taskUniqueName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } else {
      await Workmanager().cancelByUniqueName(_taskUniqueName);
    }
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> setCpuTempThreshold(double celsius) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_cpuTempKey, celsius);
  }

  static Future<double> getCpuTempThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_cpuTempKey) ?? 80.0;
  }

  static Future<void> setPacketLossThreshold(double percent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_packetLossKey, percent);
  }

  static Future<double> getPacketLossThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_packetLossKey) ?? 15.0;
  }

  static Future<void> setGatewayAlertsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gatewayAlertsKey, enabled);
  }

  static Future<bool> getGatewayAlertsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_gatewayAlertsKey) ?? true;
  }

  static Future<void> _performBackgroundCheck() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_enabledKey) ?? false)) return;

    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );

    final profilesJson = prefs.getString('profiles');
    final selectedId = prefs.getString('selectedProfileId');
    if (profilesJson == null || selectedId == null || selectedId.isEmpty) return;

    Map<String, dynamic>? profileData;
    try {
      final decoded = jsonDecode(profilesJson) as List;
      for (final p in decoded) {
        if ((p as Map<String, dynamic>)['id'] == selectedId) {
          profileData = p;
          break;
        }
      }
    } catch (_) {
      return;
    }
    if (profileData == null) return;

    final apiKey = await storage.read(key: 'profile_api_key_$selectedId');
    if (apiKey == null || apiKey.isEmpty) return;

    final host = profileData['host']?.toString() ?? '';
    final port = profileData['port'] as int? ?? 443;
    final allowSelfSigned = profileData['allowSelfSignedCert'] as bool? ?? false;
    if (host.isEmpty) return;

    final cpuThreshold = prefs.getDouble(_cpuTempKey) ?? 80.0;
    final lossThreshold = prefs.getDouble(_packetLossKey) ?? 15.0;
    final gatewayAlerts = prefs.getBool(_gatewayAlertsKey) ?? true;

    final dio = Dio(BaseOptions(
      baseUrl: 'https://$host:$port',
      headers: {'X-API-Key': apiKey},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));

    if (allowSelfSigned) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = (_, __, ___) => true;
          return client;
        },
      );
    }

    try {
      final responses = await Future.wait([
        dio.get('/api/v2/status/gateways'),
        dio.get('/api/v2/status/system'),
      ]);

      if (gatewayAlerts) {
        final gwData = responses[0].data;
        if (gwData is Map && gwData['data'] is List) {
          for (final gw in gwData['data'] as List) {
            if (gw is! Map<String, dynamic>) continue;
            final name = gw['name']?.toString() ?? 'Gateway';
            final status = gw['status']?.toString().toLowerCase() ?? '';
            final loss = _parseDouble(gw['packet_loss'] ?? gw['packetloss']);

            if (status == 'down' || status == 'offline') {
              await _showNotification(
                id: _stableId(name, 'down'),
                title: 'Gateway Offline',
                body: '$name is not reachable',
              );
            } else if (loss >= lossThreshold) {
              await _showNotification(
                id: _stableId(name, 'loss'),
                title: 'High Packet Loss',
                body: '$name: ${loss.toStringAsFixed(1)}% packet loss',
              );
            }
          }
        }
      }

      final sysData = responses[1].data;
      if (sysData is Map) {
        final data = sysData['data'];
        if (data is Map<String, dynamic>) {
          final sensors = data['thermal_sensors'] as List? ??
              data['thermals'] as List? ??
              [];
          for (final sensor in sensors) {
            if (sensor is! Map<String, dynamic>) continue;
            final temp = _parseDouble(
                sensor['temperature_c'] ?? sensor['temp'] ?? sensor['temperature']);
            final name = sensor['name']?.toString() ?? 'CPU';
            if (temp >= cpuThreshold) {
              await _showNotification(
                id: _stableId(name, 'temp'),
                title: 'High Temperature Alert',
                body:
                    '$name reached ${temp.toStringAsFixed(1)}°C (limit ${cpuThreshold.toStringAsFixed(0)}°C)',
              );
              break;
            }
          }
        }
      }
    } catch (_) {}
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    final str = value.toString().replaceAll('%', '').trim();
    return double.tryParse(str) ?? 0;
  }

  static int _stableId(String name, String kind) =>
      '${name}_$kind'.hashCode.abs() % 100000;

  static Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _notifications.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            _notificationChannelName,
            channelDescription:
                'Critical status alerts from your pfSense firewall',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }
}
