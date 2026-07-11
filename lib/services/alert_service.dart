import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../utils/background_notification_id.dart';
import 'background_alert_diagnostics.dart';
import 'background_alert_runner.dart';

export 'background_alert_runner.dart'
    show
        AlertTemperatureReading,
        gatewayPacketLossPercent,
        systemTemperatureReadings;

const _taskUniqueName = 'pfsense_alert_check';
const _notificationChannelId = 'pfsense_alerts';
const _notificationChannelName = 'pfSense Alerts';

@pragma('vm:entry-point')
void alertCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await AlertService.performBackgroundCheck();
    } catch (error) {
      await AlertService.recordOperationalFailure(error);
    }
    return true;
  });
}

class AlertService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    final notifier = _LocalAlertNotifier(_notifications);
    try {
      final permissionGranted = await notifier.requestPermission();
      if (!permissionGranted) {
        await recordOperationalFailure(
          const BackgroundAlertNotificationPermissionException(),
        );
      }
    } catch (_) {
      await recordOperationalFailure(
        const BackgroundAlertNotificationException(),
      );
    }

    try {
      await Workmanager().initialize(
        alertCallbackDispatcher,
        isInDebugMode: false,
      );
    } catch (_) {
      await recordOperationalFailure(
        const BackgroundAlertSchedulingException(),
      );
    }
  }

  static Future<void> setAlertsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      await prefs.setBool(backgroundAlertsEnabledKey, false);
      try {
        await Workmanager().cancelByUniqueName(_taskUniqueName);
      } catch (_) {
        await recordOperationalFailure(
          const BackgroundAlertSchedulingException(),
          preferences: prefs,
        );
        throw StateError(
          'Background alerts were disabled locally, but Android could not cancel the scheduled task.',
        );
      }
      return;
    }

    final notifier = _LocalAlertNotifier(_notifications);
    try {
      if (!await notifier.requestPermission()) {
        await recordOperationalFailure(
          const BackgroundAlertNotificationPermissionException(),
          preferences: prefs,
        );
      }
    } catch (_) {
      await recordOperationalFailure(
        const BackgroundAlertNotificationException(),
        preferences: prefs,
      );
    }

    try {
      await Workmanager().registerPeriodicTask(
        _taskUniqueName,
        _taskUniqueName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      await prefs.setBool(backgroundAlertsEnabledKey, true);
    } catch (_) {
      await prefs.setBool(backgroundAlertsEnabledKey, false);
      await recordOperationalFailure(
        const BackgroundAlertSchedulingException(),
        preferences: prefs,
      );
      throw StateError(
        'Android could not schedule background alerts. Review battery optimization and background activity settings.',
      );
    }
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(backgroundAlertsEnabledKey) ?? false;
  }

  static Future<void> setCpuTempThreshold(double celsius) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(backgroundAlertCpuTempKey, celsius);
  }

  static Future<double> getCpuTempThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(backgroundAlertCpuTempKey) ?? 80.0;
  }

  static Future<void> setPacketLossThreshold(double percent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(backgroundAlertPacketLossKey, percent);
  }

  static Future<double> getPacketLossThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(backgroundAlertPacketLossKey) ?? 15.0;
  }

  static Future<void> setGatewayAlertsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(backgroundAlertGatewayKey, enabled);
  }

  static Future<bool> getGatewayAlertsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(backgroundAlertGatewayKey) ?? true;
  }

  static Future<BackgroundAlertDiagnostics> getDiagnostics() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return BackgroundAlertDiagnosticsStore(prefs).read();
  }

  static Future<BackgroundAlertCheckResult> performBackgroundCheck() async {
    final prefs = await SharedPreferences.getInstance();
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final runner = BackgroundAlertRunner(
      preferences: prefs,
      secureStorage: storage,
      notifier: _LocalAlertNotifier(_notifications),
      clientFactory: PfSenseBackgroundAlertApiClient.new,
      notificationId: backgroundNotificationId,
    );
    return runner.run();
  }

  static Future<void> recordOperationalFailure(
    Object error, {
    SharedPreferences? preferences,
  }) async {
    try {
      final prefs = preferences ?? await SharedPreferences.getInstance();
      final failure = classifyBackgroundAlertFailure(error);
      await BackgroundAlertDiagnosticsStore(prefs).recordFailure(
        failure,
        DateTime.now(),
      );
    } catch (_) {
      // Background execution must still return safely when diagnostics storage
      // itself is unavailable.
    }
  }
}

class _LocalAlertNotifier implements BackgroundAlertNotifier {
  _LocalAlertNotifier(this.notifications);

  final FlutterLocalNotificationsPlugin notifications;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    final initialized = await notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_launcher'),
      ),
    );
    if (initialized == false) {
      throw const BackgroundAlertNotificationException();
    }
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await _ensureInitialized();
    final android = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<bool> hasPermission() async {
    try {
      await _ensureInitialized();
      final android = notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? true;
    } catch (error) {
      if (error is BackgroundAlertNotificationException) rethrow;
      throw const BackgroundAlertNotificationException();
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    await notifications.show(
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
  }
}
