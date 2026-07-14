import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dns_management.dart';
import '../models/pfrest_capabilities.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/dns_management_validation.dart';

class DnsResourceFormScreen extends StatefulWidget {
  const DnsResourceFormScreen({
    super.key,
    required this.kind,
    required this.resources,
    this.resource,
    this.initialValues = const {},
    this.onPermissionDenied,
  });

  final DnsResourceKind kind;
  final ManagedDnsResource? resource;
  final List<ManagedDnsResource> resources;
  final Map<String, dynamic> initialValues;
  final VoidCallback? onPermissionDenied;

  @override
  State<DnsResourceFormScreen> createState() =>
      _DnsResourceFormScreenState();
}

class _DnsResourceFormScreenState extends State<DnsResourceFormScreen> {
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
    if (widget.kind == DnsResourceKind.resolverHostOverride) {
      _values.putIfAbsent('ip', () => <String>[]);
      _values.putIfAbsent('aliases', () => <Map<String, dynamic>>[]);
    } else if (widget.kind == DnsResourceKind.forwarderHostOverride) {
      _values.putIfAbsent('ip', () => '');
      _values.putIfAbsent('aliases', () => <Map<String, dynamic>>[]);
    } else if (widget.kind == DnsResourceKind.resolverDomainOverride) {
      _values.putIfAbsent('forward_tls_upstream', () => false);
      _values.putIfAbsent('tls_hostname', () => '');
    } else if (widget.kind == DnsResourceKind.resolverAccessList) {
      _values.putIfAbsent('action', () => 'allow');
      _values.putIfAbsent('networks', () => <Map<String, dynamic>>[]);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.dnsManagementService;
    if (!session.connected || service == null) return;

    final capability = service.capabilities.forKind(widget.kind);
    final operation = _editing ? capability.update : capability.create;
    final serviceCapabilities =
        service.capabilities.forService(widget.kind.service);
    if (operation == null || !serviceCapabilities.canApply) {
      _message('This profile cannot save and apply this DNS resource.');
      return;
    }

    final values = normaliseDnsValues(_values);
    final validation = validateDnsResource(
      kind: widget.kind,
      values: values,
      operation: operation,
      context: DnsValidationContext(
        resources: widget.resources,
        editing: widget.resource,
      ),
    );
    if (!validation.isValid) {
      setState(() => _errors = validation.errors);
      _message(validation.summary);
      return;
    }

    final changes = _changedValues(values);
    if (_editing && changes.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_editing ? 'Save DNS changes?' : 'Create DNS resource?'),
        content: Text(
          'The ${widget.kind.service.label} configuration will be applied after the write succeeds. Invalid overrides or access rules can disrupt name resolution.',
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
        await service.update(widget.resource!, changes);
      } else {
        await service.create(widget.kind, values);
      }
      await service.apply(widget.kind.service);
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
    final service = session.dnsManagementService;
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
          : _form(
              operation,
              service.capabilities.forService(widget.kind.service).canApply,
            ),
    );
  }

  Widget _form(PfRestOperationCapability operation, bool canApply) {
    final fields = operation.requestFields.values
        .where((field) => field.location.toLowerCase() == 'body')
        .toList(growable: false);
    final byName = {for (final field in fields) field.name: field};
    final widgets = <Widget>[];

    if (widget.kind.child) {
      widgets.add(_parentField(byName['parent_id']));
    }
    if (widget.kind == DnsResourceKind.resolverHostOverride ||
        widget.kind == DnsResourceKind.forwarderHostOverride) {
      widgets.add(_section('Host override'));
      _add(widgets, byName['host']);
      _add(widgets, byName['domain']);
      final ipField = byName['ip'];
      if (ipField != null) widgets.add(_ipField(ipField));
      _add(widgets, byName['descr'] ?? byName['description']);
      final aliases = byName['aliases'];
      if (aliases != null) widgets.add(_aliasEditor(aliases));
    } else if (widget.kind == DnsResourceKind.resolverDomainOverride) {
      widgets.add(_section('Domain override'));
      _add(widgets, byName['domain']);
      _add(widgets, byName['ip']);
      _add(widgets, byName['forward_tls_upstream']);
      if (_boolean(_values['forward_tls_upstream'])) {
        _add(widgets, byName['tls_hostname']);
      }
      _add(widgets, byName['descr'] ?? byName['description']);
    } else if (widget.kind == DnsResourceKind.resolverAccessList) {
      widgets.add(_section('Access list'));
      _add(widgets, byName['name']);
      _add(widgets, byName['action']);
      _add(widgets, byName['description'] ?? byName['descr']);
      final networks = byName['networks'];
      if (networks != null) widgets.add(_networkEditor(networks));
    } else if (widget.kind == DnsResourceKind.resolverHostAlias ||
        widget.kind == DnsResourceKind.forwarderHostAlias) {
      widgets.add(_section('Host alias'));
      _add(widgets, byName['host']);
      _add(widgets, byName['domain']);
      _add(widgets, byName['descr'] ?? byName['description']);
    } else {
      widgets.add(_section('Access-list network'));
      _add(widgets, byName['network']);
      _add(widgets, byName['mask']);
      _add(widgets, byName['description'] ?? byName['descr']);
    }

    final advanced = fields
        .where((field) => !_knownFields.contains(field.name))
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!canApply)
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Apply operation unavailable'),
              subtitle: Text(
                'Editing is disabled because the connected schema does not report the matching DNS apply endpoint.',
              ),
            ),
          ),
        ..._spaced(widgets),
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
      ],
    );
  }

  Widget _parentField(PfRestFieldConstraint? field) {
    final current = _text(_values['parent_id']);
    final parentKind = switch (widget.kind) {
      DnsResourceKind.resolverHostAlias =>
        DnsResourceKind.resolverHostOverride,
      DnsResourceKind.forwarderHostAlias =>
        DnsResourceKind.forwarderHostOverride,
      DnsResourceKind.resolverAccessListNetwork =>
        DnsResourceKind.resolverAccessList,
      _ => null,
    };
    final parents = widget.resources
        .where((resource) => resource.kind == parentKind && resource.id != null)
        .toList(growable: false);
    if (field == null || parents.isEmpty) {
      return TextFormField(
        initialValue: current,
        enabled: !_editing,
        decoration: InputDecoration(
          labelText: 'Parent resource ID',
          errorText: _errors['parent_id'],
        ),
        onChanged: (value) => _setValue('parent_id', value),
      );
    }
    final choices = <String, String>{
      for (final parent in parents)
        parent.id.toString(): parent.displayName,
      if (current.isNotEmpty) current: current,
    };
    return DropdownButtonFormField<String>(
      key: ValueKey('dns-parent-$current'),
      initialValue: current.isEmpty ? null : current,
      decoration: InputDecoration(
        labelText: 'Parent ${parentKind?.singularLabel ?? 'resource'}',
        errorText: _errors['parent_id'],
      ),
      items: [
        for (final entry in choices.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: _editing
          ? null
          : (value) => _setValue('parent_id', value ?? ''),
    );
  }

  Widget _ipField(PfRestFieldConstraint field) {
    final resolver = widget.kind == DnsResourceKind.resolverHostOverride;
    if (!resolver) return _field(field);
    final values = _stringList(_values['ip']);
    return TextFormField(
      key: ValueKey('dns-ip-list-${values.join('|')}'),
      initialValue: values.join(', '),
      maxLines: 2,
      decoration: InputDecoration(
        labelText: 'IP addresses',
        errorText: _errors['ip'],
        helperText: 'Separate IPv4 or IPv6 addresses with commas.',
      ),
      onChanged: (value) => _setValue('ip', _splitValues(value)),
    );
  }

  Widget _aliasEditor(PfRestFieldConstraint field) {
    final aliases = _mapList(_values['aliases']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Aliases',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                final next = aliases.map(Map<String, dynamic>.from).toList();
                next.add({'host': '', 'domain': '', 'descr': ''});
                _setValue('aliases', next);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add alias'),
            ),
          ],
        ),
        if (_errors[field.name] != null)
          Text(
            _errors[field.name]!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (var index = 0; index < aliases.length; index++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('alias-host-$index-${aliases[index]['host']}'),
                          initialValue: _text(aliases[index]['host']),
                          decoration: const InputDecoration(labelText: 'Host'),
                          onChanged: (value) =>
                              _updateMapList('aliases', index, 'host', value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey(
                            'alias-domain-$index-${aliases[index]['domain']}',
                          ),
                          initialValue: _text(aliases[index]['domain']),
                          decoration: const InputDecoration(labelText: 'Domain'),
                          onChanged: (value) =>
                              _updateMapList('aliases', index, 'domain', value),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove alias',
                        onPressed: () => _removeMapList('aliases', index),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: ValueKey(
                      'alias-description-$index-${aliases[index]['descr'] ?? aliases[index]['description']}',
                    ),
                    initialValue: _text(
                      aliases[index]['descr'] ?? aliases[index]['description'],
                    ),
                    decoration: const InputDecoration(labelText: 'Description'),
                    onChanged: (value) =>
                        _updateMapList('aliases', index, 'descr', value),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _networkEditor(PfRestFieldConstraint field) {
    final networks = _mapList(_values['networks']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Networks',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                final next = networks.map(Map<String, dynamic>.from).toList();
                next.add({'network': '', 'mask': 24, 'description': ''});
                _setValue('networks', next);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add network'),
            ),
          ],
        ),
        if (_errors[field.name] != null)
          Text(
            _errors[field.name]!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (var index = 0; index < networks.length; index++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          key: ValueKey(
                            'network-address-$index-${networks[index]['network']}',
                          ),
                          initialValue: _text(networks[index]['network']),
                          decoration: const InputDecoration(labelText: 'Network'),
                          onChanged: (value) =>
                              _updateMapList('networks', index, 'network', value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey(
                            'network-mask-$index-${networks[index]['mask']}',
                          ),
                          initialValue: _text(networks[index]['mask']),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Prefix'),
                          onChanged: (value) => _updateMapList(
                            'networks',
                            index,
                            'mask',
                            int.tryParse(value) ?? value,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove network',
                        onPressed: () => _removeMapList('networks', index),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: ValueKey(
                      'network-description-$index-${networks[index]['description']}',
                    ),
                    initialValue: _text(networks[index]['description']),
                    decoration: const InputDecoration(labelText: 'Description'),
                    onChanged: (value) => _updateMapList(
                      'networks',
                      index,
                      'description',
                      value,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _updateMapList(
    String listName,
    int index,
    String field,
    Object? value,
  ) {
    final next = _mapList(_values[listName])
        .map(Map<String, dynamic>.from)
        .toList();
    next[index][field] = value;
    _setValue(listName, next);
  }

  void _removeMapList(String listName, int index) {
    final next = _mapList(_values[listName])
        .map(Map<String, dynamic>.from)
        .toList();
    next.removeAt(index);
    _setValue(listName, next);
  }

  void _add(
    List<Widget> widgets,
    PfRestFieldConstraint? field,
  ) {
    if (field != null) widgets.add(_field(field));
  }

  Widget _field(PfRestFieldConstraint field) {
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
        key: ValueKey('dns-field-$name-$current'),
        initialValue: current == null || current.isEmpty ? null : current,
        decoration: InputDecoration(
          labelText: _label(name),
          errorText: _errors[name],
        ),
        items: [
          for (final option in allowed)
            DropdownMenuItem(value: option, child: Text(_label(option))),
        ],
        onChanged: (selected) => _setValue(name, selected),
      );
    }

    final isList = field.type == 'array' || value is List;
    return TextFormField(
      key: ValueKey('dns-field-$name-${value?.hashCode ?? 0}'),
      initialValue: isList && value is List
          ? value.map((item) => item.toString()).join(', ')
          : value?.toString() ?? '',
      maxLines: isList ? 2 : 1,
      keyboardType: field.type == 'integer' || field.type == 'number'
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: _label(name),
        errorText: _errors[name],
        helperText: isList ? 'Separate values with commas.' : null,
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

  Widget _section(String label) => Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
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
  'id',
  'parent_id',
  'host',
  'domain',
  'ip',
  'descr',
  'description',
  'aliases',
  'forward_tls_upstream',
  'tls_hostname',
  'name',
  'action',
  'networks',
  'network',
  'mask',
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

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) {
    return item.map((key, child) => MapEntry(key.toString(), child));
  }).toList(growable: false);
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
  final text = _text(value);
  return text.isEmpty ? const [] : [text];
}

String _text(Object? value) => value?.toString().trim() ?? '';

bool _boolean(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
}

String _label(String value) {
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
