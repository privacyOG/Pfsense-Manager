import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/utils/api_exception.dart';
import 'package:pfsense_manager/utils/api_feature_support.dart';

void main() {
  group('ApiFeatureSupportCache', () {
    test('marks missing optional endpoints as unsupported', () async {
      final cache = ApiFeatureSupportCache();
      var calls = 0;

      Future<void> callFeature() => requireApiFeature<void>(
            cache,
            'Traceroute',
            () async {
              calls++;
              throw const ApiException('Not found', 404);
            },
          );

      await expectLater(callFeature(), throwsA(isA<UnsupportedApiFeatureException>()));
      await expectLater(callFeature(), throwsA(isA<UnsupportedApiFeatureException>()));
      expect(calls, 1);
    });

    test('does not hide network or auth failures as unsupported', () async {
      final cache = ApiFeatureSupportCache();
      var calls = 0;

      Future<void> callFeature() => requireApiFeature<void>(
            cache,
            'DNS lookup',
            () async {
              calls++;
              throw const ApiException('Network error', null, true);
            },
          );

      await expectLater(callFeature(), throwsA(isA<ApiException>()));
      await expectLater(callFeature(), throwsA(isA<ApiException>()));
      expect(calls, 2);
    });

    test('marks successful optional endpoints as supported', () async {
      final cache = ApiFeatureSupportCache();

      final value = await requireApiFeature<int>(
        cache,
        'Configuration backup',
        () async => 7,
      );

      expect(value, 7);
      expect(cache.isKnownUnsupported('Configuration backup'), isFalse);
    });
  });
}
