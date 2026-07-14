import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/administration_management.dart';
import '../providers/session_provider.dart';
import 'administration_form_screen.dart';
import 'administration_resource_screen.dart';

class AdministrationScreen extends StatelessWidget {
  const AdministrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.administrationService;
    final capabilities = service?.capabilities;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        actions: [
          IconButton(
            tooltip: 'Refresh capabilities',
            onPressed: session.connected
                ? () async {
                    await context
                        .read<PfSenseSessionProvider>()
                        .refreshCapabilities();
                  }
                : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !session.connected || service == null
          ? const Center(child: Text('Connect to a firewall to continue.'))
          : capabilities == null || !capabilities.canReadAnything
              ? _Unavailable(message: session.capabilities?.message)
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.security_outlined),
                        title: Text('Capability-aware administration'),
                        subtitle: Text(
                          'Only operations reported by the connected pfREST OpenAPI schema are shown. Read-only permissions remain visible without exposing unavailable writes.',
                        ),
                      ),
                    ),
                    for (final section in capabilities.readableSections)
                      _section(context, section, capabilities),
                  ],
                ),
    );
  }

  Widget _section(
    BuildContext context,
    AdministrationSection section,
    AdministrationManagementCapabilities capabilities,
  ) {
    final resources = AdministrationResourceKind.values
        .where(
          (kind) =>
              kind.section == section &&
              capabilities.forResource(kind).canRead,
        )
        .toList(growable: false);
    final actions = AdministrationActionKind.values
        .where(
          (kind) =>
              kind.section == section &&
              capabilities.forAction(kind).available,
        )
        .toList(growable: false);

    return Card(
      child: ExpansionTile(
        initiallyExpanded: section == AdministrationSection.certificates,
        leading: Icon(_sectionIcon(section)),
        title: Text(section.label),
        subtitle: Text(
          '${resources.length} resource${resources.length == 1 ? '' : 's'} • ${actions.length} action${actions.length == 1 ? '' : 's'}',
        ),
        children: [
          for (final kind in resources)
            Builder(
              builder: (context) {
                final capability = capabilities.forResource(kind);
                return ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(kind.label),
                  subtitle: Text(
                    capability.readOnly
                        ? 'View only'
                        : [
                            if (capability.canCreate) 'Create',
                            if (capability.canUpdate) 'Edit',
                            if (capability.canDelete) 'Delete',
                          ].join(' • '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AdministrationResourceScreen(kind: kind),
                    ),
                  ),
                );
              },
            ),
          for (final action in actions)
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(action.label),
              subtitle: Text(
                action.highImpact
                    ? 'High-impact action — confirmation required'
                    : action.secretResult
                        ? 'One-time secret result'
                        : 'Reported action',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdministrationFormScreen.action(
                    action: action,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'No supported administrative operations were reported.',
              textAlign: TextAlign.center,
            ),
            if (message?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

IconData _sectionIcon(AdministrationSection section) => switch (section) {
      AdministrationSection.certificates => Icons.workspace_premium_outlined,
      AdministrationSection.identities => Icons.manage_accounts_outlined,
      AdministrationSection.apiAccess => Icons.key_outlined,
      AdministrationSection.system => Icons.system_update_alt,
      AdministrationSection.services => Icons.miscellaneous_services_outlined,
    };