import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/l10n/app_strings.dart';
import 'package:pfsense_manager/providers/app_settings_provider.dart';
import 'package:pfsense_manager/providers/profile_provider.dart';
import 'package:pfsense_manager/providers/session_provider.dart';
import 'package:pfsense_manager/screens/lock_screen.dart';
import 'package:pfsense_manager/widgets/app_lock_gate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildApp({
  required AppSettingsProvider settings,
  required ProfileProvider profiles,
  required PfSenseSessionProvider session,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: profiles),
      ChangeNotifierProvider.value(value: session),
    ],
    child: MaterialApp(
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => AppLockGate(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(
        body: Center(child: Text('Protected content')),
      ),
    ),
  );
}

void main() {
  testWidgets('configured PIN locks cold launch and app resume', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pinCode': '1234',
      'pinEnabled': true,
      'biometricEnabled': false,
      'lockTimeoutMinutes': 5,
    });

    final settings = AppSettingsProvider();
    await settings.load();
    final profiles = ProfileProvider();
    final session = PfSenseSessionProvider();

    await tester.pumpWidget(
      _buildApp(
        settings: settings,
        profiles: profiles,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.text('Protected content'), findsNothing);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.byIcon(Icons.lock_open));
    await tester.pumpAndSettle();

    expect(find.byType(LockScreen), findsNothing);
    expect(find.text('Protected content'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await tester.pump();

    expect(find.byType(LockScreen), findsOneWidget);
    expect(session.suspendedForLock, isTrue);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump();

    expect(find.byType(LockScreen), findsOneWidget);
    expect(session.suspendedForLock, isTrue);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.byIcon(Icons.lock_open));
    await tester.pumpAndSettle();

    expect(find.byType(LockScreen), findsNothing);
    expect(session.suspendedForLock, isFalse);
  });

  testWidgets('app remains available when no lock method is enabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final settings = AppSettingsProvider();
    await settings.load();

    await tester.pumpWidget(
      _buildApp(
        settings: settings,
        profiles: ProfileProvider(),
        session: PfSenseSessionProvider(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LockScreen), findsNothing);
    expect(find.text('Protected content'), findsOneWidget);
  });
}
