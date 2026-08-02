import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/firewall_rule.dart';
import '../models/pfrest_capabilities.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import 'firewall_aliases_screen.dart';
import 'firewall_nat_screen.dart';
import 'firewall_rule_form_screen.dart';

class FirewallRulesScreen extends StatefulWidget {
  const FirewallRulesScreen({super.key});

  @override
  State<FirewallRulesScreen> createState() => _FirewallRulesScreenState();
}

class _FirewallRulesScreenState extends State<FirewallRulesScreen> {
  final Set<String> _interfaces = {'all'};
  final Set<String> _busyRuleIds = {};
  final TextEditingController _search = TextEditingController();
  List<FirewallRule> _rules = [];
  String _selectedInterface = 'all';
  String _statusFilter = 'all';
  Object? _error;
  bool _loading = false;
  bool _writePermissionDenied = false;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastSuccessfulRefresh;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final sessionChanged =
        _loadedSessionGeneration != session.sessionGeneration ||
            _loadedProfileId != profileId;

    if (sessionChanged) {
      _requestGeneration++;
      _rules = [];
      _interfaces
        ..clear()
        ..add('all');
      _selectedInterface = 'all';
      _statusFilter = 'all';
      _search.clear();
      _busyRuleIds.clear();
      _error = null;
      _writePermissionDenied = false;
      _lastSuccessfulRefresh = null;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(showSpinner: true);
        });
      }
    } else if (_rules.isEmpty && !_loading && session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(showSpinner: true);
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  PfRestOperationCapability? _operation(
    PfSenseSessionProvider session,
    String method,
  ) {
    return session.capabilities?.operation('/api/v2/firewall/rule', method);
  }

  bool _schemaSupports(
    PfSenseSessionProvider session,
    String path,
    String method,
  ) {
    final capabilities = session.capabilities;
    return capabilities?.isAvailable != true || capabilities!.supports(path, method);
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      setState(() {
        _rules = [];
        _lastSuccessfulRefresh = null;
        _error =
            AppLocalizations.of(context)?.disconnectedMessage ?? 'Disconnected';
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
      final interface =
          _selectedInterface == 'all' ? null : _selectedInterface;
      final rules = session.firewallRuleService != null
          ? await session.firewallRuleService!.list(interface: interface)
          : await session.service!.getFirewallRules(interface: interface);
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _rules = rules;
        _interfaces.addAll(
          rules.expand((rule) => rule.interfaces).where((name) => name.isNotEmpty),
        );
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

  Future<void> _toggle(FirewallRule rule) async {
    final id = rule.id;
    if (id == null || _busyRuleIds.contains(id) || _writePermissionDenied) {
      return;
    }
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          rule.enabled ? 'Disable firewall rule?' : 'Enable firewall rule?',
        ),
        content: Text(
          rule.description.isEmpty
              ? 'This changes the ${rule.type.toUpperCase()} rule on ${rule.interface}.'
              : 'This changes “${rule.description}” on ${rule.interface}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(rule.enabled ? 'Disable' : 'Enable'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyRuleIds.add(id));
    try {
      if (session.firewallRuleService != null) {
        await session.firewallRuleService!.setEnabled(
          rule,
          !rule.enabled,
          operation: _operation(session, 'PATCH'),
        );
      } else {
        await session.service!.toggleFirewallRule(id, !rule.enabled);
      }
      await _load();
    } on ApiException catch (error) {
      _handleWriteError(error);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busyRuleIds.remove(id));
    }
  }

  Future<void> _delete(FirewallRule rule) async {
    final id = rule.id;
    if (id == null || _busyRuleIds.contains(id) || _writePermissionDenied) {
      return;
    }
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete firewall rule?'),
        content: Text(
          '${rule.description.isEmpty ? 'This firewall rule' : '“${rule.description}”'} will be permanently removed and the firewall ruleset will be reloaded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyRuleIds.add(id));
    try {
      if (session.firewallRuleService != null) {
        await session.firewallRuleService!.delete(rule);
      } else {
        await session.service!.deleteFirewallRule(id);
      }
      await _load();
    } on ApiException catch (error) {
      _handleWriteError(error);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busyRuleIds.remove(id));
    }
  }

  void _handleWriteError(ApiException error) {
    if (!mounted) return;
    if (error.isPermissionError) {
      setState(() => _writePermissionDenied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permission denied (403). Firewall rule management is now read-only for this session.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _openForm([FirewallRule? rule]) async {
    final session = context.read<PfSenseSessionProvider>();
    final method = rule == null ? 'POST' : 'PATCH';
    if (!_schemaSupports(session, '/api/v2/firewall/rule', method)) return;

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FirewallRuleFormScreen(
          rule: rule,
          availableInterfaces:
              _interfaces.where((value) => value != 'all').toList(),
          onPermissionDenied: () {
            if (mounted) setState(() => _writePermissionDenied = true);
          },
        ),
      ),
    );
    if (changed == true) await _load(showSpinner: true);
  }

  void _openAliases() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FirewallAliasesScreen()),
    );
  }

  void _openNat() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FirewallNatScreen()),
    );
  }

  List<FirewallRule> get _filteredRules {
    final query = _search.text.trim().toLowerCase();
    return _rules.where((rule) {
      final statusMatches = switch (_statusFilter) {
        'enabled' => rule.enabled,
        'disabled' => !rule.enabled,
        'logged' => rule.log,
        _ => true,
      };
      if (!statusMatches) return false;
      if (query.isEmpty) return true;

      final searchable = [
        rule.description,
        rule.type,
        rule.interface,
        rule.protocolLabel,
        rule.sourceNetwork,
        rule.sourcePortRange,
        rule.destinationNetwork,
        rule.portRange,
        rule.gateway ?? '',
        rule.tag,
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final session = context.watch<PfSenseSessionProvider>();
    final visibleRules = _filteredRules;
    final canCreate = session.connected &&
        !_writePermissionDenied &&
        _schemaSupports(session, '/api/v2/firewall/rule', 'POST');
    final canUpdate = !_writePermissionDenied &&
        _schemaSupports(session, '/api/v2/firewall/rule', 'PATCH');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(showSpinner: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedInterface,
                    decoration: InputDecoration(
                      labelText: strings?.interface ?? 'Interface',
                      prefixIcon: const Icon(Icons.settings_ethernet),
                    ),
                    items: [
                      for (final name in _interfaces)
                        DropdownMenuItem(
                          value: name,
                          child: Text(
                            name == 'all' ? (strings?.all ?? 'All') : name,
                          ),
                        ),
                    ],
                    onChanged: _loading
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _selectedInterface = value);
                            _load(showSpinner: true);
                          },
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  key: const Key('firewall-tools-menu'),
                  tooltip: 'Firewall tools',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'aliases') _openAliases();
                    if (value == 'nat') _openNat();
                    if (value == 'refresh') _load(showSpinner: true);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'aliases',
                      enabled: session.connected,
                      child: const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.label_outline),
                        title: Text('Aliases'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'nat',
                      enabled: session.connected,
                      child: const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.swap_horiz),
                        title: Text('NAT'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'refresh',
                      enabled: !_loading,
                      child: const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.refresh),
                        title: Text('Refresh rules'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('firewall-rule-search'),
              controller: _search,
              decoration: InputDecoration(
                labelText: 'Search rules',
                hintText: 'Description, address, alias, port or protocol',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _search.clear,
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'All'),
                  _filterChip('enabled', 'Enabled'),
                  _filterChip('disabled', 'Disabled'),
                  _filterChip('logged', 'Logged'),
                ],
              ),
            ),
            if (_writePermissionDenied)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Read-only firewall rules'),
                  subtitle: Text(
                    'The current credential cannot change firewall rules. Reconnect after updating its permissions.',
                  ),
                ),
              ),
            if (!_schemaSupports(session, '/api/v2/firewall/rule', 'POST') &&
                session.capabilities?.isAvailable == true)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.extension_off_outlined),
                  title: Text('Rule creation unavailable'),
                  subtitle: Text(
                    'The installed pfREST schema does not report the singular firewall-rule create endpoint.',
                  ),
                ),
              ),
            if (_lastSuccessfulRefresh != null) ...[
              const SizedBox(height: 8),
              Text(
                '${visibleRules.length} of ${_rules.length} rules • Updated ${_formatTime(_lastSuccessfulRefresh!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (!session.connected)
              _message(
                Icons.cloud_off_outlined,
                strings?.disconnectedMessage ?? 'Disconnected',
              )
            else if (_loading && _rules.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_loading) const LinearProgressIndicator(minHeight: 3),
              if (_error != null)
                _message(Icons.error_outline, _error.toString()),
              if (!_loading && _error == null && visibleRules.isEmpty)
                _message(
                  Icons.rule_folder_outlined,
                  _rules.isEmpty
                      ? (strings?.emptyState ?? 'Nothing to show yet.')
                      : 'No firewall rules match the current filters.',
                ),
              for (final rule in visibleRules) _ruleCard(rule, canUpdate),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canCreate ? () => _openForm() : null,
        icon: const Icon(Icons.add),
        label: Text(strings?.addRule ?? 'Add rule'),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: _statusFilter == value,
        label: Text(label),
        onSelected: (_) => setState(() => _statusFilter = value),
      ),
    );
  }

  Widget _ruleCard(FirewallRule rule, bool canUpdate) {
    final id = rule.id;
    final busy = id != null && _busyRuleIds.contains(id);
    final actionColor = _color(rule.type);
    final source = _endpointText(rule.sourceNetwork, rule.sourcePortRange);
    final destination =
        _endpointText(rule.destinationNetwork, rule.portRange);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: busy || !canUpdate ? null : () => _openForm(rule),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _badge(
                              rule.type.toUpperCase(),
                              icon: _icon(rule.type),
                              color: actionColor,
                            ),
                            _badge(rule.protocolLabel),
                            _badge(rule.interface.isEmpty ? 'ANY' : rule.interface),
                            _badge(
                              rule.enabled ? 'ENABLED' : 'DISABLED',
                              color: rule.enabled
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          rule.description.isEmpty
                              ? '${rule.type.toUpperCase()} rule'
                              : rule.description,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: 'Rule actions',
                      onSelected: (value) {
                        if (value == 'toggle') _toggle(rule);
                        if (value == 'edit') _openForm(rule);
                        if (value == 'delete') _delete(rule);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'toggle',
                          enabled: canUpdate && id != null,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              rule.enabled
                                  ? Icons.toggle_off_outlined
                                  : Icons.toggle_on_outlined,
                            ),
                            title: Text(rule.enabled ? 'Disable' : 'Enable'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'edit',
                          enabled: canUpdate,
                          child: const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          enabled: !_writePermissionDenied && id != null,
                          child: const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_outline),
                            title: Text('Delete'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _trafficRow(
                Icons.call_made_outlined,
                'Source',
                source,
              ),
              const SizedBox(height: 8),
              _trafficRow(
                Icons.call_received_outlined,
                'Destination',
                destination,
              ),
              if (rule.floating ||
                  rule.log ||
                  rule.gateway != null ||
                  rule.tag.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (rule.floating)
                      _badge('FLOATING ${rule.direction.toUpperCase()}'),
                    if (rule.log) _badge('LOGGED', icon: Icons.receipt_long),
                    if (rule.gateway != null)
                      _badge('GW ${rule.gateway}', icon: Icons.alt_route),
                    if (rule.tag.isNotEmpty)
                      _badge(rule.tag, icon: Icons.sell_outlined),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _trafficRow(IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _badge(
    String label, {
    IconData? icon,
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: resolved.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: resolved),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: resolved,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _endpointText(String network, String port) {
    return port.isEmpty ? network : '$network : $port';
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  Color _color(String type) => switch (type.toLowerCase()) {
        'pass' => Colors.green,
        'block' => Colors.red,
        'reject' => Colors.orange,
        _ => Colors.grey,
      };

  IconData _icon(String type) => switch (type.toLowerCase()) {
        'pass' => Icons.check,
        'block' => Icons.block,
        'reject' => Icons.remove_circle_outline,
        _ => Icons.help_outline,
      };

  Widget _message(IconData icon, String text) =>
      Card(child: ListTile(leading: Icon(icon), title: Text(text)));
}
