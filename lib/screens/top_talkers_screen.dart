import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/top_talker.dart';
import '../providers/session_provider.dart';
import '../widgets/state_message.dart';

class TopTalkersScreen extends StatefulWidget {
  const TopTalkersScreen({super.key});

  @override
  State<TopTalkersScreen> createState() => _TopTalkersScreenState();
}

class _TopTalkersScreenState extends State<TopTalkersScreen> {
  List<TopTalker> _talkers = [];
  Object? _error;
  bool _loading = false;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastRefresh;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;
    if (changed) {
      _requestGeneration++;
      _talkers = [];
      _error = null;
      _lastRefresh = null;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      _timer?.cancel();
      _timer = null;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(showSpinner: true);
        });
      }
    } else if (_talkers.isEmpty && !_loading && session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(showSpinner: true);
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      final disconnected = AppStrings.of(context).t('disconnected');
      setState(() {
        _talkers = [];
        _error = disconnected;
      });
      return;
    }
    final req = ++_requestGeneration;
    final gen = session.sessionGeneration;
    final pid = session.selectedProfile?.id;
    setState(() {
      _loading = true;
      if (showSpinner) _error = null;
    });
    try {
      final data = await session.service!.getTopTalkers();
      if (!mounted ||
          req != _requestGeneration ||
          gen != session.sessionGeneration ||
          pid != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _talkers = data;
        _error = null;
        _lastRefresh = DateTime.now();
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) _load();
      });
    } catch (e) {
      if (mounted && req == _requestGeneration) setState(() => _error = e);
    } finally {
      if (mounted && req == _requestGeneration) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final session = context.watch<PfSenseSessionProvider>();
    final maxRate = _talkers.isEmpty
        ? 1.0
        : _talkers
            .map((talker) => talker.bytesPerSecond)
            .reduce((current, next) => current > next ? current : next);

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _SummaryCard(count: _talkers.length, lastRefresh: _lastRefresh),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            StateMessage(
              icon: Icons.cloud_off_outlined,
              text: strings.t('disconnectedConnectFirst'),
            )
          else if (_error != null)
            StateMessage(
              icon: Icons.error_outline,
              text: _error.toString(),
              action: TextButton(
                onPressed: () => _load(showSpinner: true),
                child: Text(strings.t('retry')),
              ),
            )
          else if (_talkers.isEmpty && !_loading)
            StateMessage(
              icon: Icons.bar_chart_outlined,
              text: strings.t('noActiveStates'),
              details: strings.t('trafficWillAppear'),
            )
          else
            for (final talker in _talkers)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TalkerTile(talker: talker, maxRate: maxRate),
              ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count, required this.lastRefresh});
  final int count;
  final DateTime? lastRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bar_chart_outlined, color: scheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.t('topTalkers'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    lastRefresh == null
                        ? strings.t('topTalkersSubtitle')
                        : strings.f(
                            'topTalkersUpdated',
                            {'time': _clock(lastRefresh!)},
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              '$count',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}:'
        '${l.second.toString().padLeft(2, '0')}';
  }
}

class _TalkerTile extends StatelessWidget {
  const _TalkerTile({required this.talker, required this.maxRate});
  final TopTalker talker;
  final double maxRate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = maxRate > 0
        ? (talker.bytesPerSecond / maxRate).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices_other_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    talker.displayName,
                    style: Theme.of(context).textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatRate(talker.bytesPerSecond),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            if (talker.hostname != null && talker.hostname!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                talker.ipAddress,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.storage_outlined, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Total ${_formatBytes(talker.bytes)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.link_outlined, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  talker.connections == 1
                      ? AppStrings.of(context).t('connectionOne')
                      : AppStrings.of(context).f(
                          'connectionsMany',
                          {'count': talker.connections.toString()},
                        ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (talker.interface.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.cable_outlined, size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(talker.interface, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatRate(double bytesPerSecond) {
    return '${_formatBytes(bytesPerSecond.round())}/s';
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1073741824) return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}
