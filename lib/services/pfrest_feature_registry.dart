import '../models/pfrest_capabilities.dart';
import '../utils/api_exception.dart';
import '../utils/api_feature_support.dart';

enum PfRestFeature {
  traceroute,
  dnsLookup,
  smartStatus,
  configurationBackup,
  pfBlockerStatus,
  pfBlockerUpdate,
  pfBlockerToggle,
  captivePortalSessions,
  captivePortalDisconnect,
  captivePortalVouchers,
  captivePortalVoucherGeneration,
}

enum PfRestFeatureAvailability {
  available,
  unsupported,
  unknown,
}

class PfRestFeatureContract {
  const PfRestFeatureContract({
    required this.feature,
    required this.label,
    required this.path,
    required this.method,
    required this.dependency,
    required this.description,
  });

  final PfRestFeature feature;
  final String label;
  final String path;
  final String method;
  final String dependency;
  final String description;
}

const pfRestFeatureContracts = <PfRestFeature, PfRestFeatureContract>{
  PfRestFeature.traceroute: PfRestFeatureContract(
    feature: PfRestFeature.traceroute,
    label: 'Traceroute',
    path: '/api/v2/diagnostics/traceroute',
    method: 'POST',
    dependency: 'custom pfREST diagnostics extension',
    description: 'Runs traceroute from the firewall.',
  ),
  PfRestFeature.dnsLookup: PfRestFeatureContract(
    feature: PfRestFeature.dnsLookup,
    label: 'DNS lookup',
    path: '/api/v2/diagnostics/dns_lookup',
    method: 'POST',
    dependency: 'custom pfREST diagnostics extension',
    description: 'Runs a DNS query from the firewall.',
  ),
  PfRestFeature.smartStatus: PfRestFeatureContract(
    feature: PfRestFeature.smartStatus,
    label: 'SMART drive status',
    path: '/api/v2/diagnostics/smart_status',
    method: 'GET',
    dependency: 'custom pfREST SMART extension',
    description: 'Reads drive-health and SMART telemetry.',
  ),
  PfRestFeature.configurationBackup: PfRestFeatureContract(
    feature: PfRestFeature.configurationBackup,
    label: 'Configuration backup',
    path: '/api/v2/system/config',
    method: 'GET',
    dependency: 'custom pfREST configuration export extension',
    description: 'Downloads the firewall XML configuration.',
  ),
  PfRestFeature.pfBlockerStatus: PfRestFeatureContract(
    feature: PfRestFeature.pfBlockerStatus,
    label: 'pfBlockerNG status',
    path: '/api/v2/status/pfblockerng',
    method: 'GET',
    dependency: 'pfBlockerNG custom pfREST extension',
    description: 'Reads pfBlockerNG state and counters.',
  ),
  PfRestFeature.pfBlockerUpdate: PfRestFeatureContract(
    feature: PfRestFeature.pfBlockerUpdate,
    label: 'pfBlockerNG list update',
    path: '/api/v2/status/pfblockerng/update',
    method: 'POST',
    dependency: 'pfBlockerNG custom pfREST extension',
    description: 'Starts a pfBlockerNG list update.',
  ),
  PfRestFeature.pfBlockerToggle: PfRestFeatureContract(
    feature: PfRestFeature.pfBlockerToggle,
    label: 'pfBlockerNG enable control',
    path: '/api/v2/status/pfblockerng',
    method: 'PATCH',
    dependency: 'pfBlockerNG custom pfREST extension',
    description: 'Enables or pauses pfBlockerNG.',
  ),
  PfRestFeature.captivePortalSessions: PfRestFeatureContract(
    feature: PfRestFeature.captivePortalSessions,
    label: 'Captive portal sessions',
    path: '/api/v2/services/captiveportal/sessions',
    method: 'GET',
    dependency: 'captive portal custom pfREST extension',
    description: 'Lists active captive portal sessions.',
  ),
  PfRestFeature.captivePortalDisconnect: PfRestFeatureContract(
    feature: PfRestFeature.captivePortalDisconnect,
    label: 'Captive portal disconnect',
    path: '/api/v2/services/captiveportal/session',
    method: 'DELETE',
    dependency: 'captive portal custom pfREST extension',
    description: 'Disconnects an active captive portal session.',
  ),
  PfRestFeature.captivePortalVouchers: PfRestFeatureContract(
    feature: PfRestFeature.captivePortalVouchers,
    label: 'Captive portal vouchers',
    path: '/api/v2/services/captiveportal/vouchers',
    method: 'GET',
    dependency: 'captive portal custom pfREST extension',
    description: 'Lists captive portal vouchers.',
  ),
  PfRestFeature.captivePortalVoucherGeneration: PfRestFeatureContract(
    feature: PfRestFeature.captivePortalVoucherGeneration,
    label: 'Captive portal voucher generation',
    path: '/api/v2/services/captiveportal/vouchers',
    method: 'POST',
    dependency: 'captive portal custom pfREST extension',
    description: 'Generates new captive portal vouchers.',
  ),
};

class PfRestFeatureDecision {
  const PfRestFeatureDecision({
    required this.contract,
    required this.availability,
    required this.message,
  });

  final PfRestFeatureContract contract;
  final PfRestFeatureAvailability availability;
  final String message;

  bool get isAvailable => availability == PfRestFeatureAvailability.available;
  bool get isUnsupported => availability == PfRestFeatureAvailability.unsupported;
  bool get isUnknown => availability == PfRestFeatureAvailability.unknown;
  bool get canAttempt => !isUnsupported;
}

class PfRestFeatureRegistry {
  const PfRestFeatureRegistry({
    required this.activeProfileId,
    required this.capabilities,
  });

  final String? activeProfileId;
  final PfRestCapabilities? capabilities;

  PfRestFeatureDecision decision(PfRestFeature feature) {
    final contract = pfRestFeatureContracts[feature]!;
    final profileId = activeProfileId;
    final snapshot = capabilities;

    if (profileId == null || profileId.isEmpty) {
      return PfRestFeatureDecision(
        contract: contract,
        availability: PfRestFeatureAvailability.unknown,
        message: 'Connect to a firewall before checking this capability.',
      );
    }

    if (snapshot == null || snapshot.profileId != profileId) {
      return PfRestFeatureDecision(
        contract: contract,
        availability: PfRestFeatureAvailability.unknown,
        message:
            'Capability information is not available for the selected profile yet.',
      );
    }

    if (snapshot.isAvailable) {
      if (snapshot.supports(contract.path, contract.method)) {
        return PfRestFeatureDecision(
          contract: contract,
          availability: PfRestFeatureAvailability.available,
          message: '${contract.label} is reported by this firewall.',
        );
      }
      return PfRestFeatureDecision(
        contract: contract,
        availability: PfRestFeatureAvailability.unsupported,
        message:
            '${contract.label} is not reported by this firewall. Requires ${contract.dependency}.',
      );
    }

    return PfRestFeatureDecision(
      contract: contract,
      availability: PfRestFeatureAvailability.unknown,
      message: _limitedMessage(snapshot, contract),
    );
  }

  bool anyCanAttempt(Iterable<PfRestFeature> features) {
    return features.any((feature) => decision(feature).canAttempt);
  }

  bool anyAvailable(Iterable<PfRestFeature> features) {
    return features.any((feature) => decision(feature).isAvailable);
  }

  String _limitedMessage(
    PfRestCapabilities snapshot,
    PfRestFeatureContract contract,
  ) {
    final reason = switch (snapshot.issue) {
      PfRestCapabilityIssue.authentication =>
        'OpenAPI schema authentication failed.',
      PfRestCapabilityIssue.permissionDenied =>
        'OpenAPI schema access is forbidden for this credential.',
      PfRestCapabilityIssue.schemaUnavailable =>
        'This installation does not expose the OpenAPI schema.',
      PfRestCapabilityIssue.invalidSchema =>
        'The OpenAPI schema response could not be parsed.',
      PfRestCapabilityIssue.requestFailed =>
        'The OpenAPI schema request failed temporarily.',
      PfRestCapabilityIssue.notLoaded || null =>
        'Capability discovery has not completed.',
    };
    return '$reason ${contract.label} availability is unknown; the request can still be attempted.';
  }
}

String pfRestFeatureRequestErrorMessage(
  PfRestFeature feature,
  Object error,
) {
  final contract = pfRestFeatureContracts[feature]!;
  if (error is UnsupportedApiFeatureException) {
    return '${contract.label} is not supported by this firewall. Requires ${contract.dependency}.';
  }
  if (error is ApiException) {
    if (error.isAuthenticationError) {
      return 'Authentication failed (401) while using ${contract.label}. Verify the saved credential.';
    }
    if (error.isPermissionError) {
      return 'Permission denied (403) for ${contract.label}. The endpoint may be present, but the saved credential cannot use it.';
    }
    if (error.isTimeout) {
      return '${contract.label} timed out. The capability is not marked unsupported.';
    }
    if (error.isNetworkError) {
      return '${contract.label} could not reach the firewall. The capability is not marked unsupported.';
    }
  }
  return error.toString();
}
