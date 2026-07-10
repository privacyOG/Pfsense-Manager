import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dashboard.dart';
import 'package:pfsense_manager/widgets/interface_traffic_totals.dart';

void main() {
  Widget buildTotals(InterfaceStatus interface) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: InterfaceTrafficTotals(
              interfaces: [interface],
              compact: true,
              darkSurface: true,
            ),
          ),
        ),
      ),
    );
  }

  InterfaceStatus interface({
    int errorsIn = 0,
    int errorsOut = 0,
    int collisions = 0,
  }) {
    return InterfaceStatus(
      name: 'wan',
      description: 'WAN',
      hardwareInterface: 'ixl0',
      status: 'up',
      bytesIn: 1024,
      bytesOut: 2048,
      packetsIn: 1200,
      packetsOut: 2400,
      errorsIn: errorsIn,
      errorsOut: errorsOut,
      collisions: collisions,
    );
  }

  testWidgets('compact totals use a two-column traffic grid', (tester) async {
    await tester.pumpWidget(buildTotals(interface()));

    expect(find.text('Bytes in'), findsOneWidget);
    expect(find.text('Bytes out'), findsOneWidget);
    expect(find.text('Packets in'), findsOneWidget);
    expect(find.text('Packets out'), findsOneWidget);
    expect(find.text('No interface errors reported'), findsOneWidget);

    final bytesInTop = tester.getTopLeft(find.text('Bytes in')).dy;
    final bytesOutTop = tester.getTopLeft(find.text('Bytes out')).dy;
    expect((bytesInTop - bytesOutTop).abs(), lessThan(1));
  });

  testWidgets('compact totals summarise interface health problems', (tester) async {
    await tester.pumpWidget(
      buildTotals(interface(errorsIn: 2, errorsOut: 1, collisions: 1)),
    );

    expect(find.text('3 errors • 1 collision'), findsOneWidget);
    expect(find.byKey(const Key('interface-health-summary')), findsOneWidget);
  });
}
