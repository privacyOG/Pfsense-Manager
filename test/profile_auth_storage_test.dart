import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/profile.dart';
import 'package:pfsense_manager/providers/profile_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('legacy profile metadata defaults to API-key authentication', () {
    final profile = PfSenseProfile.fromJson({
      'id': 'legacy',
      'name': 'Legacy profile',
      'host': 'firewall.example.test',
      'port': 443,
      'useHttps': true,
      'allowSelfSignedCert': false,
      'username': 'api-user',
    });

    expect(profile.authMode, PfSenseAuthMode.apiKey);
    expect(profile.apiKey, isEmpty);
    expect(profile.password, isEmpty);
    expect(profile.trustedCertificateSha256, isEmpty);
  });

  test('profile metadata includes mode and trust data but excludes secrets', () {
    final profile = PfSenseProfile(
      id: 'jwt-export',
      name: 'JWT profile',
      host: 'firewall.example.test',
      username: 'local-admin',
      authMode: PfSenseAuthMode.jwtPassword,
      allowSelfSignedCert: true,
      trustedCertificateSha256:
          '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF',
      apiKey: 'api-secret',
      password: 'password-secret',
    );

    final json = profile.toJson();
    expect(json['authMode'], 'jwt_password');
    expect(json['trustedCertificateSha256'], hasLength(64));
    expect(json.containsKey('apiKey'), isFalse);
    expect(json.containsKey('password'), isFalse);
    expect(json.values, isNot(contains('api-secret')));
    expect(json.values, isNot(contains('password-secret')));
  });

  test('connection resolution loads only the selected credential type',
      () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'profile_api_key_api-profile': 'saved-api-key',
      'profile_password_api-profile': 'unused-password',
      'profile_api_key_jwt-profile': 'unused-api-key',
      'profile_password_jwt-profile': 'saved-password',
    });

    final apiProfile = await ProfileProvider.resolveForConnection(
      PfSenseProfile(
        id: 'api-profile',
        name: 'API profile',
        host: 'api.example.test',
        username: '',
      ),
    );
    final jwtProfile = await ProfileProvider.resolveForConnection(
      PfSenseProfile(
        id: 'jwt-profile',
        name: 'JWT profile',
        host: 'jwt.example.test',
        username: 'local-admin',
        authMode: PfSenseAuthMode.jwtPassword,
      ),
    );

    expect(apiProfile.apiKey, 'saved-api-key');
    expect(apiProfile.password, isEmpty);
    expect(jwtProfile.apiKey, isEmpty);
    expect(jwtProfile.password, 'saved-password');
  });

  test('JWT password is stored separately and omitted from profile metadata',
      () async {
    final provider = ProfileProvider();
    addTearDown(provider.dispose);

    await provider.addProfile(
      PfSenseProfile(
        id: 'stored-jwt',
        name: 'Stored JWT',
        host: 'firewall.example.test',
        username: 'local-admin',
        authMode: PfSenseAuthMode.jwtPassword,
        password: 'saved-password',
      ),
    );

    expect(provider.profiles.single.password, isEmpty);
    expect(provider.profiles.single.apiKey, isEmpty);

    final resolved = await ProfileProvider.resolveForConnection(
      provider.profiles.single,
    );
    expect(resolved.password, 'saved-password');
    expect(resolved.apiKey, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    final metadata = prefs.getString('profiles') ?? '';
    expect(metadata, isNot(contains('saved-password')));
    expect(metadata, contains('jwt_password'));
  });

  test('profile export never contains API keys or passwords', () async {
    final provider = ProfileProvider();
    addTearDown(provider.dispose);

    await provider.addProfile(
      PfSenseProfile(
        id: 'export-api',
        name: 'Export API',
        host: 'api.example.test',
        username: '',
        apiKey: 'private-api-key',
      ),
    );
    await provider.addProfile(
      PfSenseProfile(
        id: 'export-jwt',
        name: 'Export JWT',
        host: 'jwt.example.test',
        username: 'local-admin',
        authMode: PfSenseAuthMode.jwtPassword,
        password: 'private-password',
      ),
    );

    final exported = provider.exportProfiles();
    final decoded = jsonDecode(exported) as List<dynamic>;
    expect(decoded, hasLength(2));
    expect(exported, isNot(contains('private-api-key')));
    expect(exported, isNot(contains('private-password')));
    expect(exported, contains('api_key'));
    expect(exported, contains('jwt_password'));
  });

  test('changing authentication mode removes the inactive credential',
      () async {
    final provider = ProfileProvider();
    addTearDown(provider.dispose);
    const storage = FlutterSecureStorage();

    await provider.addProfile(
      PfSenseProfile(
        id: 'switch-mode',
        name: 'Switch mode',
        host: 'firewall.example.test',
        username: '',
        apiKey: 'saved-api-key',
      ),
    );

    await provider.updateProfile(
      provider.profiles.single.copyWith(
        username: 'local-admin',
        authMode: PfSenseAuthMode.jwtPassword,
        password: 'saved-password',
      ),
    );

    expect(await storage.read(key: 'profile_api_key_switch-mode'), isNull);
    expect(
      await storage.read(key: 'profile_password_switch-mode'),
      'saved-password',
    );
  });

  test('removing a profile deletes both secure credential slots', () async {
    final provider = ProfileProvider();
    addTearDown(provider.dispose);
    const storage = FlutterSecureStorage();

    await provider.addProfile(
      PfSenseProfile(
        id: 'delete-secrets',
        name: 'Delete secrets',
        host: 'firewall.example.test',
        username: '',
        apiKey: 'saved-api-key',
      ),
    );
    await storage.write(
      key: 'profile_password_delete-secrets',
      value: 'legacy-password',
    );

    expect(
      await storage.read(key: 'profile_api_key_delete-secrets'),
      'saved-api-key',
    );
    expect(
      await storage.read(key: 'profile_password_delete-secrets'),
      'legacy-password',
    );

    await provider.removeProfile('delete-secrets');

    expect(
      await storage.read(key: 'profile_api_key_delete-secrets'),
      isNull,
    );
    expect(
      await storage.read(key: 'profile_password_delete-secrets'),
      isNull,
    );
  });
}
