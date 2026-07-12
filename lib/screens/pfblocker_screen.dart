import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../services/pfrest_feature_registry.dart';
import '../widgets/pfrest_feature_gate.dart';

class PfBlockerScreen extends StatefulWidget {
  const PfBlockerScreen({super.key});

  @override
  State<PfBlockerScreen> createState() => _PfBlockerScreenState();
}

class _PfBlockerScreenState extends State<PfBlockerScreen> {
  Map<String, dynamic>? _status;
  bool _loading = false;
  bool _updating = false;
  bool _toggling = false;
  String? _error;
  DateTime? _lastRefresh;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;

  PfRestFeatureRegistry _registry(PfSenseSessionProvider session) {
    return PfRestFeatureRegistry(
      activeProfileId: session.selectedProfile?.id,
      capabilities: session.capabilities,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;
    if (!changed) return;

    _requestGeneration++;
    _status = null;
    _error = null;
    _lastRefresh = null;
    _loadedSessionGeneration = session.sessionGeneration;
    _loadedProfileId = profileId;

    final decision = _registry(session).decision(PfRestFeature.pfBlockerStatus);
    if (session.connected && decision.canAttempt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    final decision = _registry(session).decision(PfRestFeature.pfBlockerStatus);
    if (!session.connected || session.service == null || !decision.canAttempt) {
      return;
    }

    final request = ++_requestGeneration;
    final generation = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await session.service!.getPfBlockerStatus();
      if (!mounted ||
          request != _requestGeneration ||
          generation != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _status = data;
        _lastRefresh = DateTime.now();
      });
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        setState(() {
          _error = pfRestFeatureRequestErrorMessage(
            PfRestFeature.pfBlockerStatus,
            error,
          );
        });
      }
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _updateLists(PfRestFeatureDecision decision) async {
    if (_updating || !decision.canAttempt) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;

    setState(() => _updating = true);
    try {
      await session.service!.updatePfBlockerLists();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('pfBlockerNG update requested.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pfRestFeatureRequestErrorMessage(
                PfRestFeature.pfBlockerUpdate,
                error,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _toggleEnabled(PfRestFeatureDecision decision) async {
    if (_toggling || _status == null || !decision.canAttempt) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;

    final currentlyEnabled = _status!['enable'] as bool? ?? true;
    if (currentlyEnabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pause pfBlockerNG?'),
          content: const Text(
            'Blocking will be paused until pfBlockerNG is enabled again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Pause blocking'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _toggling = true);
    try {
      await session.service!.setPfBlockerEnabled(!currentlyEnabled);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pfRestFeatureRequestErrorMessage(
                PfRestFeature.pfBlockerToggle,
                error,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final registry = _registry(session);
    final statusDecision = registry.decision(PfRestFeature.pfBlockerStatus);
    final updateDecision = registry.decision(PfRestFeature.pfBlockerUpdate);
    final toggleDecision = registry.decision(PfRestFeature.pfBlockerToggle);

    if (statusDecision.isUnsupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('pfBlockerNG')),
        body: PfRestFeatureBlockedView(
          decision: statusDecision,
          onRefresh: () => session.refreshCapabilities(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('pfBlockerNG'),
        actions: [
          IconButton(
            tooltip: 'Refresh capabilities',
            onPressed: session.connected
                ? () => session.refreshCapabilities()
                : null,
            icon: const Icon(Icons.extension_outlined),
          ),
          IconButton(
            tooltip: 'Refresh status',
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
            if (statusDecision.isUnknown) ...[
              PfRestFeatureNotice(
                decision: statusDecision,
                onRefresh: () => session.refreshCapabilities(),
              ),
              const SizedBox(height: 12),
            ],
            if (_loading) const LinearProgressIndicator(),
            if (!session.connected)
              const _InfoCard(
                icon: Icons.cloud_off_outlined,
                title: 'Disconnected',
                subtitle: 'Connect to a firewall before loading pfBlockerNG.',
              )
            else if (_error != null)
              _InfoCard(
                icon: Icons.error_outline,
                title: 'pfBlockerNG request failed',
                subtitle: _error!,
              )
            else if (_status != null) ...[
              _StatusHeader(status: _status!),
              const SizedBox(height: 16),
              _StatsGrid(status: _status!),
              const SizedBox(height: 16),
              _CapabilityAction(
                decision: updateDecision,
                label: _updating ? 'Updating…' : 'Update lists',
                icon: Icons.sync,
                busy: _updating,
                onPressed: () => _updateLists(updateDecision),
              ),
              const SizedBox(height: 8),
              _CapabilityAction(
                decision: toggleDecision,
                label: _toggling
                    ? 'Applying…'
                    : ((_status!['enable'] as bool? ?? true)
                        ? 'Pause blocking'
                        : 'Enable blocking'),
                icon: Icons.power_settings_new,
                busy: _toggling,
                onPressed: () => _toggleEnabled(toggleDecision),
              ),
              if (_lastRefresh != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Last updated ${_formatTime(_lastRefresh!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ] else if (!_loading)
              const _InfoCard(
                icon: Icons.shield_outlined,
                title: 'pfBlockerNG',
                subtitle: 'Pull to refresh or use the refresh button.',
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _CapabilityAction extends StatelessWidget {
  const _CapabilityAction({
    required this.decision,
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final PfRestFeatureDecision decision;
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: decision.canAttempt && !busy,
        leading: busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        title: Text(label),
        subtitle: decision.isAvailable
            ? Text(decision.contract.description)
            : Text(decision.message),
        trailing: decision.isUnsupported
            ? const Icon(Icons.extension_off_outlined)
            : const Icon(Icons.chevron_right),
        onTap: decision.canAttempt && !busy ? onPressed : null,
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.status});

  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final enabled = status['enable'] as bool? ?? true;
    final color = enabled
        ? const Color(0xFF00C2A8)
        : Theme.of(context).colorScheme.error;
    return Card(
      child: ListTile(
        leading: Icon(
          enabled ? Icons.security : Icons.security_outlined,
          color: color,
        ),
        title: Text(enabled ? 'pfBlockerNG active' : 'pfBlockerNG paused'),
        subtitle: Text(status['version']?.toString() ?? 'Version not reported'),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.status});

  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final dnsbl = status['dnsbl'] as Map<String, dynamic>? ?? const {};
    final ip = status['ip'] as Map<String, dynamic>? ?? const {};
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _StatCard(
          label: 'DNSBL blocked',
          value: _format(dnsbl['blocked'] ?? status['dnsbl_blocked']),
          icon: Icons.dns_outlined,
        ),
        _StatCard(
          label: 'DNSBL allowed',
          value: _format(dnsbl['allowed'] ?? status['dnsbl_allowed']),
          icon: Icons.check_circle_outline,
        ),
        _StatCard(
          label: 'IP blocked',
          value: _format(ip['blocked'] ?? status['ip_blocked']),
          icon: Icons.block_outlined,
        ),
        _StatCard(
          label: 'Lists loaded',
          value: _format(status['lists_loaded'] ?? status['list_count']),
          icon: Icons.list_alt_outlined,
        ),
      ],
    );
  }

  String _format(dynamic value) => value?.toString() ?? '--';
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
