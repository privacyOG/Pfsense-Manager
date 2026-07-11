import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/system_info.dart';
import 'package:pfsense_manager/widgets/system_info_details.dart';

void main() {
  testWidgets('marks missing mirror and repository information as unreported',
      (tester) async {
    final info = SystemInfo.fromJson({
      'data': {
        'version': '2.8.0-RELEASE',
        'hostname': 'firewall',
      },
    });

    await _pumpDetails(tester, info);

    expect(find.text('Package mirror'), findsOneWidget);
    expect(find.text('Repository data not reported'), findsOneWidget);
    expect(
      find.text(
        'pfREST did not return repository information for this firewall.',
      ),
      findsOneWidget,
    );
    expect(find.text('pfSense Manager app'), findsOneWidget);
    expect(find.text('9.9.9'), findsOneWidget);
    expect(find.text('https://cloud.privacyx.co/'), findsNothing);
    expect(find.text('pfSense Manager'), findsNothing);
  });

  testWidgets('shows partial repository fields without inferred values',
      (tester) async {
    final info = SystemInfo.fromJson({
      'data': {
        'version': '2.8.0-RELEASE',
        'hostname': 'firewall',
        'repositories': [
          {
            'name': 'primary',
          },
        ],
      },
    });

    await _pumpDetails(tester, info);

    expect(find.text('Repository data not reported'), findsNothing);
    expect(find.text('primary'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('URL'), findsOneWidget);
    expect(find.text('https://cloud.privacyx.co/'), findsNothing);
    expect(find.text('Enabled'), findsNothing);
  });

  testWidgets('shows valid mirror and repository responses unchanged',
      (tester) async {
    final info = SystemInfo.fromJson({
      'data': {
        'version': '2.8.0-RELEASE',
        'hostname': 'firewall',
        'package_mirror_url': 'https://packages.example.test/',
        'repositories': [
          {
            'name': 'primary',
            'url': 'https://repository.example.test/',
            'priority': 1,
            'enabled': true,
          },
        ],
      },
    });

    await _pumpDetails(tester, info);

    expect(find.text('https://packages.example.test/'), findsOneWidget);
    expect(find.text('primary'), findsOneWidget);
    expect(find.text('https://repository.example.test/'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Repository data not reported'), findsNothing);
  });
}

Future<void> _pumpDetails(WidgetTester tester, SystemInfo info) async {
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SystemInfoDetails(
            info: info,
            appVersion: '9.9.9',
            rebooting: false,
            onReboot: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
