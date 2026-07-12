import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/providers/session_provider.dart';
import 'package:pfsense_manager/screens/diagnostics_screen.dart';
import 'package:pfsense_manager/screens/pfrest_feature_routes.dart';
import 'package:pfsense_manager/services/pfrest_feature_registry.dart';
import 'package:pfsense_manager/widgets/pfrest_feature_gate.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('known unsupported feature tile cannot be activated',
      (tester) async {
    var activated = false;
    final decision = _registry(_availableCapabilities()).decision(
      PfRestFeature.configurationBackup,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Card(
            child: PfRestFeatureListTile(
              decision: decision,
              icon: Icons.backup_outlined,
              title: 'Configuration backup',
              availableSubtitle: 'Download configuration',
              onTap: () => activated = true,
            ),
          ),
        ),
      ),
    );

    expect(decision.isUnsupported, isTrue);
    expect(find.textContaining('custom pfREST configuration export extension'),
        findsOneWidget);
    await tester.tap(find.text('Configuration backup'));
    await tester.pump();
    expect(activated, isFalse);
  });

  testWidgets('limited capability tile remains attemptable with a warning',
      (tester) async {
    var activated = false;
    final decision = _registry(
      PfRestCapabilities.limited(
        profileId: 'profile-a',
        issue: PfRestCapabilityIssue.permissionDenied,
        message: 'Schema permission denied.',
      ),
    ).decision(PfRestFeature.configurationBackup);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Card(
            child: PfRestFeatureListTile(
              decision: decision,
              icon: Icons.backup_outlined,
              title: 'Configuration backup',
              availableSubtitle: 'Download configuration',
              onTap: () => activated = true,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('availability is unknown'), findsOneWidget);
    await tester.tap(find.text('Configuration backup'));
    await tester.pump();
    expect(activated, isTrue);
  });

  testWidgets('unsupported diagnostic tab never exposes its run control',
      (tester) async {
    final session = _FakeSession(_availableCapabilities());
    addTearDown(session.dispose);

    await tester.pumpWidget(_withSession(session, const DiagnosticsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Traceroute'));
    await tester.pumpAndSettle();

    expect(find.text('Traceroute unavailable'), findsOneWidget);
    expect(find.textContaining('custom pfREST diagnostics extension'),
        findsOneWidget);
    expect(find.text('Run Traceroute'), findsNothing);
  });

  testWidgets('limited diagnostic tab remains usable and explains uncertainty',
      (tester) async {
    final session = _FakeSession(
      PfRestCapabilities.limited(
        profileId: 'profile-a',
        issue: PfRestCapabilityIssue.permissionDenied,
        message: 'Schema permission denied.',
      ),
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(_withSession(session, const DiagnosticsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Traceroute'));
    await tester.pumpAndSettle();

    expect(find.text('Traceroute availability unknown'), findsOneWidget);
    expect(find.text('Run Traceroute'), findsOneWidget);
  });

  testWidgets('unsupported pfBlockerNG route is blocked before data loading',
      (tester) async {
    final session = _FakeSession(_availableCapabilities());
    addTearDown(session.dispose);

    await tester.pumpWidget(
      _withSession(session, const PfBlockerFeatureScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('pfBlockerNG status unavailable'), findsOneWidget);
    expect(find.textContaining('pfBlockerNG custom pfREST extension'),
        findsOneWidget);
    expect(find.text('Update lists'), findsNothing);
  });

  testWidgets('unsupported captive portal route exposes no management tabs',
      (tester) async {
    final session = _FakeSession(_availableCapabilities());
    addTearDown(session.dispose);

    await tester.pumpWidget(
      _withSession(session, const CaptivePortalFeatureScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Captive portal sessions unavailable'), findsOneWidget);
    expect(find.text('Captive portal vouchers unavailable'), findsOneWidget);
    expect(find.text('Generate'), findsNothing);
    expect(find.text('Disconnect'), findsNothing);
  });
}

Widget _withSession(PfSenseSessionProvider session, Widget child) {
  return ChangeNotifierProvider<PfSenseSessionProvider>.value(
    value: session,
    child: MaterialApp(home: child),
  );
}

PfRestFeatureRegistry _registry(PfRestCapabilities capabilities) {
  return PfRestFeatureRegistry(
    activeProfileId: 'profile-a',
    capabilities: capabilities,
  );
}

PfRestCapabilities _availableCapabilities() {
  return PfRestCapabilities(
    profileId: 'profile-a',
    status: PfRestCapabilityStatus.available,
    operations: const {},
    packageTags: const {},
    loadedAt: DateTime.utc(2026, 7, 12),
  );
}

class _FakeSession extends PfSenseSessionProvider {
  _FakeSession(this.snapshot);

  final PfRestCapabilities snapshot;
  final PfSenseProfile profile = PfSenseProfile(
    id: 'profile-a',
    name: 'Test firewall',
    host: 'firewall.example.test',
    username: 'api-user',
  );

  @override
  bool get connected => true;

  @override
  PfSenseProfile? get selectedProfile => profile;

  @override
  PfRestCapabilities? get capabilities => snapshot;

  @override
  Future<PfRestCapabilities?> refreshCapabilities() async => snapshot;
}
