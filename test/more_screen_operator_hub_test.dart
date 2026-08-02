import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/providers/session_provider.dart';
import 'package:pfsense_manager/screens/more_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('operator hub shows connection context and task groups',
      (tester) async {
    final session = PfSenseSessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<PfSenseSessionProvider>.value(
        value: session,
        child: const MaterialApp(home: Scaffold(body: MoreScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No firewall selected'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Operate and troubleshoot'), findsOneWidget);
    expect(find.byKey(const Key('operator-hub-search')), findsOneWidget);
  });

  testWidgets('operator hub search filters tools and can be cleared',
      (tester) async {
    final session = PfSenseSessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<PfSenseSessionProvider>.value(
        value: session,
        child: const MaterialApp(home: Scaffold(body: MoreScreen())),
      ),
    );
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('operator-hub-search'));
    await tester.enterText(search, 'profiles');
    await tester.pumpAndSettle();

    expect(find.text('Firewall profiles'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Operate and troubleshoot'), findsNothing);

    await tester.enterText(search, 'nonexistent tool');
    await tester.pumpAndSettle();

    expect(find.textContaining('No tools match'), findsOneWidget);
    expect(find.text('Clear search'), findsOneWidget);

    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Operate and troubleshoot'), findsOneWidget);
  });
}
