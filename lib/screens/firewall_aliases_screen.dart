import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/firewall_alias.dart';
import '../providers/session_provider.dart';
import '../services/pfrest_feature_registry.dart';
import '../utils/api_exception.dart';
import '../widgets/pfrest_feature_gate.dart';
import '../widgets/slide_to_confirm.dart';
import 'firewall_alias_form_screen.dart';

class FirewallAliasesScreen extends StatefulWidget {
  const FirewallAliasesScreen({super.key});

  @override
  State<FirewallAliasesScreen> createState() => _FirewallAliasesScreenState();
}

class _FirewallAliasesScreenState extends State<FirewallAliasesScreen> {
  final _search = TextEditingController();
  List<FirewallAlias> _aliases = const [];
  String _typeFilter = 'all';
  Object? _error;
  bool _loading = false;
  bool _actionBusy = false;
  bool _writePermissionDenied = false;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastSuccessfulRefresh;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refreshView);
  }

  void _refreshView() {
    if (mounted) setState(() {});
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
    _aliases = const [];
    _typeFilter = 'all';
    _error = null;
    _lastSuccessfulRefresh = null;
    _writePermissionDenied = false;
    _loadedSessionGeneration = session.sessionGeneration;
    _loadedProfileId = profileId;
    if (session.connected && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(showSpinner: true);
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _search
      ..removeListener(_refreshView)
      ..dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.firewallAliasService;
    if (!session.connected || service == null) {
      if (!mounted) return;
      setState(() {
        _aliases = const [];
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
      final aliases = await service.list();
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _aliases = aliases;
        _error = null;
        _lastSuccessfulRefresh = DateTime.now();
      });
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      setState(() => _error = _requestError(
            PfRestFeature.firewallAliasesRead,
            error,
          ));
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _markReadOnly() {
    if (!mounted || _writePermissionDenied) return;
    setState(() => _writePermissionDenied = true);
  }

  Future<void> _openForm([FirewallAlias? alias]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FirewallAliasFormScreen(
          alias: alias,
          existingAliases: _aliases,
          onPermissionDenied: _markReadOnly,
        ),
      ),
    );
    if (changed == true) await _load(showSpinner: true);
  }

  Future<void> _delete(
    FirewallAlias alias,
    PfRestFeatureDecision decision,
  ) async {
    final id = alias.id;
    if (id == null ||
        _actionBusy ||
        _writePermissionDenied ||
        !decision.canAttempt) {
      return;
    }
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Delete firewall alias?',
      body:
          'Delete “${alias.name}” (${alias.type}, ${alias.entries.length} values). Rules or aliases that reference it may stop working.',
      slideLabel: 'Slide to delete',
      icon: Icons.delete_forever_outlined,
    );
    if (confirmed != true || !mounted) return;

    final session = context.read<PfSenseSessionProvider>();
    final service = session.firewallAliasService;
    if (!session.connected || service == null) return;

    setState(() => _actionBusy = true);
    try {
      await service.delete(id);
      await _load(showSpinner: true);
    } on ApiException catch (error) {
      if (error.isPermissionError) {
        _markReadOnly();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _requestError(PfRestFeature.firewallAliasDelete, error),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final registry = PfRestFeatureRegistry(
      activeProfileId: session.selectedProfile?.id,
      capabilities: session.capabilities,
    );
    final read = registry.decision(PfRestFeature.firewallAliasesRead);
    final create = registry.decision(PfRestFeature.firewallAliasCreate);
    final update = registry.decision(PfRestFeature.firewallAliasUpdate);
    final delete = registry.decision(PfRestFeature.firewallAliasDelete);

    if (read.isUnsupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Firewall aliases')),
        body: PfRestFeatureBlockedView(
          decision: read,
          onRefresh: session.connected
              ? () => session.refreshCapabilities()
              : null,
        ),
      );
    }

    final query = _search.text.trim().toLowerCase();
    final visible = _aliases.where((alias) {
      if (_typeFilter != 'all' && alias.type != _typeFilter) return false;
      if (query.isEmpty) return true;
      return alias.name.toLowerCase().contains(query) ||
          alias.description.toLowerCase().contains(query) ||
          alias.entries.any(
            (entry) =>
                entry.value.toLowerCase().contains(query) ||
                entry.description.toLowerCase().contains(query),
          );
    }).toList(growable: false);

    final canCreate = session.connected &&
        create.canAttempt &&
        !_actionBusy &&
        !_writePermissionDenied;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Firewall aliases'),
        actions: [
          IconButton(
            tooltip: 'Refresh aliases',
            onPressed: _loading ? null : () => _load(showSpinner: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(showSpinner: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PfRestFeatureNotice(
              decision: read,
              onRefresh: session.connected
                  ? () => session.refreshCapabilities()
                  : null,
            ),
            if (_writePermissionDenied)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Read-only alias access'),
                  subtitle: Text(
                    'A write request was denied with 403. Create, edit and delete actions are disabled for this session.',
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Search aliases',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    key: const Key('firewall-alias-type-filter'),
                    initialValue: _typeFilter,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(value: 'host', child: Text('Host')),
                      DropdownMenuItem(
                        value: 'network',
                        child: Text('Network'),
                      ),
                      DropdownMenuItem(value: 'port', child: Text('Port')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _typeFilter = value);
                    },
                  ),
                ),
              ],
            ),
            if (_lastSuccessfulRefresh != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last updated ${_formatTime(_lastSuccessfulRefresh!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            if (!session.connected)
              _message(Icons.cloud_off_outlined, 'Disconnected')
            else if (_loading && _aliases.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_loading) const LinearProgressIndicator(minHeight: 3),
              if (_error != null)
                _message(Icons.error_outline, _error.toString()),
              if (!_loading && _error == null && visible.isEmpty)
                _message(
                  Icons.label_outline,
                  query.isEmpty && _typeFilter == 'all'
                      ? 'No firewall aliases returned.'
                      : 'No aliases match the current filters.',
                ),
              for (final alias in visible)
                _aliasCard(alias, update: update, delete: delete),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-firewall-alias'),
        onPressed: canCreate ? () => _openForm() : null,
        icon: const Icon(Icons.add),
        label: const Text('Add alias'),
      ),
    );
  }

  Widget _aliasCard(
    FirewallAlias alias, {
    required PfRestFeatureDecision update,
    required PfRestFeatureDecision delete,
  }) {
    final canEdit = alias.isSupportedType &&
        update.canAttempt &&
        !_writePermissionDenied &&
        !_actionBusy;
    final canDelete = alias.id != null &&
        delete.canAttempt &&
        !_writePermissionDenied &&
        !_actionBusy;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(_typeIcon(alias.type)),
        ),
        title: Text(alias.name.isEmpty ? 'Unnamed alias' : alias.name),
        subtitle: Text(
          '${_typeLabel(alias.type)} • ${alias.entries.length} value${alias.entries.length == 1 ? '' : 's'}'
          '${alias.description.isEmpty ? '' : '\n${alias.description}'}',
        ),
        isThreeLine: alias.description.isNotEmpty,
        onTap: () => _inspect(alias),
        trailing: PopupMenuButton<String>(
          enabled: canEdit || canDelete,
          onSelected: (value) {
            if (value == 'edit') _openForm(alias);
            if (value == 'delete') _delete(alias, delete);
          },
          itemBuilder: (context) => [
            if (canEdit)
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                ),
              ),
            if (canDelete)
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _inspect(FirewallAlias alias) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alias.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('${_typeLabel(alias.type)} alias'),
              if (!alias.isSupportedType) ...[
                const SizedBox(height: 10),
                const Text(
                  'This alias type is visible for inspection but is not supported for editing.',
                ),
              ],
              if (alias.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(alias.description),
              ],
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: alias.entries.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final entry = alias.entries[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text('${index + 1}'),
                      title: SelectableText(entry.value),
                      subtitle: entry.description.isEmpty
                          ? null
                          : Text(entry.description),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _requestError(PfRestFeature feature, Object error) {
    return pfRestFeatureRequestErrorMessage(feature, error);
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  String _typeLabel(String type) => switch (type.toLowerCase()) {
        'host' => 'Host',
        'network' => 'Network',
        'port' => 'Port',
        _ => type.isEmpty ? 'Unknown' : 'Unsupported: $type',
      };

  IconData _typeIcon(String type) => switch (type.toLowerCase()) {
        'host' => Icons.computer_outlined,
        'network' => Icons.account_tree_outlined,
        'port' => Icons.settings_input_component_outlined,
        _ => Icons.help_outline,
      };

  Widget _message(IconData icon, String text) =>
      Card(child: ListTile(leading: Icon(icon), title: Text(text)));
}
