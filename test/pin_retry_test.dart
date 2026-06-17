import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/providers/app_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/memory_pin_verifier_store.dart';

Future<String> _createTestVerifier(String pin) async => 'test:$pin';

Future<bool> _checkTestVerifier(String pin, String verifier) async =>
    verifier == 'test:$pin';

void main() {
  test('repeated incorrect PIN attempts apply a retry delay', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    var now = DateTime.utc(2026, 6, 17, 12);
    final store = MemoryPinVerifierStore();
    final settings = AppSettingsProvider(
      pinStore: store,
      now: () => now,
      createVerifier: _createTestVerifier,
      checkVerifier: _checkTestVerifier,
    );
    await settings.load();
    await settings.setPin('1234');

    expect(store.value, 'test:1234');
    expect(store.value, isNot('1234'));

    expect(await settings.verifyPin('0000'), isFalse);
    expect(await settings.verifyPin('0000'), isFalse);
    expect(await settings.verifyPin('0000'), isFalse);
    expect(settings.pinRetrySeconds, 1);

    expect(await settings.verifyPin('1234'), isFalse);

    now = now.add(const Duration(seconds: 2));
    expect(await settings.verifyPin('1234'), isTrue);
    expect(settings.pinRetrySeconds, 0);
  });
}
