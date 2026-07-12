import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/services/pfrest_feature_registry.dart';
import 'package:pfsense_manager/utils/api_exception.dart';
import 'package:pfsense_manager/utils/api_feature_support.dart';

void main() {
  group('profile-scoped feature decisions', () {
    test('reports an exact method and path as available', () {
      final registry = PfRestFeatureRegistry(
        activeProfileId: 'profile-a',
        capabilities: _availableCapabilities(
          profileId: 'profile-a',
          operations: const [
            ('POST', '/api/v2/diagnostics/traceroute'),
          ],
        ),
      );

      final decision = registry.decision(PfRestFeature.traceroute);

      expect(decision.isAvailable, isTrue);
      expect(decision.canAttempt, isTrue);
      expect(decision.contract.method, 'POST');
      expect(decision.contract.path, '/api/v2/diagnostics/traceroute');
    });

    test('known absent operation is disabled with its dependency', () {
      final registry = PfRestFeatureRegistry(
        activeProfileId: 'profile-a',
        capabilities: _availableCapabilities(
          profileId: 'profile-a',
          operations: const [],
        ),
      );

      final decision = registry.decision(PfRestFeature.smartStatus);

      expect(decision.isUnsupported, isTrue);
      expect(decision.canAttempt, isFalse);
      expect(decision.message, contains('not reported by this firewall'));
      expect(decision.message, contains('custom pfREST SMART extension'));
    });

    test('method mismatch does not imply support', () {
      final registry = PfRestFeatureRegistry(
        activeProfileId: 'profile-a',
        capabilities: _availableCapabilities(
          profileId: 'profile-a',
          operations: const [
            ('GET', '/api/v2/diagnostics/traceroute'),
          ],
        ),
      );

      expect(
        registry.decision(PfRestFeature.traceroute).isUnsupported,
        isTrue,
      );
    });

    test('schema permission failure remains unknown and attemptable', () {
      final registry = PfRestFeatureRegistry(
        activeProfileId: 'profile-a',
        capabilities: PfRestCapabilities.limited(
          profileId: 'profile-a',
          issue: PfRestCapabilityIssue.permissionDenied,
          message: 'Schema permission denied.',
        ),
      );

      final decision = registry.decision(PfRestFeature.pfBlockerStatus);

      expect(decision.isUnknown, isTrue);
      expect(decision.canAttempt, isTrue);
      expect(decision.message, contains('schema access is forbidden'));
      expect(decision.message, contains('can still be attempted'));
    });

    test('temporary schema failure remains unknown rather than unsupported', () {
      final registry = PfRestFeatureRegistry(
        activeProfileId: 'profile-a',
        capabilities: PfRestCapabilities.limited(
          profileId: 'profile-a',
          issue: PfRestCapabilityIssue.requestFailed,
          message: 'Temporary failure.',
        ),
      );

      final decision = registry.decision(PfRestFeature.configurationBackup);

      expect(decision.isUnknown, isTrue);
      expect(decision.isUnsupported, isFalse);
      expect(decision.canAttempt, isTrue);
    });

    test('capability data from another profile is never reused', () {
      final registry = PfRestFeatureRegistry(
        activeProfileId: 'profile-b',
        capabilities: _availableCapabilities(
          profileId: 'profile-a',
          operations: const [
            ('GET', '/api/v2/system/config'),
          ],
        ),
      );

      final decision = registry.decision(PfRestFeature.configurationBackup);

      expect(decision.isUnknown, isTrue);
      expect(decision.message, contains('selected profile'));
    });

    test('group checks retain limited-mode compatibility', () {
      final registry = PfRestFeatureRegistry(
        activeProfileId: 'profile-a',
        capabilities: PfRestCapabilities.limited(
          profileId: 'profile-a',
          issue: PfRestCapabilityIssue.schemaUnavailable,
          message: 'Schema unavailable.',
        ),
      );

      expect(
        registry.anyCanAttempt(const [
          PfRestFeature.captivePortalSessions,
          PfRestFeature.captivePortalVouchers,
        ]),
        isTrue,
      );
      expect(
        registry.anyAvailable(const [
          PfRestFeature.captivePortalSessions,
          PfRestFeature.captivePortalVouchers,
        ]),
        isFalse,
      );
    });
  });

  group('feature request errors', () {
    test('403 remains a permission failure', () {
      final message = pfRestFeatureRequestErrorMessage(
        PfRestFeature.pfBlockerStatus,
        const ApiException('Read privilege required', 403),
      );

      expect(message, contains('Permission denied (403)'));
      expect(message, contains('saved credential cannot use it'));
      expect(message, isNot(contains('not supported')));
    });

    test('404-derived unsupported feature names the required extension', () {
      final message = pfRestFeatureRequestErrorMessage(
        PfRestFeature.captivePortalSessions,
        const UnsupportedApiFeatureException('Captive portal'),
      );

      expect(message, contains('not supported by this firewall'));
      expect(message, contains('captive portal custom pfREST extension'));
    });

    test('timeout and network failures remain temporary', () {
      final timeout = pfRestFeatureRequestErrorMessage(
        PfRestFeature.dnsLookup,
        const ApiException('Timed out', null, false, true),
      );
      final network = pfRestFeatureRequestErrorMessage(
        PfRestFeature.dnsLookup,
        const ApiException('Network failed', null, true),
      );

      expect(timeout, contains('not marked unsupported'));
      expect(network, contains('not marked unsupported'));
    });
  });
}

PfRestCapabilities _availableCapabilities({
  required String profileId,
  required List<(String, String)> operations,
}) {
  return PfRestCapabilities(
    profileId: profileId,
    status: PfRestCapabilityStatus.available,
    operations: {
      for (final operation in operations)
        PfRestCapabilities.operationKey(operation.$2, operation.$1):
            PfRestOperationCapability(
          path: operation.$2,
          method: operation.$1,
          requestFields: const {},
          tags: const {},
        ),
    },
    packageTags: const {},
    loadedAt: DateTime.utc(2026, 7, 12),
  );
}
