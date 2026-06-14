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
}
