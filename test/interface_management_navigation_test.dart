import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/providers/session_provider.dart';
import 'package:pfsense_manager/screens/network_monitor_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Network Live opens the interface manager', (tester) async {
    final session = PfSenseSessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<PfSenseSessionProvider>.value(
        value: session,
        child: const MaterialApp(
          home: Scaffold(body: NetworkMonitorScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-interface-management')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-interface-management')));
    await tester.pumpAndSettle();

    expect(find.text('Interfaces'), findsOneWidget);
    expect(find.text('Interface management unavailable'), findsOneWidget);
    expect(
      find.text('Connect to a firewall to view interface capabilities.'),
      findsOneWidget,
    );
  });
}
