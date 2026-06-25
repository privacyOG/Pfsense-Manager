import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/l10n/app_strings.dart';

void main() {
  group('AppStrings', () {
    test('resolves keys for each supported locale', () {
      for (final locale in AppStrings.supportedLocales) {
        final strings = AppStrings(locale);
        expect(strings.t('topTalkers'), isNotEmpty);
        expect(strings.t('dhcpManagement'), isNotEmpty);
        expect(strings.t('disconnected'), isNotEmpty);
      }
    });

    test('falls back to English for keys missing in a locale', () {
      // 'cpu' is only defined in the English map.
      expect(const AppStrings(Locale('ar')).t('cpu'), 'CPU');
    });

    test('returns the key itself when it is unknown everywhere', () {
      expect(const AppStrings(Locale('en')).t('definitely_missing'),
          'definitely_missing');
    });

    test('f() substitutes named placeholders', () {
      final strings = const AppStrings(Locale('en'));
      expect(
        strings.f('magicPacketSent', {'target': 'living-room-tv'}),
        'Magic packet sent to living-room-tv',
      );
      expect(
        strings.f('connectionsMany', {'count': '12'}),
        '12 connections',
      );
    });

    test('f() substitution works in a non-English locale', () {
      final strings = const AppStrings(Locale('de'));
      expect(
        strings.f('lastUpdated', {'time': '14:05'}),
        'Zuletzt aktualisiert 14:05',
      );
    });

    test('all new batch keys are defined (English baseline)', () {
      const newKeys = [
        'disconnected',
        'retry',
        'lastUpdated',
        'dhcpManagement',
        'searchLeases',
        'noLeases',
        'active',
        'static',
        'total',
        'wakeOnLan',
        'deleteLease',
        'deleteDhcpLease',
        'removeLeaseConfirm',
        'magicPacketSent',
        'topTalkers',
        'topTalkersSubtitle',
        'topTalkersUpdated',
        'disconnectedConnectFirst',
        'noActiveStates',
        'trafficWillAppear',
        'connectionOne',
        'connectionsMany',
      ];
      final strings = const AppStrings(Locale('en'));
      for (final key in newKeys) {
        // A missing key would fall back to the key string itself.
        expect(strings.t(key), isNot(key), reason: 'Missing "$key"');
      }
    });
  });
}
