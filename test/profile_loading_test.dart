import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/providers/profile_provider.dart';
import 'package:pfsense_manager/providers/session_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('profile metadata loads without saved API keys', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'profiles': jsonEncode([
        {
          'id': 'first',
          'name': 'First',
          'host': 'first.example.test',
          'port': 443,
          'useHttps': true,
          'allowSelfSignedCert': false,
          'username': 'first-user',
        },
        {
          'id': 'second',
          'name': 'Second',
          'host': 'second.example.test',
          'port': 443,
          'useHttps': true,
          'allowSelfSignedCert': false,
          'username': 'second-user',
        },
      ]),
      'selectedProfileId': 'first',
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'profile_api_key_first': 'first-value',
      'profile_api_key_second': 'second-value',
    });

    final provider = ProfileProvider();
    await provider.loadProfiles();

    expect(provider.profiles, hasLength(2));
    expect(provider.profiles.every((profile) => profile.apiKey.isEmpty), isTrue);

    final resolved = await provider.profileForConnection(
      provider.profiles.first,
    );
    expect(resolved.apiKey, 'first-value');
    expect(provider.profiles.first.apiKey, isEmpty);
    expect(provider.profiles.last.apiKey, isEmpty);
  });

  test('session retains profile metadata instead of the supplied value', () async {
    final session = PfSenseSessionProvider();
    await session.connect(
      PfSenseProfile(
        id: 'session-test',
        name: 'Session test',
        host: 'firewall.example.test',
        useHttps: false,
        username: 'api-user',
        apiKey: 'temporary-value',
      ),
    );

    expect(session.selectedProfile, isNotNull);
    expect(session.selectedProfile!.apiKey, isEmpty);
  });
}
