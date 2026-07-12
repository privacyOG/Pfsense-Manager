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
  testWidgets('editing a description preserves untouched advanced values',
      (tester) async {
    final service = _RecordingService();
    final session = _ConnectedSession(service);
    addTearDown(service.dispose);
    addTearDown(session.dispose);

    await _pump(
      tester,
      session,
      rule: _advancedRule(),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Updated advanced rule',
    );
    await _save(tester);

    final payload = service.updatedPayload!;
    expect(payload['descr'], 'Updated advanced rule');
    expect(payload['interface'], ['wan', 'lan']);
    expect(payload['source'], '!PrivateHosts');
    expect(payload['source_port'], 'TrustedPorts');
    expect(payload['destination_port'], '8000:8080');
    expect(payload['log'], isTrue);
    expect(payload['tag'], 'policy');
    expect(payload['statetype'], 'sloppy state');
    expect(payload['tcp_flags_out_of'], ['syn', 'ack']);
    expect(payload['tcp_flags_set'], ['syn']);
    expect(payload['gateway'], 'WAN_GW');
    expect(payload['sched'], 'BusinessHours');
    expect(payload['dnpipe'], 'Download');
    expect(payload['pdnpipe'], 'Upload');
    expect(payload['defaultqueue'], 'qDefault');
    expect(payload['ackqueue'], 'qAck');
    expect(payload['quick'], isTrue);
    expect(payload['direction'], 'in');
    expect(payload.containsKey('floating'), isFalse);
  });

  testWidgets('floating conditions control interface and direction fields',
      (tester) async {
    final service = _RecordingService();
    final session = _ConnectedSession(service);
    addTearDown(service.dispose);
    addTearDown(session.dispose);

    await _pump(tester, session);
    await _openAdvanced(tester);

    expect(find.byKey(const Key('firewall-direction')), findsNothing);
    await tester.tap(find.byKey(const Key('firewall-floating')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('firewall-direction')), findsOneWidget);
    expect(find.byKey(const Key('firewall-interface-wan')), findsOneWidget);
    expect(find.byKey(const Key('firewall-interface-lan')), findsOneWidget);
  });

  testWidgets('protocol conditions show only applicable advanced controls',
      (tester) async {
    final service = _RecordingService();
    final session = _ConnectedSession(service);
    addTearDown(service.dispose);
    addTearDown(session.dispose);

    await _pump(tester, session);
    await _openAdvanced(tester);

    expect(find.byKey(const Key('firewall-tcp-flags-any')), findsOneWidget);
    expect(find.byKey(const Key('firewall-icmp-types')), findsNothing);

    await tester.tap(find.byKey(const Key('firewall-protocol')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ICMP').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('firewall-tcp-flags-any')), findsNothing);
    expect(find.byKey(const Key('firewall-icmp-types')), findsOneWidget);
    expect(find.byKey(const Key('destination-port-from')), findsNothing);
  });

  testWidgets('placement requires explicit confirmation before create',
      (tester) async {
    final service = _RecordingService();
    final session = _ConnectedSession(service);
    addTearDown(service.dispose);
    addTearDown(session.dispose);

    await _pump(tester, session);
    await _openAdvanced(tester);
    await tester.enterText(
      find.byKey(const Key('firewall-placement')),
      '3',
    );

    await _save(tester, settle: false);
    await tester.pumpAndSettle();
    expect(find.text('Place firewall rule?'), findsOneWidget);
    expect(service.createdPayload, isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(service.createdPayload, isNull);

    await _save(tester, settle: false);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Place rule'));
    await tester.pumpAndSettle();

    expect(service.createdPayload?['placement'], 3);
  });

  testWidgets('multiple interfaces cannot be saved without floating mode',
      (tester) async {
    final service = _RecordingService();
    final session = _ConnectedSession(service);
    addTearDown(service.dispose);
    addTearDown(session.dispose);

    final invalid = FirewallRule(
      id: '8',
      interfaces: const ['wan', 'lan'],
      floating: false,
      protocol: 'tcp',
      sourceNetwork: 'any',
      destinationNetwork: 'any',
    );
    await _pump(tester, session, rule: invalid);
    await _save(tester);

    expect(find.textContaining('Multiple interfaces require'), findsWidgets);
    expect(service.updatedPayload, isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  PfSenseSessionProvider session, {
  FirewallRule? rule,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<PfSenseSessionProvider>.value(
      value: session,
      child: MaterialApp(
        home: FirewallRuleFormScreen(
          rule: rule,
          availableInterfaces: const ['wan', 'lan', 'opt1'],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAdvanced(WidgetTester tester) async {
  final tile = find.byKey(const Key('firewall-rule-advanced'));
  await tester.scrollUntilVisible(
    tile,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _save(
  WidgetTester tester, {
  bool settle = true,
}) async {
  final save = find.byKey(const Key('save-firewall-rule'));
  await tester.scrollUntilVisible(
    save,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(save);
  if (settle) await tester.pumpAndSettle();
}

FirewallRule _advancedRule() => FirewallRule(
      id: '42',
      interfaces: const ['wan', 'lan'],
      type: 'pass',
      ipProtocol: 'inet',
      protocol: 'tcp',
      sourceNetwork: 'PrivateHosts',
      sourceInverted: true,
      sourcePort: 'TrustedPorts',
      destinationNetwork: 'lan:ip',
      destinationPort: '8000:8080',
      description: 'Advanced rule',
      log: true,
      tag: 'policy',
      stateType: 'sloppy state',
      tcpFlagsOutOf: const ['syn', 'ack'],
      tcpFlagsSet: const ['syn'],
      gateway: 'WAN_GW',
      schedule: 'BusinessHours',
      dnpipe: 'Download',
      pdnpipe: 'Upload',
      defaultQueue: 'qDefault',
      ackQueue: 'qAck',
      floating: true,
      quick: true,
      direction: 'in',
      createdTime: '2026-07-12T00:00:00Z',
    );

class _ConnectedSession extends PfSenseSessionProvider {
  _ConnectedSession(this._testService);

  final PfSenseService _testService;

  @override
  bool get connected => true;

  @override
  PfSenseService? get service => _testService;
}

class _RecordingService extends PfSenseService {
  _RecordingService() : super(_RecordingClient());

  Map<String, dynamic>? createdPayload;
  Map<String, dynamic>? updatedPayload;

  @override
  Future<FirewallRule> createFirewallRule(Map<String, dynamic> ruleData) async {
    createdPayload = Map<String, dynamic>.from(ruleData);
    return FirewallRule.fromJson({'id': 1, ...ruleData});
  }

  @override
  Future<void> updateFirewallRule(
    String uuid,
    Map<String, dynamic> ruleData,
  ) async {
    updatedPayload = Map<String, dynamic>.from(ruleData);
  }
}

class _RecordingClient extends PfSenseApiClient {
  _RecordingClient()
      : super(
          PfSenseProfile(
            id: 'advanced-form-test',
            name: 'Advanced form test',
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
