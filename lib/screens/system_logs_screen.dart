import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/system_log_entry.dart';
import '../providers/session_provider.dart';

/// A pfSense system log source surfaced as a tab.
class _LogSource {
  const _LogSource(this.label, this.logType, this.icon);
  final String label;
  final String logType;
  final IconData icon;
}

const _logSources = <_LogSource>[
  _LogSource('System', 'system', Icons.dns_outlined),
  _LogSource('DHCP', 'dhcpd', Icons.router_outlined),
  _LogSource('DNS', 'resolver', Icons.travel_explore_outlined),
  _LogSource('Gateway', 'gateways', Icons.swap_horiz_outlined),
];

class SystemLogsScreen extends StatefulWidget {
  const SystemLogsScreen({super.key});

  @override
  State<SystemLogsScreen> createState() => _SystemLogsScreenState();
}

class _SystemLogsScreenState extends State<SystemLogsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _logSources.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System logs'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            for (final source in _logSources)
              Tab(icon: Icon(source.icon), text: source.label),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final source in _logSources) _LogTab(source: source),
        ],
      ),
    );
  }
}

class _LogTab extends StatefulWidget {
  const _LogTab({required this.source});

  final _LogSource source;

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _search = TextEditingController();
  List<SystemLogEntry> _entries = [];
  bool _loading = false;
  bool _autoRefresh = false;
  bool _appActive = true;
  Object? _error;
  Timer? _timer;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastSuccessfulRefresh;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_onSearchChanged);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      final session = context.read<PfSenseSessionProvider>();
      if (_autoRefresh && _appActive && session.connected && !_loading) {
        _load();
      }
    });
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;

    if (changed) {
      _requestGeneration++;
      _entries = [];
      _error = null;
      _lastSuccessfulRefresh = null;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(showSpinner: true);
        });
      }
    } else if (_entries.isEmpty && !_loading && session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(showSpinner: true);
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _lastSuccessfulRefresh = null;
        _error = 'Disconnected';
      });
      return;
    }

    final request = ++_requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    setState(() {
      _loading = true;
      if (showSpinner) _error = null;
    });

    try {
      final entries = await session.service!.getSystemLog(widget.source.logType);
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _entries = entries;
        _error = null;
        _lastSuccessfulRefresh = DateTime.now();
      });
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      setState(() => _error = error);
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _copyAll(List<SystemLogEntry> visible) async {
    if (visible.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: visible.map((e) => e.raw).join('\n')),
    );
    HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${visible.length} log lines copied'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = context.watch<PfSenseSessionProvider>();
    final query = _search.text.trim().toLowerCase();
    final visible = _entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.raw.toLowerCase().contains(query);
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Filter ${widget.source.label.toLowerCase()} log',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _search.clear(),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoRefresh,
                  onChanged: (value) => setState(() => _autoRefresh = value),
                  title: const Text('Auto refresh'),
                  secondary: const Icon(Icons.autorenew),
                ),
              ),
              IconButton(
                tooltip: 'Copy visible lines',
                onPressed: visible.isEmpty ? null : () => _copyAll(visible),
                icon: const Icon(Icons.copy_all_outlined),
              ),
            ],
          ),
          if (_lastSuccessfulRefresh != null)
            Text(
              'Last updated ${_formatTime(_lastSuccessfulRefresh!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            _message(Icons.cloud_off_outlined, 'Disconnected')
          else if (_error != null)
            _message(Icons.error_outline, _error.toString())
          else if (!_loading && visible.isEmpty)
            _message(
              Icons.article_outlined,
              query.isEmpty
                  ? 'No ${widget.source.label.toLowerCase()} log entries returned.'
                  : 'No lines match "$query".',
            ),
          if (session.connected)
            for (final entry in visible) _LogTile(entry: entry),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  Widget _message(IconData icon, String text) =>
      Card(child: ListTile(leading: Icon(icon), title: Text(text)));
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final SystemLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.timeLabel.isNotEmpty || entry.process.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    if (entry.timeLabel.isNotEmpty) ...[
                      Icon(Icons.schedule, size: 13, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        entry.timeLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    if (entry.process.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.process,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            SelectableText(
              entry.message.isEmpty ? entry.raw : entry.message,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
