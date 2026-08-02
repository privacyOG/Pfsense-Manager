import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/providers/profile_provider.dart';
import 'package:pfsense_manager/screens/profile_form_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('profile wizard saves a JWT password profile explicitly',
      (tester) async {
    final provider = ProfileProvider();
    addTearDown(provider.dispose);
    await _pumpForm(tester, provider);

    await _completeFirewallStep(
      tester,
      name: 'JWT firewall',
      host: 'firewall.example.test',
    );
    await _selectAuthMode(tester, 'Username and password (JWT)');

    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Used only to obtain a JWT token.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('profile-username')),
      'local-admin',
    );
    await tester.enterText(
      find.byKey(const Key('profile-auth-secret')),
      'local-password',
    );

    await _continue(tester);
    expect(find.text('Review'), findsWidgets);
    await _continue(tester);

    expect(provider.profiles, hasLength(1));
    final metadata = provider.profiles.single;
    expect(metadata.authMode, PfSenseAuthMode.jwtPassword);
    expect(metadata.apiKey, isEmpty);
    expect(metadata.password, isEmpty);

    final resolved = await ProfileProvider.resolveForConnection(metadata);
    expect(resolved.authMode, PfSenseAuthMode.jwtPassword);
    expect(resolved.password, 'local-password');
    expect(resolved.apiKey, isEmpty);
  });

  testWidgets('switching authentication modes clears the unsaved secret',
      (tester) async {
    final provider = ProfileProvider();
    addTearDown(provider.dispose);
    await _pumpForm(tester, provider);
    await _completeFirewallStep(
      tester,
      name: 'Mode switch',
      host: 'firewall.example.test',
    );

    final secret = find.byKey(const Key('profile-auth-secret'));
    await tester.enterText(secret, 'unsaved-api-key');
    expect(
      tester.widget<TextFormField>(secret).controller?.text,
      'unsaved-api-key',
    );

    await _selectAuthMode(tester, 'Username and password (JWT)');

    expect(tester.widget<TextFormField>(secret).controller?.text, isEmpty);
    expect(find.text('Password'), findsOneWidget);

    await tester.enterText(secret, 'unsaved-password');
    await _selectAuthMode(tester, 'API key — recommended');

    expect(tester.widget<TextFormField>(secret).controller?.text, isEmpty);
    expect(find.text('API key'), findsOneWidget);
  });

  testWidgets('changing authentication mode requires the new credential',
      (tester) async {
    final provider = ProfileProvider();
    addTearDown(provider.dispose);

    await provider.addProfile(
      PfSenseProfile(
        id: 'edit-auth-mode',
        name: 'Existing firewall',
        host: 'firewall.example.test',
        username: '',
        apiKey: 'saved-api-key',
      ),
    );
    final existing = provider.profiles.single;

    await _pumpForm(tester, provider, profile: existing);
    await _continue(tester);
    await _selectAuthMode(tester, 'Username and password (JWT)');
    await tester.enterText(
      find.byKey(const Key('profile-username')),
      'local-admin',
    );
    await _continue(tester);

    expect(find.text('Required'), findsOneWidget);
    expect(provider.profiles.single.authMode, PfSenseAuthMode.apiKey);

    await tester.enterText(
      find.byKey(const Key('profile-auth-secret')),
      'new-password',
    );
    await _continue(tester);
    await _continue(tester);

    expect(provider.profiles.single.authMode, PfSenseAuthMode.jwtPassword);
    final resolved = await ProfileProvider.resolveForConnection(
      provider.profiles.single,
    );
    expect(resolved.password, 'new-password');
    expect(resolved.apiKey, isEmpty);
  });
}

Future<void> _pumpForm(
  WidgetTester tester,
  ProfileProvider provider, {
  PfSenseProfile? profile,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<ProfileProvider>.value(
      value: provider,
      child: MaterialApp(home: ProfileFormScreen(profile: profile)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _completeFirewallStep(
  WidgetTester tester, {
  required String name,
  required String host,
}) async {
  await tester.enterText(find.byKey(const Key('profile-name')), name);
  await tester.enterText(find.byKey(const Key('profile-host')), host);
  await tester.enterText(find.byKey(const Key('profile-port')), '443');
  await _continue(tester);
}

Future<void> _selectAuthMode(WidgetTester tester, String label) async {
  final selector = find.byKey(const Key('profile-auth-mode'));
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _continue(WidgetTester tester) async {
  final button = find.byKey(const Key('profile-step-continue'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
