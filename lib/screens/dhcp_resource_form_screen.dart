import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dhcp_management.dart';
import '../models/interface_management.dart';
import '../models/pfrest_capabilities.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/dhcp_management_validation.dart';

class DhcpResourceFormScreen extends StatefulWidget {
  const DhcpResourceFormScreen({
    super.key,
    required this.kind,
    required this.servers,
    required this.staticMappings,
    required this.addressPools,
    required this.interfaces,
    required this.relayEnabled,
    this.resource,
    this.initialValues = const {},
    this.onPermissionDenied,
  });

  final DhcpResourceKind kind;
  final ManagedDhcpResource? resource;
  final Map<String, dynamic> initialValues;
  final List<ManagedDhcpResource> servers;
  final List<ManagedDhcpResource> staticMappings;
  final List<ManagedDhcpResource> addressPools;
  final List<ManagedInterfaceResource> interfaces;
  final bool relayEnabled;
  final VoidCallback? onPermissionDenied;

  @override
  State<DhcpResourceFormScreen> createState() =>
      _DhcpResourceFormScreenState();
}

class _DhcpResourceFormScreenState extends State<DhcpResourceFormScreen> {
  late Map<String, dynamic> _values;
  Map<String, String> _errors = const {};
  bool _saving = false;

  bool get _editing => widget.resource != null;

  @override
  void initState() {
    super.initState();
    _values = {
      ...?widget.resource?.raw,
      ...widget.initialValues,
    };
    switch (widget.kind) {
      case DhcpResourceKind.server:
        _values.putIfAbsent('enable', () => false);
        _values.putIfAbsent('defaultleasetime', () => 7200);
        _values.putIfAbsent('maxleasetime', () => 86400);
        for (final name in const [
          'dnsserver',
          'winsserver',
          'ntpserver',
          'domainsearchlist',
          'mac_allow',
          'mac_deny',
        ]) {
          _values.putIfAbsent(name, () => <String>[]);
        }
        for (final name in const [
          'staticarp',
          'ignorebootp',
          'ignoreclientuids',
          'nonak',
          'disablepingcheck',
          'dhcpleaseinlocaltime',
          'statsgraph',
        ]) {
          _values.putIfAbsent(name, () => false);
        }
      case DhcpResourceKind.staticMapping:
        _values.putIfAbsent('defaultleasetime', () => 7200);
        _values.putIfAbsent('maxleasetime', () => 86400);
        _values.putIfAbsent('arp_table_static_entry', () => false);
        for (final name in const [
          'dnsserver',
          'winsserver',
          'ntpserver',
          'domainsearchlist',
        ]) {
          _values.putIfAbsent(name, () => <String>[]);
        }
      case DhcpResourceKind.addressPool:
        _values.putIfAbsent('defaultleasetime', () => 7200);
        _values.putIfAbsent('maxleasetime', () => 86400);
        _values.putIfAbsent('ignorebootp', () => false);
        _values.putIfAbsent('ignoreclientuids', () => false);
        for (final name in const [
          'dnsserver',
          'winsserver',
          'ntpserver',
          'domainsearchlist',
          'mac_allow',
          'mac_deny',
        ]) {
          _values.putIfAbsent(name, () => <String>[]);
        }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.dhcpManagementService;
    if (!session.connected || service == null) return;

    final capability = service.capabilities.forKind(widget.kind);
    final operation = _editing ? capability.update : capability.create;
    if (operation == null || !service.capabilities.canApply) {
      _message('This profile cannot save and apply this DHCP resource.');
      return;
    }

    final values = normaliseDhcpValues(widget.kind, _values);
    final validation = validateDhcpResourceValues(
      kind: widget.kind,
      values: values,
      operation: operation,
      context: DhcpValidationContext(
        interfaces: widget.interfaces,
        servers: widget.servers,
        staticMappings: widget.staticMappings,
        addressPools: widget.addressPools,
        relayEnabled: widget.relayEnabled,
        editing: widget.resource,
      ),
    );
    if (!validation.isValid) {
      setState(() => _errors = validation.errors);
      _message(validation.summary);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_editing ? 'Save DHCP changes?' : 'Create resource?'),
        content: Text(
          widget.kind == DhcpResourceKind.server
              ? 'DHCP server changes can interrupt address assignment. The configuration will be applied after the write succeeds.'
              : 'The DHCP configuration will be applied after the write succeeds.',
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
      if (_editing) {
        await service.update(widget.resource!, _changedValues(values));
      } else {
        await service.create(widget.kind, values);
      }
      await service.apply();
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
    final original = widget.resource?.raw;
    if (original == null) return values;
    return {
      for (final entry in values.entries)
        if (!_equivalent(original[entry.key], entry.value))
          entry.key: entry.value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.dhcpManagementService;
    final capability = service?.capabilities.forKind(widget.kind);
    final operation = _editing ? capability?.update : capability?.create;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing
              ? 'Edit ${widget.kind.singularLabel}'
              : 'Add ${widget.kind.singularLabel}',
        ),
      ),
      body: service == null || operation == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This write operation is not available for the selected profile.',
                ),
              ),
            )
          : _form(operation, service.capabilities.canApply),
    );
  }

  Widget _form(PfRestOperationCapability operation, bool canApply) {
    final fields = operation.requestFields.values
        .where((field) => field.location.toLowerCase() == 'body')
        .toList(growable: false);
    final byName = {for (final field in fields) field.name: field};
    final widgets = switch (widget.kind) {
      DhcpResourceKind.server => _serverFields(byName),
      DhcpResourceKind.staticMapping => _mappingFields(byName),
      DhcpResourceKind.addressPool => _poolFields(byName),
    };
    final advanced = _advancedFields(fields);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!canApply)
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Apply operation unavailable'),
              subtitle: Text(
                'Editing is disabled because the connected schema does not report the DHCP apply endpoint.',
              ),
            ),
          ),
        ...widgets,
        if (advanced.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            leading: const Icon(Icons.tune),
            title: const Text('Additional reported fields'),
            subtitle: const Text(
              'These controls come from the connected OpenAPI schema.',
            ),
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
      ],
    );
  }

  List<Widget> _serverFields(Map<String, PfRestFieldConstraint> fields) {
    final widgets = <Widget>[_section('Interface and service')];
    widgets.add(_serverInterfaceField(fields['id'] ?? fields['interface']));
    _add(widgets, fields['enable']);

    widgets.add(_section('Primary address range'));
    _add(widgets, fields['range_from']);
    _add(widgets, fields['range_to']);

    widgets.add(_section('Client network settings'));
    for (final name in const [
      'gateway',
      'domain',
      'domainsearchlist',
      'dnsserver',
      'winsserver',
      'ntpserver',
      'defaultleasetime',
      'maxleasetime',
    ]) {
      _add(widgets, fields[name]);
    }

    widgets.add(_section('Access and behaviour'));
    for (final name in const [
      'denyunknown',
      'mac_allow',
      'mac_deny',
      'staticarp',
      'ignorebootp',
      'ignoreclientuids',
      'nonak',
      'disablepingcheck',
      'dhcpleaseinlocaltime',
      'statsgraph',
      'failover_peerip',
    ]) {
      _add(widgets, fields[name]);
    }
    return _spaced(widgets);
  }

  List<Widget> _mappingFields(Map<String, PfRestFieldConstraint> fields) {
    final widgets = <Widget>[_section('Client identity')];
    widgets.add(_parentField(fields['parent_id']));
    for (final name in const ['mac', 'ipaddr', 'hostname', 'cid', 'descr']) {
      _add(widgets, fields[name]);
    }

    widgets.add(_section('Client options'));
    for (final name in const [
      'gateway',
      'domain',
      'domainsearchlist',
      'dnsserver',
      'winsserver',
      'ntpserver',
      'defaultleasetime',
      'maxleasetime',
      'arp_table_static_entry',
    ]) {
      _add(widgets, fields[name]);
    }
    return _spaced(widgets);
  }

  List<Widget> _poolFields(Map<String, PfRestFieldConstraint> fields) {
    final widgets = <Widget>[_section('Address pool')];
    widgets.add(_parentField(fields['parent_id']));
    _add(widgets, fields['range_from']);
    _add(widgets, fields['range_to']);

    widgets.add(_section('Pool options'));
    for (final name in const [
      'gateway',
      'domain',
      'domainsearchlist',
      'dnsserver',
      'winsserver',
      'ntpserver',
      'defaultleasetime',
      'maxleasetime',
      'denyunknown',
      'mac_allow',
      'mac_deny',
      'ignorebootp',
      'ignoreclientuids',
    ]) {
      _add(widgets, fields[name]);
    }
    return _spaced(widgets);
  }

  Widget _serverInterfaceField(PfRestFieldConstraint? field) {
    final current = _text(_values['id'] ?? _values['interface']);
    final options = <String, String>{};
    for (final interface in widget.interfaces) {
      final id = interface.id?.toString().trim();
      if (id == null || id.isEmpty) continue;
      options[id] = interface.description.isEmpty
          ? id.toUpperCase()
          : '${interface.description} ($id)';
    }
    if (current.isNotEmpty) options.putIfAbsent(current, () => current);
    if (options.isEmpty || field == null) {
      return _textField(
        name: 'id',
        label: 'Interface ID',
        enabled: !_editing,
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('dhcp-server-interface-$current'),
      initialValue: current.isEmpty ? null : current,
      decoration: InputDecoration(
        labelText: 'Interface',
        errorText: _errors['id'] ?? _errors['interface'],
      ),
      items: [
        for (final entry in options.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: _editing
          ? null
          : (value) {
              setState(() {
                _values['id'] = value ?? '';
                _values['interface'] = value ?? '';
                _errors = {..._errors}
                  ..remove('id')
                  ..remove('interface');
              });
            },
    );
  }

  Widget _parentField(PfRestFieldConstraint? field) {
    final current = _text(_values['parent_id']);
    final options = <String, String>{
      for (final server in widget.servers)
        if (server.interfaceId.isNotEmpty)
          server.interfaceId: _serverLabel(server.interfaceId),
    };
    if (current.isNotEmpty) options.putIfAbsent(current, () => current);
    if (options.isEmpty || field == null) {
      return _textField(
        name: 'parent_id',
        label: 'DHCP server interface',
        enabled: !_editing,
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('dhcp-parent-$current'),
      initialValue: current.isEmpty ? null : current,
      decoration: InputDecoration(
        labelText: 'DHCP server interface',
        errorText: _errors['parent_id'],
      ),
      items: [
        for (final entry in options.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: _editing
          ? null
          : (value) => _setValue('parent_id', value ?? ''),
    );
  }

  String _serverLabel(String id) {
    for (final interface in widget.interfaces) {
      if (interface.id?.toString() == id) {
        return interface.description.isEmpty
            ? id.toUpperCase()
            : '${interface.description} ($id)';
      }
    }
    return id.toUpperCase();
  }

  void _add(
    List<Widget> widgets,
    PfRestFieldConstraint? field, {
    bool enabled = true,
  }) {
    if (field != null) widgets.add(_field(field, enabled: enabled));
  }

  Widget _field(
    PfRestFieldConstraint field, {
    bool enabled = true,
  }) {
    final name = field.name;
    final value = _values[name];
    if (field.type == 'boolean' || value is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_label(name)),
        subtitle: _errorText(name),
        value: _boolean(value),
        onChanged: enabled ? (selected) => _setValue(name, selected) : null,
      );
    }

    final allowed = field.allowedValues
        .map((item) => item?.toString())
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (allowed.isNotEmpty) {
      final current = value?.toString();
      final options = <String>{
        ...allowed,
        if (current != null && current.isNotEmpty) current,
      };
      return DropdownButtonFormField<String>(
        key: ValueKey('dhcp-field-$name-$current'),
        initialValue: current == null || current.isEmpty ? null : current,
        decoration: InputDecoration(
          labelText: _label(name),
          errorText: _errors[name],
        ),
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option,
              child: Text(_displayValue(option)),
            ),
        ],
        onChanged: enabled ? (selected) => _setValue(name, selected) : null,
      );
    }

    final isList = field.type == 'array' || value is List;
    return TextFormField(
      key: ValueKey('dhcp-field-$name-${value?.hashCode ?? 0}'),
      initialValue: isList && value is List
          ? value.map((item) => item.toString()).join(', ')
          : value?.toString() ?? '',
      enabled: enabled,
      keyboardType: field.type == 'integer' || field.type == 'number'
          ? TextInputType.number
          : TextInputType.text,
      maxLines: isList ? 2 : 1,
      decoration: InputDecoration(
        labelText: _label(name),
        errorText: _errors[name],
        helperText: isList ? 'Separate values with commas.' : null,
      ),
      onChanged: (text) {
        final parsed = isList
            ? text
                .split(RegExp(r'[,;\n]'))
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
            : field.type == 'integer'
                ? int.tryParse(text) ?? text
                : field.type == 'number'
                    ? num.tryParse(text) ?? text
                    : text;
        _setValue(name, parsed);
      },
    );
  }

  Widget _textField({
    required String name,
    required String label,
    bool enabled = true,
  }) {
    return TextFormField(
      initialValue: _text(_values[name]),
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        errorText: _errors[name],
      ),
      onChanged: (value) => _setValue(name, value),
    );
  }

  List<PfRestFieldConstraint> _advancedFields(
    List<PfRestFieldConstraint> fields,
  ) {
    const common = {
      'id',
      'parent_id',
      'interface',
      'enable',
      'range_from',
      'range_to',
      'gateway',
      'domain',
      'domainsearchlist',
      'dnsserver',
      'winsserver',
      'ntpserver',
      'defaultleasetime',
      'maxleasetime',
      'denyunknown',
      'mac_allow',
      'mac_deny',
      'staticarp',
      'ignorebootp',
      'ignoreclientuids',
      'nonak',
      'disablepingcheck',
      'dhcpleaseinlocaltime',
      'statsgraph',
      'failover_peerip',
      'mac',
      'ipaddr',
      'hostname',
      'cid',
      'descr',
      'arp_table_static_entry',
      'pool',
      'numberoptions',
      'staticmap',
    };
    return fields
        .where((field) => !common.contains(field.name))
        .toList(growable: false);
  }

  void _setValue(String name, Object? value) {
    setState(() {
      _values[name] = value;
      _errors = {..._errors}..remove(name);
    });
  }

  Widget? _errorText(String name) {
    final error = _errors[name];
    if (error == null) return null;
    return Text(
      error,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  List<Widget> _spaced(List<Widget> widgets) {
    final result = <Widget>[];
    for (final widget in widgets) {
      if (result.isNotEmpty) result.add(const SizedBox(height: 12));
      result.add(widget);
    }
    return result;
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

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

String _text(Object? value) => value?.toString().trim() ?? '';

bool _boolean(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
}

String _label(String name) {
  return name
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

String _displayValue(String value) {
  if (value.isEmpty) return 'Automatic';
  if (value == 'none') return 'None';
  return _label(value);
}
