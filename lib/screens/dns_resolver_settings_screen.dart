import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dns_management.dart';
import '../models/interface_management.dart';
import '../models/pfrest_capabilities.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/dns_management_validation.dart';
import '../widgets/slide_to_confirm.dart';

class DnsResolverSettingsScreen extends StatefulWidget {
  const DnsResolverSettingsScreen({
    super.key,
    required this.settings,
    required this.interfaces,
    this.onPermissionDenied,
  });

  final DnsResolverSettings settings;
  final List<ManagedInterfaceResource> interfaces;
  final VoidCallback? onPermissionDenied;

  @override
  State<DnsResolverSettingsScreen> createState() =>
      _DnsResolverSettingsScreenState();
}

class _DnsResolverSettingsScreenState
    extends State<DnsResolverSettingsScreen> {
  late Map<String, dynamic> _values;
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.settings.raw);
    for (final entry in const <String, Object>{
      'enable': false,
      'port': 53,
      'enablessl': false,
      'tlsport': 853,
      'active_interface': <String>[],
      'outgoing_interface': <String>[],
      'strictout': false,
      'system_domain_local_zone_type': 'transparent',
      'dnssec': false,
      'python': false,
      'python_order': 'pre_validator',
      'python_script': '',
      'forwarding': false,
      'regdhcp': false,
      'regdhcpstatic': false,
      'regovpnclients': false,
      'custom_options': '',
    }.entries) {
      _values.putIfAbsent(entry.key, () => entry.value);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.dnsManagementService;
    final operation = service?.capabilities.settingsUpdate;
    if (!session.connected || service == null || operation == null) return;
    if (!service.capabilities.forService(DnsServiceKind.resolver).canApply) {
      _message('DNS Resolver changes cannot be applied by this profile.');
      return;
    }

    final values = normaliseDnsValues(_values);
    final validation = validateResolverSettings(
      values: values,
      operation: operation,
    );
    if (!validation.isValid) {
      setState(() => _errors = validation.errors);
      _message(validation.summary);
      return;
    }

    final changes = _changedValues(values);
    if (changes.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }

    final customChanged = changes.containsKey('custom_options');
    final confirmed = customChanged
        ? await showSlideToConfirmSheet(
            context: context,
            title: 'Apply custom Resolver options?',
            body:
                'Custom options are inserted into the Resolver configuration and can prevent Unbound from starting. Apply only syntax that is valid for this firewall.',
            slideLabel: 'Slide to save and apply',
            icon: Icons.warning_amber_outlined,
          )
        : await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Save DNS Resolver settings?'),
              content: const Text(
                'Listening, outgoing-interface, port and service-state changes can interrupt DNS resolution. The configuration will be applied after the write succeeds.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save and apply'),
                ),
              ],
            ),
          );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await service.updateResolverSettings(widget.settings, changes);
      await service.apply(DnsServiceKind.resolver);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (error.isPermissionError) widget.onPermissionDenied?.call();
      if (mounted) _message(error.toString());
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _changedValues(Map<String, dynamic> values) {
    return {
      for (final entry in values.entries)
        if (!_equivalent(widget.settings.raw[entry.key], entry.value))
          entry.key: entry.value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.dnsManagementService;
    final operation = service?.capabilities.settingsUpdate;
    if (service == null || operation == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('DNS Resolver settings')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Resolver settings are not writable for the selected profile.',
            ),
          ),
        ),
      );
    }

    final fields = operation.requestFields.values
        .where((field) => field.location.toLowerCase() == 'body')
        .toList(growable: false);
    final byName = {for (final field in fields) field.name: field};
    final advanced = fields
        .where((field) => !_knownFields.contains(field.name))
        .toList(growable: false);
    final canApply =
        service.capabilities.forService(DnsServiceKind.resolver).canApply;

    return Scaffold(
      appBar: AppBar(title: const Text('DNS Resolver settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Service and ports'),
          _fieldIfPresent(byName['enable']),
          _fieldIfPresent(byName['port']),
          _fieldIfPresent(byName['enablessl']),
          if (_boolean(_values['enablessl'])) ...[
            _fieldIfPresent(byName['sslcertref']),
            _fieldIfPresent(byName['tlsport']),
          ],
          _section('Interfaces'),
          _interfaceField(byName['active_interface']),
          _interfaceField(byName['outgoing_interface']),
          _fieldIfPresent(byName['strictout']),
          _section('Resolution behaviour'),
          for (final name in const [
            'system_domain_local_zone_type',
            'dnssec',
            'forwarding',
            'regdhcp',
            'regdhcpstatic',
            'regovpnclients',
          ])
            _fieldIfPresent(byName[name]),
          _section('Python module'),
          _fieldIfPresent(byName['python']),
          if (_boolean(_values['python'])) ...[
            _fieldIfPresent(byName['python_order']),
            _fieldIfPresent(byName['python_script']),
          ],
          _section('Custom options'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.warning_amber_outlined),
              title: Text('Advanced configuration'),
              subtitle: Text(
                'Invalid custom options can prevent the DNS Resolver service from starting. Existing content is preserved unless edited.',
              ),
            ),
          ),
          _fieldIfPresent(byName['custom_options'], multiline: true),
          if (advanced.isNotEmpty) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              leading: const Icon(Icons.tune),
              title: const Text('Additional reported fields'),
              children: [
                for (final field in advanced)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: _field(field),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving || !canApply ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Applying…' : 'Save and apply'),
          ),
        ].expand(_withSpacing).toList(growable: false),
      ),
    );
  }

  Iterable<Widget> _withSpacing(Widget widget) sync* {
    yield widget;
    if (widget is! SizedBox) yield const SizedBox(height: 12);
  }

  Widget _section(String label) => Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      );

  Widget _fieldIfPresent(
    PfRestFieldConstraint? field, {
    bool multiline = false,
  }) {
    return field == null ? const SizedBox.shrink() : _field(field, multiline: multiline);
  }

  Widget _interfaceField(PfRestFieldConstraint? field) {
    if (field == null) return const SizedBox.shrink();
    final selected = _stringList(_values[field.name]).toSet();
    final options = <String, String>{
      for (final special in const ['all', '_llocwan', '_lloclan'])
        special: _displayValue(special),
      for (final interface in widget.interfaces)
        if ((interface.id?.toString().trim() ?? '').isNotEmpty)
          interface.id!.toString(): interface.description.isEmpty
              ? interface.id!.toString().toUpperCase()
              : '${interface.description} (${interface.id})',
      for (final current in selected) current: current,
    };
    return InputDecorator(
      decoration: InputDecoration(
        labelText: _label(field.name),
        errorText: _errors[field.name],
        helperText: selected.isEmpty
            ? 'No explicit selection uses the service default.'
            : null,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final entry in options.entries)
            FilterChip(
              label: Text(entry.value),
              selected: selected.contains(entry.key),
              onSelected: (value) {
                final next = Set<String>.from(selected);
                value ? next.add(entry.key) : next.remove(entry.key);
                _setValue(field.name, next.toList(growable: false));
              },
            ),
        ],
      ),
    );
  }

  Widget _field(
    PfRestFieldConstraint field, {
    bool multiline = false,
  }) {
    final name = field.name;
    final value = _values[name];
    if (field.type == 'boolean' || value is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_label(name)),
        subtitle: _errorText(name),
        value: _boolean(value),
        onChanged: (selected) => _setValue(name, selected),
      );
    }

    final allowed = field.allowedValues
        .map((item) => item?.toString())
        .whereType<String>()
        .toSet();
    if (allowed.isNotEmpty) {
      final current = value?.toString();
      if (current != null && current.isNotEmpty) allowed.add(current);
      return DropdownButtonFormField<String>(
        key: ValueKey('resolver-setting-$name-$current'),
        initialValue: current == null || current.isEmpty ? null : current,
        decoration: InputDecoration(
          labelText: _label(name),
          errorText: _errors[name],
        ),
        items: [
          for (final option in allowed)
            DropdownMenuItem(
              value: option,
              child: Text(_displayValue(option)),
            ),
        ],
        onChanged: (selected) => _setValue(name, selected),
      );
    }

    final isList = field.type == 'array' || value is List;
    return TextFormField(
      key: ValueKey('resolver-setting-$name-${value?.hashCode ?? 0}'),
      initialValue: isList && value is List
          ? value.map((item) => item.toString()).join(', ')
          : value?.toString() ?? '',
      maxLines: multiline || isList ? 5 : 1,
      keyboardType: field.type == 'integer' || field.type == 'number'
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: _label(name),
        errorText: _errors[name],
        helperText: isList ? 'Separate values with commas.' : null,
        alignLabelWithHint: multiline || isList,
      ),
      onChanged: (text) {
        final parsed = isList
            ? _splitValues(text)
            : field.type == 'integer'
                ? int.tryParse(text) ?? text
                : field.type == 'number'
                    ? num.tryParse(text) ?? text
                    : text;
        _setValue(name, parsed);
      },
    );
  }

  Widget? _errorText(String name) {
    final error = _errors[name];
    if (error == null) return null;
    return Text(
      error,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }

  void _setValue(String name, Object? value) {
    setState(() {
      _values[name] = value;
      _errors = {..._errors}..remove(name);
    });
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

const _knownFields = {
  'enable',
  'port',
  'enablessl',
  'sslcertref',
  'tlsport',
  'active_interface',
  'outgoing_interface',
  'strictout',
  'system_domain_local_zone_type',
  'dnssec',
  'python',
  'python_order',
  'python_script',
  'forwarding',
  'regdhcp',
  'regdhcpstatic',
  'regovpnclients',
  'custom_options',
};

bool _equivalent(Object? first, Object? second) {
  if (first is List && second is List) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!_equivalent(first[index], second[index])) return false;
    }
    return true;
  }
  if (first is Map && second is Map) {
    if (first.length != second.length) return false;
    for (final key in first.keys) {
      if (!second.containsKey(key) || !_equivalent(first[key], second[key])) {
        return false;
      }
    }
    return true;
  }
  return first?.toString() == second?.toString();
}

List<String> _splitValues(String value) {
  return value
      .split(RegExp(r'[,;\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? const [] : [text];
}

bool _boolean(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
}

String _label(String name) {
  return name
      .replaceAll('_', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

String _displayValue(String value) {
  return switch (value) {
    'all' => 'All interfaces',
    '_llocwan' => 'All WAN interfaces',
    '_lloclan' => 'All LAN interfaces',
    'pre_validator' => 'Before validation',
    'post_validator' => 'After validation',
    _ => _label(value),
  };
}
