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

  testWidgets('profile form shows a clear invalid endpoint error',
      (tester) async {
    final provider = ProfileProvider();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ProfileProvider>.value(
        value: provider,
        child: const MaterialApp(home: ProfileFormScreen()),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Main firewall');
    await tester.enterText(
      fields.at(1),
      'https://user:secret@firewall.example.test',
    );
    await tester.enterText(fields.at(2), '443');
    await tester.enterText(fields.at(3), 'api-user');
    await tester.enterText(fields.at(4), 'api-key');

    final saveButton = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(
      find.text('Remove the username or password from the endpoint.'),
      findsOneWidget,
    );
    expect(provider.profiles, isEmpty);
  });

  testWidgets('profile form stores a normalised IPv6 endpoint',
      (tester) async {
    final provider = ProfileProvider();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ProfileProvider>.value(
        value: provider,
        child: const MaterialApp(home: ProfileFormScreen()),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'IPv6 firewall');
    await tester.enterText(fields.at(1), 'https://[2001:db8::20]:8443');
    await tester.enterText(fields.at(2), '443');
    await tester.enterText(fields.at(3), 'api-user');
    await tester.enterText(fields.at(4), 'api-key');

    final saveButton = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(provider.profiles, hasLength(1));
    final profile = provider.profiles.single;
    expect(profile.host, '2001:db8::20');
    expect(profile.port, 8443);
    expect(profile.useHttps, isTrue);
    expect(profile.baseUrl, 'https://[2001:db8::20]:8443');
  });
}
