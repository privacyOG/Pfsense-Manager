import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/services/pfrest_feature_registry.dart';

void main() {
  test('exposes alias operations independently from the OpenAPI snapshot', () {
    final registry = PfRestFeatureRegistry(
      activeProfileId: 'profile-1',
      capabilities: _capabilities({
        _operation('/api/v2/firewall/aliases', 'GET'),
        _operation('/api/v2/firewall/alias', 'POST'),
        _operation('/api/v2/firewall/alias', 'PATCH'),
      }),
    );

    expect(
      registry.decision(PfRestFeature.firewallAliasesRead).isAvailable,
      isTrue,
    );
    expect(
      registry.decision(PfRestFeature.firewallAliasCreate).isAvailable,
      isTrue,
    );
    expect(
      registry.decision(PfRestFeature.firewallAliasUpdate).isAvailable,
      isTrue,
    );
    expect(
      registry.decision(PfRestFeature.firewallAliasDelete).isUnsupported,
      isTrue,
    );
  });

  test('read-only schema permits browsing but blocks every write action', () {
    final registry = PfRestFeatureRegistry(
      activeProfileId: 'profile-1',
      capabilities: _capabilities({
        _operation('/api/v2/firewall/aliases', 'GET'),
      }),
    );

    expect(
      registry.decision(PfRestFeature.firewallAliasesRead).canAttempt,
      isTrue,
    );
    expect(
      registry.decision(PfRestFeature.firewallAliasCreate).canAttempt,
      isFalse,
    );
    expect(
      registry.decision(PfRestFeature.firewallAliasUpdate).canAttempt,
      isFalse,
    );
    expect(
      registry.decision(PfRestFeature.firewallAliasDelete).canAttempt,
      isFalse,
    );
  });

  test('limited schema keeps direct compatibility attempts available', () {
    final registry = PfRestFeatureRegistry(
      activeProfileId: 'profile-1',
      capabilities: PfRestCapabilities.limited(
        profileId: 'profile-1',
        issue: PfRestCapabilityIssue.permissionDenied,
        message: 'Schema forbidden.',
      ),
    );

    for (final feature in const [
      PfRestFeature.firewallAliasesRead,
      PfRestFeature.firewallAliasCreate,
      PfRestFeature.firewallAliasUpdate,
      PfRestFeature.firewallAliasDelete,
    ]) {
      final decision = registry.decision(feature);
      expect(decision.isUnknown, isTrue);
      expect(decision.canAttempt, isTrue);
      expect(decision.message, contains('availability is unknown'));
    }
  });

  test('alias contracts use the singular write and plural read endpoints', () {
    expect(
      pfRestFeatureContracts[PfRestFeature.firewallAliasesRead]!.path,
      '/api/v2/firewall/aliases',
    );
    expect(
      pfRestFeatureContracts[PfRestFeature.firewallAliasesRead]!.method,
      'GET',
    );
    expect(
      pfRestFeatureContracts[PfRestFeature.firewallAliasCreate]!.path,
      '/api/v2/firewall/alias',
    );
    expect(
      pfRestFeatureContracts[PfRestFeature.firewallAliasCreate]!.method,
      'POST',
    );
    expect(
      pfRestFeatureContracts[PfRestFeature.firewallAliasUpdate]!.method,
      'PATCH',
    );
    expect(
      pfRestFeatureContracts[PfRestFeature.firewallAliasDelete]!.method,
      'DELETE',
    );
  });
}

PfRestCapabilities _capabilities(Set<PfRestOperationCapability> operations) {
  return PfRestCapabilities(
    profileId: 'profile-1',
    status: PfRestCapabilityStatus.available,
    operations: {
      for (final operation in operations)
        PfRestCapabilities.operationKey(operation.path, operation.method):
            operation,
    },
    packageTags: const {},
    loadedAt: DateTime.utc(2026, 7, 12),
  );
}

PfRestOperationCapability _operation(String path, String method) {
  return PfRestOperationCapability(
    path: path,
    method: method,
    requestFields: const {},
    tags: const {'Firewall'},
  );
}
