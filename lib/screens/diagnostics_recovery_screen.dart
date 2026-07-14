import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/diagnostics_recovery.dart';
import '../providers/session_provider.dart';
import '../widgets/slide_to_confirm.dart';

enum _DiagnosticsTool { arp, tables, history, console }

class DiagnosticsRecoveryScreen extends StatelessWidget {
  const DiagnosticsRecoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.diagnosticsRecoveryService;
    final capabilities = service?.capabilities;
    final tools = <_DiagnosticsTool>[
      if (capabilities?.canReadArp == true) _DiagnosticsTool.arp,
      if (capabilities?.canReadTables == true) _DiagnosticsTool.tables,
      if (capabilities?.canReadHistory == true) _DiagnosticsTool.history,
      if (capabilities?.canRunCommands == true) _DiagnosticsTool.console,
    ];

    if (!session.connected || service == null) {
      return const _StatusScaffold(
        icon: Icons.cloud_off_outlined,
        message: 'Connect to a firewall to use diagnostics and recovery tools.',
      );
    }
    if (tools.isEmpty) {
      return const _StatusScaffold(
        icon: Icons.build_circle_outlined,
        message:
            'The connected pfREST OpenAPI schema did not report stock ARP, pf-table, configuration-history, or command-prompt operations.',
      );
    }

    return DefaultTabController(
      length: tools.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Diagnostics & recovery'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final tool in tools)
                Tab(icon: Icon(_icon(tool)), text: _label(tool)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final tool in tools)
              switch (tool) {
                _DiagnosticsTool.arp => const _ArpTab(),
                _DiagnosticsTool.tables => const _PfTablesTab(),
                _DiagnosticsTool.history => const _HistoryTab(),
                _DiagnosticsTool.console => const _CommandConsoleTab(),
              },
          ],
        ),
      ),
    );
  }
}

class _ArpTab extends StatefulWidget {
  const _ArpTab();

  @override
  State<_ArpTab> createState() => _ArpTabState();
}

class _ArpTabState extends State<_ArpTab> {
  List<ArpTableEntry> _entries = const [];
  Object? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.diagnosticsRecoveryService;
    if (!session.connected || service == null) return;
    final request = ++_request;
    final generation = session.sessionGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await service.listArpEntries();
      if (!mounted ||
          request != _request ||
          generation != session.sessionGeneration) {
        return;
      }
      setState(() => _entries = entries);
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _delete(ArpTableEntry entry) async {
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Delete ARP entry?',
      body:
          'This removes ${entry.ipAddress.isEmpty ? entry.displayName : entry.ipAddress} from the live ARP table. Connectivity may be briefly interrupted while the neighbor is rediscovered.',
      slideLabel: 'Slide to delete entry',
      icon: Icons.delete_outline,
    );
    if (confirmed != true || !mounted) return;
    try {
      await context
          .read<PfSenseSessionProvider>()
          .diagnosticsRecoveryService!
          .deleteArpEntry(entry);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) _message(error.toString());
    }
  }

  Future<void> _clear() async {
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Clear the entire ARP table?',
      body:
          'Every dynamic ARP entry will be removed. Active devices must be rediscovered and network traffic may pause briefly.',
      slideLabel: 'Slide to clear ARP table',
      icon: Icons.delete_sweep_outlined,
    );
    if (confirmed != true || !mounted) return;
    try {
      await context
          .read<PfSenseSessionProvider>()
          .diagnosticsRecoveryService!
          .clearArpTable();
      if (mounted) await _load();
    } catch (error) {
      if (mounted) _message(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = context
        .watch<PfSenseSessionProvider>()
        .diagnosticsRecoveryService!
        .capabilities;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.device_hub_outlined),
              title: const Text('ARP table'),
              subtitle: Text(
                capabilities.canMutateArp
                    ? 'Live entries reported by stock pfREST. Deletion changes runtime state immediately.'
                    : 'View only — the connected profile does not expose ARP deletion.',
              ),
              trailing: capabilities.arpClear == null
                  ? null
                  : IconButton(
                      tooltip: 'Clear ARP table',
                      onPressed: _loading ? null : _clear,
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            _ErrorCard(error: _error!, onRetry: _load)
          else if (!_loading && _entries.isEmpty)
            const _EmptyCard(message: 'No ARP entries were returned.'),
          for (final entry in _entries)
            Card(
              child: ListTile(
                leading: Icon(
                  entry.permanent ? Icons.push_pin_outlined : Icons.lan_outlined,
                ),
                title: Text(entry.displayName),
                subtitle: Text(
                  [
                    entry.ipAddress,
                    entry.macAddress,
                    entry.interfaceName,
                    entry.type,
                    if (entry.expires.isNotEmpty) 'Expires ${entry.expires}',
                  ].where((value) => value.isNotEmpty).join(' • '),
                ),
                trailing: capabilities.arpDeleteEntry == null || entry.id == null
                    ? null
                    : IconButton(
                        tooltip: 'Delete this ARP entry',
                        onPressed: () => _delete(entry),
                        icon: const Icon(Icons.delete_outline),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PfTablesTab extends StatefulWidget {
  const _PfTablesTab();

  @override
  State<_PfTablesTab> createState() => _PfTablesTabState();
}

class _PfTablesTabState extends State<_PfTablesTab> {
  List<PfTableSnapshot> _tables = const [];
  Object? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.diagnosticsRecoveryService;
    if (!session.connected || service == null) return;
    final request = ++_request;
    final generation = session.sessionGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tables = await service.listPfTables();
      if (!mounted ||
          request != _request ||
          generation != session.sessionGeneration) {
        return;
      }
      setState(() => _tables = tables);
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _flush(PfTableSnapshot table) async {
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Flush ${table.name}?',
      body:
          'All ${table.entries.length} entries will be removed from this live pf table. Firewall behavior may change immediately, but the table definition itself is not deleted.',
      slideLabel: 'Slide to flush table',
      icon: Icons.delete_sweep_outlined,
    );
    if (confirmed != true || !mounted) return;
    try {
      await context
          .read<PfSenseSessionProvider>()
          .diagnosticsRecoveryService!
          .flushPfTable(table);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) _message(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = context
        .watch<PfSenseSessionProvider>()
        .diagnosticsRecoveryService!
        .capabilities;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.table_rows_outlined),
              title: const Text('pf tables'),
              subtitle: Text(
                capabilities.canFlushTables
                    ? 'Expand a table to inspect its live contents. Flush removes entries only.'
                    : 'View only — table flushing is not permitted.',
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            _ErrorCard(error: _error!, onRetry: _load)
          else if (!_loading && _tables.isEmpty)
            const _EmptyCard(message: 'No pf tables were returned.'),
          for (final table in _tables)
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: Text(table.name.isEmpty ? 'Unnamed table' : table.name),
                subtitle: Text(
                  '${table.entries.length} entr${table.entries.length == 1 ? 'y' : 'ies'}',
                ),
                trailing: capabilities.tableFlush == null || table.name.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Flush table entries',
                        onPressed: () => _flush(table),
                        icon: const Icon(Icons.delete_sweep_outlined),
                      ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (table.entries.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('This table is empty.'),
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(table.entries.join('\n')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HistoryTab extends StatefulWidget {
  const _HistoryTab();

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  List<ConfigHistoryRevision> _revisions = const [];
  Object? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.diagnosticsRecoveryService;
    if (!session.connected || service == null) return;
    final request = ++_request;
    final generation = session.sessionGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final revisions = await service.listConfigRevisions();
      if (!mounted ||
          request != _request ||
          generation != session.sessionGeneration) {
        return;
      }
      setState(() => _revisions = revisions);
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _delete(ConfigHistoryRevision revision) async {
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Delete this backup revision?',
      body:
          'The configuration-history record and its backup XML file will be permanently deleted. This does not change the active configuration.',
      slideLabel: 'Slide to delete revision',
      icon: Icons.delete_forever_outlined,
    );
    if (confirmed != true || !mounted) return;
    try {
      await context
          .read<PfSenseSessionProvider>()
          .diagnosticsRecoveryService!
          .deleteConfigRevision(revision);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) _message(error.toString());
    }
  }

  Future<void> _rollback(ConfigHistoryRevision revision) async {
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Restore this configuration?',
      body:
          'The firewall configuration will be rolled back to ${revision.displayName}. Network access, routing, authentication, and this app connection may change or disconnect immediately.',
      slideLabel: 'Slide to restore revision',
      icon: Icons.restore_outlined,
    );
    if (confirmed != true || !mounted) return;
    try {
      await context
          .read<PfSenseSessionProvider>()
          .diagnosticsRecoveryService!
          .rollbackConfigRevision(revision);
      if (mounted) {
        _message(
          'Rollback request accepted. Reconnect if the firewall address or credentials changed.',
        );
      }
    } catch (error) {
      if (mounted) _message(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = context
        .watch<PfSenseSessionProvider>()
        .diagnosticsRecoveryService!
        .capabilities;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('Configuration history'),
              subtitle: Text(
                capabilities.canRollback
                    ? 'Revision restore is available because the connected schema reports a rollback operation.'
                    : 'Stock history supports viewing and permission-gated deletion. No rollback operation was reported by this firewall.',
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            _ErrorCard(error: _error!, onRetry: _load)
          else if (!_loading && _revisions.isEmpty)
            const _EmptyCard(message: 'No configuration revisions were returned.'),
          for (final revision in _revisions)
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.restore_page_outlined),
                title: Text(revision.displayName),
                subtitle: Text(
                  [
                    if (revision.timestamp != null)
                      revision.timestamp!.toString(),
                    if (revision.version.isNotEmpty) revision.version,
                    if (revision.filesize > 0)
                      '${revision.filesize} bytes',
                  ].join(' • '),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(revision.raw),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (capabilities.canRollback)
                        FilledButton.tonalIcon(
                          onPressed: () => _rollback(revision),
                          icon: const Icon(Icons.restore_outlined),
                          label: const Text('Restore'),
                        ),
                      if (capabilities.canDeleteRevision && revision.id != null)
                        OutlinedButton.icon(
                          onPressed: () => _delete(revision),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete backup'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CommandConsoleTab extends StatefulWidget {
  const _CommandConsoleTab();

  @override
  State<_CommandConsoleTab> createState() => _CommandConsoleTabState();
}

class _CommandConsoleTabState extends State<_CommandConsoleTab> {
  final _command = TextEditingController();
  CommandPromptResult? _result;
  Object? _error;
  bool _unlocked = false;
  bool _running = false;

  @override
  void dispose() {
    _command.clear();
    _command.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running || !_unlocked) return;
    final text = _command.text.trim();
    if (text.isEmpty) {
      _message('Enter a command first.');
      return;
    }
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Run shell command?',
      body:
          'This command executes with the privileges granted to the pfREST command-prompt endpoint. It can change or destroy the firewall configuration, expose sensitive data, interrupt networking, or make the system unavailable. Command history is not retained and returned output is credential-redacted before display.',
      slideLabel: 'Slide to run command',
      icon: Icons.terminal_outlined,
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await context
          .read<PfSenseSessionProvider>()
          .diagnosticsRecoveryService!
          .runCommand(text, explicitlyUnlocked: _unlocked);
      _command.clear();
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.warning_amber_outlined),
                title: Text('Advanced command prompt'),
                subtitle: Text(
                  'This feature is separately permissioned by pfREST and locked locally for every app session. Use only commands you understand completely.',
                ),
              ),
              SwitchListTile(
                value: _unlocked,
                onChanged: _running
                    ? null
                    : (value) => setState(() {
                          _unlocked = value;
                          _command.clear();
                          _result = null;
                          _error = null;
                        }),
                title: const Text('Enable command prompt for this session'),
                secondary: Icon(
                  _unlocked ? Icons.lock_open_outlined : Icons.lock_outline,
                ),
              ),
            ],
          ),
        ),
        TextField(
          controller: _command,
          enabled: _unlocked && !_running,
          minLines: 2,
          maxLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Shell command',
            helperText: 'Commands are sent once and are not added to app history.',
            prefixIcon: Icon(Icons.terminal_outlined),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _unlocked && !_running ? _run : null,
          icon: _running
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Text(_running ? 'Running…' : 'Review and run'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(error: _error!, onRetry: () => setState(() => _error = null)),
        ],
        if (_result != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _result!.succeeded
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _result!.resultCode == null
                            ? 'Command result'
                            : 'Exit code ${_result!.resultCode}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  SelectableText(
                    _result!.output.isEmpty
                        ? '(No output returned)'
                        : _result!.output,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StatusScaffold extends StatelessWidget {
  const _StatusScaffold({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics & recovery')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(error.toString()),
        trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.inbox_outlined),
        title: Text(message),
      ),
    );
  }
}

String _label(_DiagnosticsTool tool) => switch (tool) {
      _DiagnosticsTool.arp => 'ARP',
      _DiagnosticsTool.tables => 'pf tables',
      _DiagnosticsTool.history => 'History',
      _DiagnosticsTool.console => 'Console',
    };

IconData _icon(_DiagnosticsTool tool) => switch (tool) {
      _DiagnosticsTool.arp => Icons.device_hub_outlined,
      _DiagnosticsTool.tables => Icons.table_chart_outlined,
      _DiagnosticsTool.history => Icons.history_outlined,
      _DiagnosticsTool.console => Icons.terminal_outlined,
    };