import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../services/pfrest_feature_registry.dart';
import '../widgets/pfrest_feature_gate.dart';
import 'captive_portal_screen.dart';
import 'pfblocker_screen.dart';

class PfBlockerFeatureScreen extends StatelessWidget {
  const PfBlockerFeatureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final decision = PfRestFeatureRegistry(
      activeProfileId: session.selectedProfile?.id,
      capabilities: session.capabilities,
    ).decision(PfRestFeature.pfBlockerStatus);

    if (!decision.isUnsupported) return const PfBlockerScreen();
    return _BlockedFeatureScaffold(
      title: 'pfBlockerNG',
      decision: decision,
      onRefresh: () => session.refreshCapabilities(),
    );
  }
}

class CaptivePortalFeatureScreen extends StatelessWidget {
  const CaptivePortalFeatureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final registry = PfRestFeatureRegistry(
      activeProfileId: session.selectedProfile?.id,
      capabilities: session.capabilities,
    );
    final sessions = registry.decision(PfRestFeature.captivePortalSessions);
    final vouchers = registry.decision(PfRestFeature.captivePortalVouchers);

    if (sessions.canAttempt || vouchers.canAttempt) {
      return const CaptivePortalScreen();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Captive Portal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PfRestFeatureNotice(
            decision: sessions,
            onRefresh: () => session.refreshCapabilities(),
          ),
          const SizedBox(height: 12),
          PfRestFeatureNotice(
            decision: vouchers,
            onRefresh: () => session.refreshCapabilities(),
          ),
          const SizedBox(height: 12),
          const Text(
            'The captive portal screen remains disabled until the selected firewall reports at least one supported read operation.',
          ),
        ],
      ),
    );
  }
}

class _BlockedFeatureScaffold extends StatelessWidget {
  const _BlockedFeatureScaffold({
    required this.title,
    required this.decision,
    required this.onRefresh,
  });

  final String title;
  final PfRestFeatureDecision decision;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PfRestFeatureBlockedView(
        decision: decision,
        onRefresh: onRefresh,
      ),
    );
  }
}
