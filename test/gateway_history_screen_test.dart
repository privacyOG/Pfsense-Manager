import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dashboard.dart';
import 'package:pfsense_manager/widgets/gateway_history_panel.dart';

void main() {
  testWidgets('renders gateway history status', (tester) async {
    final gateway = GatewayStatus(
      name: 'WAN_DHCP',
      status: 'online',
      latency: 14.2,
      packetLoss: 0.7,
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
    expect(find.text('Latency 14.2 ms'), findsOneWidget);
    expect(find.text('Packet loss 0.7%'), findsOneWidget);
  });
}
