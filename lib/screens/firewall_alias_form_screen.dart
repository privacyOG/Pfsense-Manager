import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/firewall_alias.dart';
import '../providers/session_provider.dart';
import '../services/pfrest_feature_registry.dart';
import '../utils/api_exception.dart';
import '../utils/firewall_alias_validation.dart';
import '../widgets/pfrest_feature_gate.dart';

class FirewallAliasFormScreen extends StatefulWidget {
  const FirewallAliasFormScreen({
    super.key,
    this.alias,
    required this.existingAliases,
    this.onPermissionDenied,
  });

  final FirewallAlias? alias;
  final List<FirewallAlias> existingAliases;
  final VoidCallback? onPermissionDenied;

  @override
  State<FirewallAliasFormScreen> createState() =>
      _FirewallAliasFormScreenState();
}

class _FirewallAliasFormScreenState extends State<FirewallAliasFormScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.alias?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.alias?.description ?? '',
  );
  late String _type = widget.alias?.type.toLowerCase() ?? 'host';
  late final List<_AliasEntryControllers> _entries = [
    for (final entry in widget.alias?.entries ?? const <FirewallAliasEntry>[])
      _AliasEntryControllers.fromEntry(entry),
    if (widget.alias == null || widget.alias!.entries.isEmpty)
      _AliasEntryControllers(),
  ];
  FirewallAliasValidationResult? _validation;
  bool _saving = false;
  bool _permissionDenied = false;

  bool get _editing => widget.alias != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  FirewallAlias _draft() {
    return FirewallAlias(
      id: widget.alias?.id,
      name: _name.text,
      type: _type,
      description: _description.text,
      entries: [for (final entry in _entries) entry.value],
    );
  }

  Future<void> _save(PfRestFeatureDecision decision) async {
    if (_saving || _permissionDenied || !decision.canAttempt) return;
    final validation = validateFirewallAlias(
      _draft(),
      existingAliases: widget.existingAliases,
    );
    setState(() => _validation = validation);
    if (!validation.isValid) return;

    final session = context.read<PfSenseSessionProvider>();
    final service = session.firewallAliasService;
    if (!session.connected || service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to a firewall first.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_editing) {
        await service.update(_draft());
      } else {
        await service.create(_draft());
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (error.isPermissionError) {
        widget.onPermissionDenied?.call();
        if (mounted) {
          setState(() => _permissionDenied = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permission denied (403). Alias management is now read-only for this session.',
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final registry = PfRestFeatureRegistry(
      activeProfileId: session.selectedProfile?.id,
      capabilities: session.capabilities,
    );
    final feature = _editing
        ? PfRestFeature.firewallAliasUpdate
        : PfRestFeature.firewallAliasCreate;
    final decision = registry.decision(feature);
    final canSave = session.connected &&
        decision.canAttempt &&
        !_saving &&
        !_permissionDenied;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit firewall alias' : 'Create firewall alias'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PfRestFeatureNotice(
            decision: decision,
            onRefresh: session.connected
                ? () => session.refreshCapabilities()
                : null,
          ),
          if (_permissionDenied)
            const Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Read-only access'),
                subtitle: Text(
                  'This credential cannot write firewall aliases. Reconnect after changing its permissions.',
                ),
              ),
            ),
          TextField(
            key: const Key('firewall-alias-name'),
            controller: _name,
            enabled: !_editing,
            maxLength: 31,
            decoration: InputDecoration(
              labelText: 'Alias name',
              helperText: _editing
                  ? 'pfREST does not allow alias names to be changed.'
                  : 'Letters, numbers and underscores only.',
              errorText: _validation?.nameError,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('firewall-alias-type'),
            initialValue: FirewallAlias.supportedTypes.contains(_type)
                ? _type
                : 'host',
            decoration: InputDecoration(
              labelText: 'Alias type',
              errorText: _validation?.typeError,
            ),
            items: const [
              DropdownMenuItem(value: 'host', child: Text('Host')),
              DropdownMenuItem(value: 'network', child: Text('Network')),
              DropdownMenuItem(value: 'port', child: Text('Port')),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _type = value;
                      _validation = null;
                    });
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('firewall-alias-description'),
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Alias values',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _entries.add(_AliasEntryControllers());
                          _validation = null;
                        }),
                icon: const Icon(Icons.add),
                label: const Text('Add value'),
              ),
            ],
          ),
          Text(
            _entryHelp(_type),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < _entries.length; index++)
            _entryCard(index),
          if (_validation?.generalError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _validation!.generalError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('save-firewall-alias'),
            onPressed: canSave ? () => _save(decision) : null,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save alias'),
          ),
        ],
      ),
    );
  }

  Widget _entryCard(int index) {
    final entry = _entries[index];
    return Card(
      key: ValueKey(entry),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: Key('firewall-alias-value-$index'),
                    controller: entry.valueController,
                    decoration: InputDecoration(
                      labelText: 'Value ${index + 1}',
                      errorText: _validation?.entryErrors[index],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove value',
                  onPressed: _saving || _entries.length == 1
                      ? null
                      : () => setState(() {
                            final removed = _entries.removeAt(index);
                            removed.dispose();
                            _validation = null;
                          }),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: Key('firewall-alias-entry-description-$index'),
              controller: entry.descriptionController,
              decoration: const InputDecoration(
                labelText: 'Value description',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _entryHelp(String type) => switch (type) {
        'network' =>
          'Use IPv4 or IPv6 CIDR values, FQDNs, or existing non-port alias names.',
        'port' =>
          'Use ports, ascending ranges such as 8000-8080, or existing port alias names.',
        _ =>
          'Use IPv4 or IPv6 addresses, FQDNs, or existing non-port alias names.',
      };
}

class _AliasEntryControllers {
  _AliasEntryControllers()
      : valueController = TextEditingController(),
        descriptionController = TextEditingController();

  _AliasEntryControllers.fromEntry(FirewallAliasEntry entry)
      : valueController = TextEditingController(text: entry.value),
        descriptionController = TextEditingController(text: entry.description);

  final TextEditingController valueController;
  final TextEditingController descriptionController;

  FirewallAliasEntry get value => FirewallAliasEntry(
        value: valueController.text,
        description: descriptionController.text,
      );

  void dispose() {
    valueController.dispose();
    descriptionController.dispose();
  }
}
