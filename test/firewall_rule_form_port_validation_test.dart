import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/firewall_rule.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/providers/session_provider.dart';
import 'package:pfsense_manager/screens/firewall_rule_form_screen.dart';
import 'package:pfsense_manager/services/api_client.dart';
import 'package:pfsense_manager/services/pfsense_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('requires a starting port when only ending port is entered',
      (tester) async {
    final fixture = await _pumpForm(tester);

    await _selectProtocol(tester, 'TCP');
    await _enterPorts(tester, to: '443');
    await _save(tester);

    expect(find.text('Enter a starting port.'), findsOneWidget);
    expect(fixture.service.createdPayload, isNull);
  });

  testWidgets('rejects a reversed destination port range', (tester) async {
    final fixture = await _pumpForm(tester);

    await _selectProtocol(tester, 'TCP');
    await _enterPorts(tester, from: '2000', to: '1000');
    await _save(tester);

    expect(
      find.text('Ending port must be greater than or equal to starting port.'),
      findsOneWidget,
    );
    expect(fixture.service.createdPayload, isNull);
  });

  testWidgets('submits a single destination port', (tester) async {
    final fixture = await _pumpForm(tester);

    await _selectProtocol(tester, 'TCP');
    await _enterPorts(tester, from: '443');
    await _save(tester);

    expect(fixture.service.createdPayload?['destination_port'], '443');
  });

  testWidgets('submits an ordered destination port range', (tester) async {
    final fixture = await _pumpForm(tester);

    await _selectProtocol(tester, 'TCP/UDP');
    await _enterPorts(tester, from: '1000', to: '2000');
    await _save(tester);

    expect(fixture.service.createdPayload?['destination_port'], '1000:2000');
  });

  for (final protocol in ['ICMP', 'ANY']) {
    testWidgets(
      'switching to $protocol clears and omits destination ports',
      (tester) async {
        final fixture = await _pumpForm(tester);

        await _selectProtocol(tester, 'TCP');
        await _enterPorts(tester, from: '443', to: '443');
        await _selectProtocol(tester, protocol);

        expect(
          find.byKey(const Key('destination-port-from')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('destination-port-to')),
          findsNothing,
        );

        await _save(tester);

        expect(
          fixture.service.createdPayload?.containsKey('destination_port'),
          isFalse,
        );
      },
    );
  }
}

Future<_FormFixture> _pumpForm(WidgetTester tester) async {
  final service = _RecordingService();
  final session = _ConnectedSessionProvider(service);
  addTearDown(service.dispose);
  addTearDown(session.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<PfSenseSessionProvider>.value(
      value: session,
      child: const MaterialApp(
        home: FirewallRuleFormScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _FormFixture(service);
}

Future<void> _selectProtocol(WidgetTester tester, String label) async {
  final selector = find.byKey(const Key('firewall-protocol'));
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _enterPorts(
  WidgetTester tester, {
  String from = '',
  String to = '',
}) async {
  final fromField = find.byKey(const Key('destination-port-from'));
  final toField = find.byKey(const Key('destination-port-to'));
  await tester.ensureVisible(fromField);
  if (from.isNotEmpty) await tester.enterText(fromField, from);
  if (to.isNotEmpty) await tester.enterText(toField, to);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  final save = find.widgetWithText(FilledButton, 'Save');
  await tester.scrollUntilVisible(
    save,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(save);
  await tester.pumpAndSettle();
}

class _FormFixture {
  const _FormFixture(this.service);

  final _RecordingService service;
}

class _ConnectedSessionProvider extends PfSenseSessionProvider {
  _ConnectedSessionProvider(this._testService);

  final PfSenseService _testService;

  @override
  bool get connected => true;

  @override
  PfSenseService? get service => _testService;
}

class _RecordingService extends PfSenseService {
  _RecordingService() : super(_RecordingApiClient());

  Map<String, dynamic>? createdPayload;

  @override
  Future<FirewallRule> createFirewallRule(Map<String, dynamic> ruleData) async {
    createdPayload = Map<String, dynamic>.from(ruleData);
    return FirewallRule(
      id: 'created',
      section: 'rules',
      type: ruleData['type'] as String? ?? 'pass',
      interface: 'wan',
      ipProtocol: ruleData['ipprotocol'] as String? ?? 'inet',
      protocol: ruleData['protocol'] as String?,
      sourceType: 'network',
      sourceNetwork: ruleData['source'] as String? ?? 'any',
      destinationType: 'network',
      destinationNetwork: ruleData['destination'] as String? ?? 'any',
      description: ruleData['descr'] as String? ?? '',
      enabled: !(ruleData['disabled'] as bool? ?? false),
      createdTime: '2026-07-11T00:00:00Z',
    );
  }
}

class _RecordingApiClient extends PfSenseApiClient {
  _RecordingApiClient()
      : super(
          PfSenseProfile(
            id: 'firewall-port-form-test',
            name: 'Firewall port form test',
            host: 'firewall.example.test',
            username: 'api-user',
            apiKey: 'test-key',
          ),
        );

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <String, dynamic>{'data': <dynamic>[]},
    );
  }
}
