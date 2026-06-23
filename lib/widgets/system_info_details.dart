import 'package:flutter/material.dart';

import '../models/system_info.dart';

class SystemInfoDetails extends StatelessWidget {
  const SystemInfoDetails({
    super.key,
    required this.info,
    required this.appVersion,
    required this.rebooting,
    required this.onReboot,
  });

  final SystemInfo info;
  final String appVersion;
  final bool rebooting;
  final VoidCallback onReboot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summary(context),
        const SizedBox(height: 18),
        const _SectionTitle(
          icon: Icons.new_releases_outlined,
          title: 'Firmware details',
        ),
        _DetailCard(rows: {
          'System type': info.systemType,
          'Router firmware': info.version,
          'pfSense Manager app': appVersion,
          'Architecture': info.architecture,
          'Git commit hash': info.gitCommit,
          'Package mirror': info.packageMirrorUrl,
          if (info.buildTime.isNotEmpty) 'Build time': info.buildTime,
        }),
        const SizedBox(height: 18),
        const _SectionTitle(
          icon: Icons.inventory_2_outlined,
          title: 'Repository information',
        ),
        for (final repository in info.repositories)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DetailCard(rows: {
              'Repository': repository.name,
              'Priority': repository.priority.toString(),
              'Status': repository.enabled ? 'Enabled' : 'Disabled',
              'URL': repository.url,
            }),
          ),
        const SizedBox(height: 8),
        const _SectionTitle(
          icon: Icons.monitor_heart_outlined,
          title: 'System status',
        ),
        _DetailCard(rows: {
          'Hostname': info.hostname,
          'Platform': info.platform,
          'Kernel version': info.kernelVersion,
          'System uptime': info.uptime,
          'PHP version': info.phpVersion,
          'Last update timestamp':
              info.lastUpdate ?? formatSystemTimestamp(info.fetchedAt),
          'Last refreshed': formatSystemTimestamp(info.fetchedAt),
        }),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: rebooting ? null : onReboot,
            icon: rebooting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.power_settings_new),
            label: Text(rebooting ? 'Rebooting…' : 'Reboot'),
          ),
        ),
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.router_outlined, color: scheme.primary, size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.hostname,
                    style: Theme.of(context).textTheme.titleLarge),
                Text('${info.systemType} ${info.version}'),
                Text(info.architecture,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.rows});

  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final entry in rows.entries) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(entry.key,
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: SelectableText(
                      entry.value,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              if (entry.key != rows.keys.last) const Divider(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

String formatSystemTimestamp(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
