import 'package:flutter/material.dart';

import '../services/background_alert_diagnostics.dart';

class BackgroundAlertHealthCard extends StatelessWidget {
  const BackgroundAlertHealthCard({
    super.key,
    required this.enabled,
    required this.diagnostics,
    required this.onRefresh,
    this.refreshing = false,
  });

  final bool enabled;
  final BackgroundAlertDiagnostics diagnostics;
  final VoidCallback onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final presentation = _presentation(scheme);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: presentation.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(presentation.icon, color: presentation.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Background alert health',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        presentation.status,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: presentation.color,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('background-alert-health-refresh'),
                  tooltip: 'Refresh background alert status',
                  onPressed: refreshing ? null : onRefresh,
                  icon: refreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              presentation.summary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const Divider(height: 24),
            _DiagnosticRow(
              label: 'Last attempted check',
              value: _formatTimestamp(context, diagnostics.lastAttempt),
            ),
            const SizedBox(height: 8),
            _DiagnosticRow(
              label: 'Last successful check',
              value: _formatTimestamp(context, diagnostics.lastSuccess),
            ),
            if (diagnostics.hasError) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: scheme.error.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      diagnostics.lastErrorCategory?.label ?? 'Failure',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      diagnostics.lastErrorMessage ??
                          'The last background check did not complete.',
                    ),
                    if (diagnostics.lastErrorAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Recorded ${_formatTimestamp(context, diagnostics.lastErrorAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _HealthPresentation _presentation(ColorScheme scheme) {
    if (!enabled) {
      return _HealthPresentation(
        status: 'Disabled',
        summary:
            'Periodic checks are not scheduled. Existing diagnostic history is retained.',
        icon: Icons.notifications_off_outlined,
        color: scheme.outline,
      );
    }
    if (diagnostics.lastAttemptSucceeded) {
      return const _HealthPresentation(
        status: 'Healthy',
        summary:
            'The latest scheduled check completed successfully and its network client was closed.',
        icon: Icons.check_circle_outline,
        color: Color(0xFF00A78E),
      );
    }
    if (diagnostics.hasError) {
      return _HealthPresentation(
        status: 'Attention required',
        summary:
            'The latest background operation failed. Review the category and remediation below.',
        icon: Icons.error_outline,
        color: scheme.error,
      );
    }
    return const _HealthPresentation(
      status: 'Waiting for first check',
      summary:
          'Android has not completed a recorded check yet. Scheduled work may be delayed by battery optimization.',
      icon: Icons.schedule_outlined,
      color: Colors.orangeAccent,
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.end,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _HealthPresentation {
  const _HealthPresentation({
    required this.status,
    required this.summary,
    required this.icon,
    required this.color,
  });

  final String status;
  final String summary;
  final IconData icon;
  final Color color;
}

String _formatTimestamp(BuildContext context, DateTime? value) {
  if (value == null) return 'Never';
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  final date = material.formatMediumDate(local);
  final time = material.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '$date, $time';
}
