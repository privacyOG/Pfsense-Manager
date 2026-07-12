import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/pfrest_capabilities.dart';
import 'package:pfsense_manager/services/firewall_nat_service.dart';
import 'package:pfsense_manager/services/pfrest_feature_registry.dart';

void main() {
  test('registers exact pfREST NAT paths and methods', () {
    expect(
      pfRestFeatureContracts[PfRestFeature.natPortForwardsRead]?.path,
      FirewallNatService.portForwardsPath,
    );
    expect(
      pfRestFeatureContracts[PfRestFeature.natPortForwardCreate]?.method,
      'POST',
    );
    expect(
      pfRestFeatureContracts[PfRestFeature.natOneToOneUpdate]?.path,
      FirewallNatService.oneToOneMappingPath,
    );
    expect(
      pfRestFeatureContracts[PfRestFeature.natOutboundModeUpdate]?.method,
      'PATCH',
    );
    expect(
      pfRestFeatureContracts[PfRestFeature.natOutboundMappingDelete]?.path,
      FirewallNatService.outboundMappingPath,
    );
  });

  test('available schema exposes independent read and write decisions', () {
    final capabilities = _capabilities({
      _operation(FirewallNatService.portForwardsPath, 'GET'),
      _operation(FirewallNatService.portForwardPath, 'POST'),
      _operation(FirewallNatService.portForwardPath, 'PATCH'),
    });
    final registry = PfRestFeatureRegistry(
      activeProfileId: 'firewall-1',
      capabilities: capabilities,
    );

    expect(
      registry.decision(PfRestFeature.natPortForwardsRead).isAvailable,
      isTrue,
    );
    expect(
      registry.decision(PfRestFeature.natPortForwardCreate).isAvailable,
      isTrue,
    );
    expect(
      registry.decision(PfRestFeature.natPortForwardUpdate).isAvailable,
      isTrue,
    );
    expect(
      registry.decision(PfRestFeature.natPortForwardDelete).isUnsupported,
      isTrue,
    );
    expect(
      registry.decision(PfRestFeature.natOneToOneRead).isUnsupported,
      isTrue,
    );
  });

  test('limited schema keeps NAT availability unknown instead of unsupported', () {
    final registry = PfRestFeatureRegistry(
      activeProfileId: 'firewall-1',
      capabilities: PfRestCapabilities.limited(
        profileId: 'firewall-1',
        issue: PfRestCapabilityIssue.permissionDenied,
        message: 'Schema permission denied.',
      ),
    );

    final decision = registry.decision(PfRestFeature.natOutboundMappingsRead);
    expect(decision.isUnknown, isTrue);
    expect(decision.canAttempt, isTrue);
    expect(decision.message, contains('forbidden'));
  });
}

PfRestCapabilities _capabilities(Set<PfRestOperationCapability> operations) {
  return PfRestCapabilities(
    profileId: 'firewall-1',
    status: PfRestCapabilityStatus.available,
    operations: {
      for (final operation in operations)
        PfRestCapabilities.operationKey(operation.path, operation.method): operation,
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
    tags: const {'Firewall NAT'},
  );
}
