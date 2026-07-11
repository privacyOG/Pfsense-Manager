import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dashboard.dart';
import 'package:pfsense_manager/widgets/dashboard_alert_strip.dart';

void main() {
  testWidgets('shows unavailable and retained sections by name',
      (tester) async {
    final data = DashboardData(
      cpuUsage: 12,
      memoryUsage: 24,
      uptime: '1 day',
      systemStatus: const DashboardSectionStatus.current(),
      gatewayStatus: const DashboardSectionStatus.unavailable(
        'Gateway status: Permission denied (403)',
      ),
      interfaceStatus: const DashboardSectionStatus.stale(
        'Interface status: Request timed out.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardAlertStrip(data: data, profileId: null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gateways unavailable'), findsOneWidget);
    expect(find.text('No data returned'), findsOneWidget);
    expect(find.text('Interfaces data retained'), findsOneWidget);
    expect(find.text('Showing last successful data'), findsOneWidget);
    expect(find.text('No active alerts'), findsNothing);
  });

  testWidgets('section details expose the affected endpoint error',
      (tester) async {
    final data = DashboardData.empty(
      systemStatus: const DashboardSectionStatus.current(),
      gatewayStatus: const DashboardSectionStatus.unavailable(
        'Gateway status: API key cannot access this endpoint (403)',
      ),
      interfaceStatus: const DashboardSectionStatus.current(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardAlertStrip(data: data, profileId: null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gateways unavailable'));
    await tester.pumpAndSettle();

    expect(
      find.text('Gateway status: API key cannot access this endpoint (403)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Check the profile permissions'),
      findsOneWidget,
    );
  });

  testWidgets('stale system data does not raise current threshold warnings',
      (tester) async {
    final data = DashboardData(
      cpuUsage: 99,
      memoryUsage: 99,
      diskUsage: 99,
      temperatureC: 99,
      uptime: '1 day',
      systemStatus: const DashboardSectionStatus.stale(
        'System status: Request timed out.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardAlertStrip(data: data, profileId: null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('System data retained'), findsOneWidget);
    expect(find.text('CPU high'), findsNothing);
    expect(find.text('RAM high'), findsNothing);
    expect(find.text('Disk high'), findsNothing);
    expect(find.text('Thermal alert'), findsNothing);
  });

  testWidgets('current telemetry continues to show threshold warnings',
      (tester) async {
    final data = DashboardData(
      cpuUsage: 90,
      memoryUsage: 20,
      uptime: '1 day',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardAlertStrip(data: data, profileId: null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CPU high'), findsOneWidget);
    expect(find.text('System data retained'), findsNothing);
  });
}
