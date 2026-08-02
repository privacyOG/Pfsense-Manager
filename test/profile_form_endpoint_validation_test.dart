import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/providers/profile_provider.dart';
import 'package:pfsense_manager/screens/profile_form_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('profile wizard shows a clear invalid endpoint error',
      (tester) async {
    final provider = ProfileProvider();
    addTearDown(provider.dispose);
    await _pumpForm(tester, provider);

    await tester.enterText(
      find.byKey(const Key('profile-name')),
      'Main firewall',
    );
    await tester.enterText(
      find.byKey(const Key('profile-host')),
      'https://user:secret@firewall.example.test',
    );
    await tester.enterText(find.byKey(const Key('profile-port')), '443');

    await _continue(tester);

    expect(
      find.text('Remove the username or password from the endpoint.'),
      findsOneWidget,
    );
    expect(provider.profiles, isEmpty);
  });

  testWidgets('profile wizard stores a normalised IPv6 endpoint',
      (tester) async {
    final provider = ProfileProvider();
    addTearDown(provider.dispose);
    await _pumpForm(tester, provider);

    await tester.enterText(
      find.byKey(const Key('profile-name')),
      'IPv6 firewall',
    );
    await tester.enterText(
      find.byKey(const Key('profile-host')),
      'https://[2001:db8::20]:8443',
    );
    await tester.enterText(find.byKey(const Key('profile-port')), '443');
    await _continue(tester);

    await tester.enterText(
      find.byKey(const Key('profile-auth-secret')),
      'api-key',
    );
    await _continue(tester);
    await _continue(tester);

    expect(provider.profiles, hasLength(1));
    final profile = provider.profiles.single;
    expect(profile.host, '2001:db8::20');
    expect(profile.port, 8443);
    expect(profile.useHttps, isTrue);
    expect(profile.baseUrl, 'https://[2001:db8::20]:8443');
    expect(profile.username, isEmpty);
  });
}

Future<void> _pumpForm(
  WidgetTester tester,
  ProfileProvider provider,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<ProfileProvider>.value(
      value: provider,
      child: const MaterialApp(home: ProfileFormScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _continue(WidgetTester tester) async {
  final button = find.byKey(const Key('profile-step-continue'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
