import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/screens/alert_settings_screen.dart';
import 'package:pfsense_manager/services/background_alert_diagnostics.dart';
import 'package:pfsense_manager/services/background_alert_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      backgroundAlertsEnabledKey: true,
      backgroundAlertCpuTempKey: 80.0,
      backgroundAlertPacketLossKey: 15.0,
      backgroundAlertGatewayKey: true,
    });
  });

  testWidgets('settings shows the latest background failure and remediation',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = BackgroundAlertDiagnosticsStore(prefs);
    final attempted = DateTime.utc(2026, 7, 11, 10);
    await store.recordAttempt(attempted);
    await store.recordFailure(
      const BackgroundAlertFailure(
        category: BackgroundAlertFailureCategory.permission,
        message:
            'The saved credential cannot read the status endpoints required by background alerts.',
      ),
      attempted,
    );

    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: AlertSettingsScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Background alert health'), findsOneWidget);
    expect(find.text('Attention required'), findsOneWidget);
    expect(find.text('API permission'), findsOneWidget);
    expect(
      find.text(
        'The saved credential cannot read the status endpoints required by background alerts.',
      ),
      findsOneWidget,
    );
    expect(find.text('Never'), findsOneWidget);
  });

  testWidgets('refresh updates the health panel after a successful check',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = BackgroundAlertDiagnosticsStore(prefs);
    final attempt = DateTime.utc(2026, 7, 11, 10);
    await store.recordAttempt(attempt);
    await store.recordFailure(
      const BackgroundAlertFailure(
        category: BackgroundAlertFailureCategory.network,
        message: 'The firewall could not be reached from the current network.',
      ),
      attempt,
    );

    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: AlertSettingsScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Attention required'), findsOneWidget);

    final success = DateTime.utc(2026, 7, 11, 10, 5);
    await store.recordSuccess(success);
    await tester.tap(
      find.byKey(const Key('background-alert-health-refresh')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Healthy'), findsOneWidget);
    expect(find.text('Network connection'), findsNothing);
    expect(find.text('Never'), findsNothing);
  });
}
