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
  const cases = {
    'inet': 'IPv4',
    'inet6': 'IPv6',
    'inet46': 'IPv4 + IPv6',
  };

  for (final entry in cases.entries) {
    testWidgets(
      'editing ${entry.value} preserves ${entry.key} in the payload',
      (tester) async {
        final service = _RecordingService();
        final session = _ConnectedSessionProvider(service);
        addTearDown(service.dispose);
        addTearDown(session.dispose);

        await _pumpForm(
          tester,
          session: session,
          rule: _rule(entry.key),
        );

        expect(find.byKey(const Key('firewall-ip-protocol')), findsOneWidget);
        expect(find.text(entry.value), findsOneWidget);

        await _save(tester);

        expect(service.updatedRuleId, '42');
        expect(service.updatedPayload?['ipprotocol'], entry.key);
      },
    );
  }

  testWidgets('new rules use IPv4 as the explicit default', (tester) async {
    final service = _RecordingService();
    final session = _ConnectedSessionProvider(service);
    addTearDown(service.dispose);
    addTearDown(session.dispose);

    await _pumpForm(tester, session: session);

    expect(find.text('IPv4'), findsOneWidget);
    await _save(tester);

    expect(service.createdPayload?['ipprotocol'], 'inet');
  });

  testWidgets('changing the selector updates the submitted IP protocol',
      (tester) async {
    final service = _RecordingService();
    final session = _ConnectedSessionProvider(service);
    addTearDown(service.dispose);
    addTearDown(session.dispose);

    await _pumpForm(
      tester,
      session: session,
      rule: _rule('inet6'),
    );

    await tester.tap(find.byKey(const Key('firewall-ip-protocol')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IPv4 + IPv6').last);
    await tester.pumpAndSettle();
    await _save(tester);

    expect(service.updatedPayload?['ipprotocol'], 'inet46');
  });
}

Future<void> _pumpForm(
  WidgetTester tester, {
  required PfSenseSessionProvider session,
  FirewallRule? rule,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<PfSenseSessionProvider>.value(
      value: session,
      child: MaterialApp(
        home: FirewallRuleFormScreen(rule: rule),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

FirewallRule _rule(String ipProtocol) => FirewallRule(
      id: '42',
      section: 'rules',
      type: 'pass',
      interface: 'wan',
      ipProtocol: ipProtocol,
      protocol: 'tcp',
      sourceType: 'network',
      sourceNetwork: 'any',
      destinationType: 'network',
      destinationNetwork: 'any',
      destinationPortFrom: 443,
      destinationPortTo: 443,
      description: 'Keep IP version',
      enabled: true,
      createdTime: '2026-07-11T00:00:00Z',
    );

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
  Map<String, dynamic>? updatedPayload;
  String? updatedRuleId;

  @override
  Future<FirewallRule> createFirewallRule(Map<String, dynamic> ruleData) async {
    createdPayload = Map<String, dynamic>.from(ruleData);
    return _rule(ruleData['ipprotocol'] as String? ?? 'inet');
  }

  @override
  Future<void> updateFirewallRule(
    String uuid,
    Map<String, dynamic> ruleData,
  ) async {
    updatedRuleId = uuid;
    updatedPayload = Map<String, dynamic>.from(ruleData);
  }
}

class _RecordingApiClient extends PfSenseApiClient {
  _RecordingApiClient()
      : super(
          PfSenseProfile(
            id: 'firewall-form-test',
            name: 'Firewall form test',
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
