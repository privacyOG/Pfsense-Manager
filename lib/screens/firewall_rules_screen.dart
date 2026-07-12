import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/firewall_rule.dart';
import '../providers/session_provider.dart';
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
  List<FirewallRule> _rules = [];
  String _selectedInterface = 'all';
  Object? _error;
  bool _loading = false;
  bool _actionBusy = false;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastSuccessfulRefresh;

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
      _error = null;
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
    super.dispose();
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
      final rules = await session.service!.getFirewallRules(
        interface: _selectedInterface == 'all' ? null : _selectedInterface,
      );
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _rules = rules;
        _interfaces.addAll(
          rules.map((rule) => rule.interface).where((name) => name.isNotEmpty),
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
    if (rule.id == null || _actionBusy) return;
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

    setState(() => _actionBusy = true);
    try {
      await session.service!.toggleFirewallRule(rule.id!, !rule.enabled);
      await _load(showSpinner: true);
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

  Future<void> _openForm([FirewallRule? rule]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FirewallRuleFormScreen(rule: rule)),
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

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final session = context.watch<PfSenseSessionProvider>();

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
                IconButton.filledTonal(
                  key: const Key('open-firewall-aliases'),
                  tooltip: 'Firewall aliases',
                  onPressed: session.connected ? _openAliases : null,
                  icon: const Icon(Icons.label_outline),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  key: const Key('open-firewall-nat'),
                  tooltip: 'NAT management',
                  onPressed: session.connected ? _openNat : null,
                  icon: const Icon(Icons.swap_horiz),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  onPressed: _loading ? null : () => _load(showSpinner: true),
                  icon: const Icon(Icons.refresh),
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
              if (!_loading && _error == null && _rules.isEmpty)
                _message(
                  Icons.rule_folder_outlined,
                  strings?.emptyState ?? 'Nothing to show yet.',
                ),
              for (final rule in _rules)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _color(rule.type).withValues(alpha: .16),
                      child: Icon(_icon(rule.type), color: _color(rule.type)),
                    ),
                    title: Text(
                      rule.description.isEmpty
                          ? '${rule.type.toUpperCase()} ${rule.interface}'
                          : rule.description,
                    ),
                    subtitle: Text(
                      '${rule.interface} | ${rule.protocolLabel} | '
                      '${rule.sourceNetwork} → ${rule.destinationNetwork}'
                      '${rule.portRange.isEmpty ? '' : ':${rule.portRange}'}',
                    ),
                    trailing: Switch(
                      value: rule.enabled,
                      onChanged: _actionBusy ? null : (_) => _toggle(rule),
                    ),
                    onTap: _actionBusy ? null : () => _openForm(rule),
                  ),
                ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: session.connected && !_actionBusy
            ? () => _openForm()
            : null,
        icon: const Icon(Icons.add),
        label: Text(strings?.addRule ?? 'Add rule'),
      ),
    );
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
