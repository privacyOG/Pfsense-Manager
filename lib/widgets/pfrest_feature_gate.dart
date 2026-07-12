import 'package:flutter/material.dart';

import '../services/pfrest_feature_registry.dart';

class PfRestFeatureListTile extends StatelessWidget {
  const PfRestFeatureListTile({
    super.key,
    required this.decision,
    required this.icon,
    required this.title,
    required this.availableSubtitle,
    required this.onTap,
    this.trailing,
    this.enabled = true,
  });

  final PfRestFeatureDecision decision;
  final IconData icon;
  final String title;
  final String availableSubtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final canOpen = enabled && decision.canAttempt;
    final scheme = Theme.of(context).colorScheme;
    final stateIcon = decision.isUnsupported
        ? Icons.extension_off_outlined
        : decision.isUnknown
            ? Icons.help_outline
            : null;

    return ListTile(
      enabled: canOpen,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        decision.isAvailable ? availableSubtitle : decision.message,
      ),
      trailing: stateIcon == null
          ? trailing ?? const Icon(Icons.chevron_right)
          : Icon(
              stateIcon,
              color: decision.isUnsupported
                  ? scheme.onSurfaceVariant
                  : scheme.tertiary,
            ),
      onTap: canOpen ? onTap : null,
    );
  }
}

class PfRestFeatureNotice extends StatelessWidget {
  const PfRestFeatureNotice({
    super.key,
    required this.decision,
    this.onRefresh,
    this.showWhenAvailable = false,
  });

  final PfRestFeatureDecision decision;
  final VoidCallback? onRefresh;
  final bool showWhenAvailable;

  @override
  Widget build(BuildContext context) {
    if (decision.isAvailable && !showWhenAvailable) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final color = decision.isUnsupported
        ? scheme.error
        : decision.isUnknown
            ? scheme.tertiary
            : scheme.primary;
    final icon = decision.isUnsupported
        ? Icons.extension_off_outlined
        : decision.isUnknown
            ? Icons.help_outline
            : Icons.extension_outlined;
    final title = decision.isUnsupported
        ? '${decision.contract.label} unavailable'
        : decision.isUnknown
            ? '${decision.contract.label} availability unknown'
            : '${decision.contract.label} available';

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(decision.message),
        trailing: onRefresh == null
            ? null
            : IconButton(
                tooltip: 'Refresh capabilities',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
      ),
    );
  }
}

class PfRestFeatureBlockedView extends StatelessWidget {
  const PfRestFeatureBlockedView({
    super.key,
    required this.decision,
    this.onRefresh,
  });

  final PfRestFeatureDecision decision;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PfRestFeatureNotice(decision: decision, onRefresh: onRefresh),
        const SizedBox(height: 8),
        Text(
          decision.contract.description,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        SelectableText(
          '${decision.contract.method} ${decision.contract.path}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
