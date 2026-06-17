import 'package:home_widget/home_widget.dart';

class HomeWidgetService {
  static const _appGroupId = 'com.privacyog.pfsense_manager';
  static const _androidWidgetName = 'PfSenseWidgetProvider';

  static Future<void> updateStatusWidget({
    String? profileName,
    String? cpuTemp,
    String? gatewayName,
    String? gatewayLatency,
    String? trafficIn,
    String? trafficOut,
    String? lastUpdated,
  }) async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      await Future.wait([
        HomeWidget.saveWidgetData<String>(
          'profile_name',
          profileName ?? 'pfSense Manager',
        ),
        HomeWidget.saveWidgetData<String>('cpu_temp', cpuTemp ?? '--'),
        HomeWidget.saveWidgetData<String>(
          'gateway_name',
          gatewayName ?? '--',
        ),
        HomeWidget.saveWidgetData<String>(
          'gateway_latency',
          gatewayLatency ?? '--',
        ),
        HomeWidget.saveWidgetData<String>('traffic_in', trafficIn ?? '--'),
        HomeWidget.saveWidgetData<String>(
          'traffic_out',
          trafficOut ?? '--',
        ),
        HomeWidget.saveWidgetData<String>(
          'last_updated',
          lastUpdated ?? '--',
        ),
      ]);
      await HomeWidget.updateWidget(androidName: _androidWidgetName);
    } catch (_) {
      // Widget updates are best-effort; silently ignore if unavailable
    }
  }

  static Future<void> clearWidget() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      await Future.wait([
        HomeWidget.saveWidgetData<String>('profile_name', 'pfSense Manager'),
        HomeWidget.saveWidgetData<String>('cpu_temp', '--'),
        HomeWidget.saveWidgetData<String>('gateway_name', '--'),
        HomeWidget.saveWidgetData<String>('gateway_latency', '--'),
        HomeWidget.saveWidgetData<String>('traffic_in', '--'),
        HomeWidget.saveWidgetData<String>('traffic_out', '--'),
        HomeWidget.saveWidgetData<String>('last_updated', '--'),
      ]);
      await HomeWidget.updateWidget(androidName: _androidWidgetName);
    } catch (_) {}
  }
}
