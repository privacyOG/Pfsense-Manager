import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dashboard.dart';
import 'package:pfsense_manager/widgets/gateway_history_panel.dart';

void main() {
  testWidgets('shows gateway telemetry while collecting history', (tester) async {
    final gateway = GatewayStatus(
      name: 'WAN_DHCP',
      status: 'online',
      latency: 12.4,
      packetLoss: 0.5,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GatewayHistoryPanel(
            gateway: gateway,
            samples: const [],
          ),
        ),
      ),
    );

    expect(find.text('WAN_DHCP'), findsOneWidget);
    expect(find.text('ONLINE'), findsOneWidget);
    expect(find.text('Latency 12.4 ms'), findsOneWidget);
    expect(find.text('Loss 0.5%'), findsOneWidget);
    expect(find.text('Collecting gateway samples…'), findsOneWidget);
  });
}
