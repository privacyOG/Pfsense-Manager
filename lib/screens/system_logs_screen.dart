import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/system_log_entry.dart';
import '../models/system_log_source.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';

class SystemLogsScreen extends StatefulWidget {
  const SystemLogsScreen({super.key});

  @override
  State<SystemLogsScreen> createState() => _SystemLogsScreenState();
}

class _SystemLogsScreenState extends State<SystemLogsScreen> {
  List<SystemLogSource> _sources = const [];
  Object? _sourceError;
  bool _loadingSources = false;
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
    if (!changed) return;

    _requestGeneration++;
    _loadedSessionGeneration = session.sessionGeneration;
    _loadedProfileId = profileId;
    _sources = const [];
    _sourceError = null;
    _loadingSources = session.connected;

    if (session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _discoverSources();
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    super.dispose();
  }

  Future<void> _discoverSources() async {
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      setState(() {
        _sources = const [];
        _sourceError = 'Disconnected';
        _loadingSources = false;
      });
      return;
    }

    final request = ++_requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    setState(() {
      _loadingSources = true;
      _sourceError = null;
    });

    try {
      final sources = await session.service!.getSystemLogSources();
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _sources = sources;
        _sourceError = null;
      });
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      setState(() {
        _sources = const [];
        _sourceError = systemLogDiscoveryErrorMessage(error);
      });
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loadingSources = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    if (!session.connected) {
      return _statusScaffold(
        icon: Icons.cloud_off_outlined,
        message: 'Disconnected',
      );
    }
    if (_loadingSources) {
      return _statusScaffold(
        icon: Icons.manage_search_outlined,
        message: 'Reading available log sources from pfREST…',
        loading: true,
      );
    }
    if (_sourceError != null) {
      return _statusScaffold(
        icon: Icons.error_outline,
        message: _sourceError.toString(),
        showRefresh: true,
      );
    }
    if (_sources.isEmpty) {
      return _statusScaffold(
        icon: Icons.article_outlined,
        message:
            'The installed pfREST schema did not report any supported system log endpoints.',
        showRefresh: true,
      );
    }

    final sourceKey = _sources.map((source) => source.path).join('|');
    return DefaultTabController(
      key: ValueKey('${session.selectedProfile?.id}:$sourceKey'),
      length: _sources.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('System logs'),
          actions: [
            IconButton(
              tooltip: 'Refresh available log sources',
              onPressed: _discoverSources,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final source in _sources)
                Tab(icon: Icon(source.icon), text: source.label),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final source in _sources)
              _LogTab(
                key: ValueKey(source.path),
                source: source,
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusScaffold({
    required IconData icon,
    required String message,
    bool loading = false,
    bool showRefresh = false,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System logs'),
        actions: [
          if (showRefresh)
            IconButton(
              tooltip: 'Refresh available log sources',
              onPressed: _discoverSources,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 3),
          Card(
            child: ListTile(
              leading: Icon(icon),
              title: Text(message),
              subtitle: showRefresh
                  ? const Text(
                      'Only GET log endpoints reported by the connected OpenAPI schema are displayed.',
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogTab extends StatefulWidget {
  const _LogTab({super.key, required this.source});

  final SystemLogSource source;

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
      final entries = await session.service!.getSystemLog(widget.source);
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
      setState(() {
        _entries = [];
        _error = systemLogErrorMessage(widget.source, error);
      });
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _copyAll(List<SystemLogEntry> visible) async {
    if (visible.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: visible.map((entry) => entry.raw).join('\n')),
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
          if (widget.source.isCustomExtension)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.extension_outlined),
                  title: const Text('Custom pfREST extension'),
                  subtitle: Text(
                    '${widget.source.label} is displayed because this installation reported ${widget.source.path}.',
                  ),
                ),
              ),
            ),
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
            _message(Icons.info_outline, _error.toString())
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

String systemLogDiscoveryErrorMessage(Object error) {
  if (error is ApiException) {
    if (error.isAuthenticationError) {
      return 'Authentication failed while reading available log sources (401). ${error.message}';
    }
    if (error.isPermissionError) {
      return 'Permission denied while reading the pfREST OpenAPI schema (403). Grant read access to $systemLogSchemaPath. ${error.message}';
    }
    if (error.isEndpointUnavailable) {
      return 'This pfREST installation does not expose the OpenAPI schema at $systemLogSchemaPath.';
    }
  }
  return error.toString();
}

String systemLogErrorMessage(SystemLogSource source, Object error) {
  if (error is ApiException) {
    if (error.isAuthenticationError) {
      return 'Authentication failed while reading ${source.label} logs (401). ${error.message}';
    }
    if (error.isPermissionError) {
      return 'Permission denied for ${source.label} logs (403). The endpoint is supported, but the saved credential cannot read it. ${error.message}';
    }
    if (error.isEndpointUnavailable) {
      return '${source.label} was reported by the OpenAPI schema but is no longer available. Refresh the log sources.';
    }
  }
  return error.toString();
}

bool isUnsupportedSystemLogError(Object error) {
  return error is ApiException && error.isEndpointUnavailable;
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
                      Icon(
                        Icons.schedule,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
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
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
