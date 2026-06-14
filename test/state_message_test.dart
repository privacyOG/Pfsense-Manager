import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/widgets/state_message.dart';

void main() {
  testWidgets('shows the supplied icon and text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StateMessage(
            icon: Icons.cloud_off_outlined,
            text: 'Disconnected',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
  });

  testWidgets('supports details and an action', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StateMessage(
            icon: Icons.error_outline,
            text: 'Unable to load data',
            details: 'Check the selected firewall connection.',
            action: TextButton(
              onPressed: () => pressed = true,
              child: const Text('Retry'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Unable to load data'), findsOneWidget);
    expect(
      find.text('Check the selected firewall connection.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    expect(pressed, isTrue);
  });
}
