import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/providers/session_provider.dart';
import 'package:pfsense_manager/screens/diagnostics_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Ping offers only packet counts accepted by pfREST',
      (tester) async {
    final session = PfSenseSessionProvider();
    addTearDown(session.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<PfSenseSessionProvider>.value(
        value: session,
        child: const MaterialApp(home: DiagnosticsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    for (final count in ['1', '4', '8', '10']) {
      expect(find.widgetWithText(ChoiceChip, count), findsOneWidget);
    }
    expect(find.widgetWithText(ChoiceChip, '16'), findsNothing);

    final selected = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '4'),
    );
    expect(selected.selected, isTrue);
  });
}
