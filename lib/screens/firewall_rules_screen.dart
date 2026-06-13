import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/firewall_rule.dart';
import '../providers/session_provider.dart';
import 'firewall_rule_form_screen.dart';

class FirewallRulesScreen extends StatefulWidget {
  const FirewallRulesScreen({super.key});
  @override
  State<FirewallRulesScreen> createState() => _FirewallRulesScreenState();
}

class _FirewallRulesScreenState extends State<FirewallRulesScreen> {
  final Set<String> _ifs = {'all'};
  List<FirewallRule> _rules = [];
  String _if = 'all';
  Object? _error;
  bool _loading = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loading && _rules.isEmpty) _load(showSpinner: true);
  }

  Future<void> _load({bool showSpinner = false}) async {
    final s = context.read<PfSenseSessionProvider>();
    if (!s.connected || s.service == null) {
      setState(
          () => _error = AppLocalizations.of(context)?.disconnectedMessage);
      return;
    }
    if (showSpinner) setState(() => _loading = true);
    try {
      final r = await s.service!
          .getFirewallRules(interface: _if == 'all' ? null : _if);
      if (mounted) {
        setState(() {
          _rules = r;
          _ifs.addAll(r.map((e) => e.interface).where((e) => e.isNotEmpty));
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted && showSpinner) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(FirewallRule r) async {
    if (r.id == null) return;
    try {
      await context
          .read<PfSenseSessionProvider>()
          .service!
          .toggleFirewallRule(r.id!, !r.enabled);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _form([FirewallRule? r]) async {
    final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => FirewallRuleFormScreen(rule: r)));
    if (ok == true) await _load(showSpinner: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = context.watch<PfSenseSessionProvider>();
    return Scaffold(
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(
                    child: DropdownButtonFormField<String>(
                        initialValue: _if,
                        decoration: InputDecoration(
                            labelText: l?.interface ?? 'Interface',
                            prefixIcon: const Icon(Icons.settings_ethernet)),
                        items: [
                          for (final name in _ifs)
                            DropdownMenuItem(
                                value: name,
                                child: Text(
                                    name == 'all' ? (l?.all ?? 'All') : name))
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _if = v);
                            _load(showSpinner: true);
                          }
                        })),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                    onPressed: () => _load(showSpinner: true),
                    icon: const Icon(Icons.refresh))
              ]),
              const SizedBox(height: 16),
              if (!s.connected)
                _msg(Icons.cloud_off_outlined,
                    l?.disconnectedMessage ?? 'Disconnected')
              else if (_loading)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                _msg(Icons.error_outline, _error.toString())
              else if (_rules.isEmpty)
                _msg(Icons.rule_folder_outlined,
                    l?.emptyState ?? 'Nothing to show yet.')
              else
                for (final r in _rules)
                  Dismissible(
                      key: ValueKey(r.id ??
                          '${r.interface}-${r.description}-${r.createdTime}'),
                      confirmDismiss: (_) async {
                        await _toggle(r);
                        return false;
                      },
                      background: Container(
                          color: r.enabled ? Colors.orange : Colors.green,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Icon(
                              r.enabled ? Icons.toggle_off : Icons.toggle_on,
                              color: Colors.white)),
                      child: Card(
                          child: ListTile(
                              leading: CircleAvatar(
                                  backgroundColor:
                                      _color(r.type).withValues(alpha: .16),
                                  child: Icon(_icon(r.type),
                                      color: _color(r.type))),
                              title: Text(r.description.isEmpty
                                  ? '${r.type.toUpperCase()} ${r.interface}'
                                  : r.description),
                              subtitle:
                                  Text('${r.interface} | ${r.protocol.toUpperCase()} | ${r.sourceNetwork} -> ${r.destinationNetwork}${r.portRange.isEmpty ? '' : ':${r.portRange}'}'),
                              trailing: Switch(value: r.enabled, onChanged: (_) => _toggle(r)),
                              onTap: () => _form(r))))
            ])),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: s.connected
                ? () => _form()
                : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(l?.disconnectedMessage ?? 'Disconnected'))),
            icon: const Icon(Icons.add),
            label: Text(l?.addRule ?? 'Add rule')));
  }

  Color _color(String t) => switch (t.toLowerCase()) {
        'pass' => Colors.green,
        'block' => Colors.red,
        'reject' => Colors.orange,
        _ => Colors.grey
      };
  IconData _icon(String t) => switch (t.toLowerCase()) {
        'pass' => Icons.check,
        'block' => Icons.block,
        'reject' => Icons.remove_circle_outline,
        _ => Icons.help_outline
      };
  Widget _msg(IconData i, String t) =>
      Card(child: ListTile(leading: Icon(i), title: Text(t)));
}
