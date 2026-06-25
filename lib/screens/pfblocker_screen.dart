import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/session_provider.dart';

class PfBlockerScreen extends StatefulWidget {
  const PfBlockerScreen({super.key});

  @override
  State<PfBlockerScreen> createState() => _PfBlockerScreenState();
}

class _PfBlockerScreenState extends State<PfBlockerScreen> {
  Map<String, dynamic>? _status;
  bool _available = true;
  bool _loading = false;
  bool _updating = false;
  bool _toggling = false;
  Object? _error;
  DateTime? _lastRefresh;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;
    if (changed) {
      _requestGeneration++;
      _status = null;
      _error = null;
      _lastRefresh = null;
      _available = true;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      if (session.connected) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;
    final request = ++_requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await session.service!.getPfBlockerStatus();
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _status = data;
        _available = data != null;
        _lastRefresh = DateTime.now();
      });
    } catch (e) {
      if (mounted && request == _requestGeneration) setState(() => _error = e);
    } finally {
      if (mounted && request == _requestGeneration) setState(() => _loading = false);
    }
  }

  Future<void> _update() async {
    if (_updating) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;
    final updateMsg = AppStrings.of(context).t('pfblockerUpdateTriggered');
    setState(() => _updating = true);
    try {
      await session.service!.updatePfBlockerLists();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(updateMsg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _toggleEnabled() async {
    if (_toggling || _status == null) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;
    final currentlyEnabled = _status!['enable'] as bool? ?? true;
    if (!currentlyEnabled) {
      setState(() => _toggling = true);
      try {
        await session.service!.setPfBlockerEnabled(true);
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
        }
      } finally {
        if (mounted) setState(() => _toggling = false);
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final s = AppStrings.of(ctx);
        return AlertDialog(
          title: Text(s.t('pausePfblocker')),
          content: Text(s.t('pausePfblockerBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('pauseBlocking')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _toggling = true);
    try {
      await session.service!.setPfBlockerEnabled(false);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final scheme = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('pfBlockerNG'),
        actions: [
          if (_lastRefresh != null)
            IconButton(
              tooltip: strings.t('refresh'),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (!session.connected)
              _InfoCard(
                icon: Icons.cloud_off_outlined,
                color: scheme.error,
                title: strings.t('disconnected'),
                subtitle: strings.t('pfblockerConnectFirst'),
              )
            else if (!_available)
              _InfoCard(
                icon: Icons.extension_off_outlined,
                color: scheme.tertiary,
                title: strings.t('pfblockerNotAvailable'),
                subtitle: strings.t('pfblockerNotAvailableDetail'),
              )
            else if (_error != null)
              _InfoCard(
                icon: Icons.error_outline,
                color: scheme.error,
                title: strings.t('pfblockerLoadFailed'),
                subtitle: _error.toString(),
              )
            else if (_status != null) ...[
              _StatusHeader(status: _status!),
              const SizedBox(height: 16),
              _StatsGrid(status: _status!),
              const SizedBox(height: 20),
              _ActionRow(
                status: _status!,
                loading: _updating || _toggling,
                onUpdate: _update,
                onToggle: _toggleEnabled,
              ),
              const SizedBox(height: 16),
              if (_lastRefresh != null)
                Text(
                  strings.f('lastUpdated', {'time': _formatTime(_lastRefresh!)}),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ] else if (!_loading)
              _InfoCard(
                icon: Icons.shield_outlined,
                color: scheme.primary,
                title: 'pfBlockerNG',
                subtitle: strings.t('pfblockerLoadHint'),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.status});
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = status['enable'] as bool? ?? true;
    final color = enabled ? const Color(0xFF00C2A8) : scheme.error;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(enabled ? Icons.security : Icons.security_outlined, color: color, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.of(context).t(enabled ? 'pfblockerActive' : 'pfblockerPaused'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
                Text(
                  status['version']?.toString() ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.status});
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final dnsbl = status['dnsbl'] as Map<String, dynamic>? ?? {};
    final ip = status['ip'] as Map<String, dynamic>? ?? {};

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _StatCard(
          label: AppStrings.of(context).t('dnsblBlocked'),
          value: _fmt(dnsbl['blocked'] ?? status['dnsbl_blocked']),
          icon: Icons.dns_outlined,
          color: const Color(0xFFE53935),
        ),
        _StatCard(
          label: AppStrings.of(context).t('dnsblAllowed'),
          value: _fmt(dnsbl['allowed'] ?? status['dnsbl_allowed']),
          icon: Icons.check_circle_outline,
          color: const Color(0xFF00C2A8),
        ),
        _StatCard(
          label: AppStrings.of(context).t('ipBlocked'),
          value: _fmt(ip['blocked'] ?? status['ip_blocked']),
          icon: Icons.block_outlined,
          color: const Color(0xFFFF6F00),
        ),
        _StatCard(
          label: AppStrings.of(context).t('listsLoaded'),
          value: _fmt(status['lists_loaded'] ?? status['list_count']),
          icon: Icons.list_alt_outlined,
          color: const Color(0xFF7B61FF),
        ),
      ],
    );
  }

  String _fmt(dynamic value) {
    if (value == null) return '--';
    final n = int.tryParse(value.toString());
    if (n == null) return value.toString();
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
    return n.toString();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800, color: color),
          ),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.status,
    required this.loading,
    required this.onUpdate,
    required this.onToggle,
  });
  final Map<String, dynamic> status;
  final bool loading;
  final VoidCallback onUpdate;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final enabled = status['enable'] as bool? ?? true;
    return Column(
      children: [
        FilledButton.icon(
          onPressed: loading ? null : onUpdate,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(AppStrings.of(context).t('updateBlocklists')),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: loading ? null : onToggle,
          icon: Icon(enabled ? Icons.pause_circle_outline : Icons.play_circle_outline),
          label: Text(AppStrings.of(context).t(enabled ? 'pauseBlocking' : 'resumeBlocking')),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: enabled ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
