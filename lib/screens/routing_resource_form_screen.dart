import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/interface_management.dart';
import '../models/pfrest_capabilities.dart';
import '../models/routing_management.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/routing_management_validation.dart';

class RoutingResourceFormScreen extends StatefulWidget {
  const RoutingResourceFormScreen({
    super.key,
    required this.kind,
    required this.gateways,
    required this.gatewayGroups,
    required this.availableInterfaces,
    this.resource,
    this.onPermissionDenied,
  });

  final RoutingResourceKind kind;
  final ManagedRoutingResource? resource;
  final List<ManagedRoutingResource> gateways;
  final List<ManagedRoutingResource> gatewayGroups;
  final List<AvailableInterface> availableInterfaces;
  final VoidCallback? onPermissionDenied;

  @override
  State<RoutingResourceFormScreen> createState() =>
      _RoutingResourceFormScreenState();
}

class _RoutingResourceFormScreenState
    extends State<RoutingResourceFormScreen> {
  late Map<String, dynamic> _values;
  Map<String, String> _errors = const {};
  bool _saving = false;

  bool get _editing => widget.resource != null;

  Map<String, String> get _gatewayFamilies {
    return {
      for (final resource in [...widget.gateways, ...widget.gatewayGroups])
        if (resource.displayName.isNotEmpty && resource.ipProtocol.isNotEmpty)
          resource.displayName: resource.ipProtocol,
    };
  }

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.resource?.raw ?? const {});
    switch (widget.kind) {
      case RoutingResourceKind.gateway:
        _values.putIfAbsent('disabled', () => false);
        _values.putIfAbsent('ipprotocol', () => 'inet');
        _values.putIfAbsent('monitor_disable', () => false);
        _values.putIfAbsent('action_disable', () => false);
        _values.putIfAbsent('force_down', () => false);
        _values.putIfAbsent('dpinger_dont_add_static_route', () => false);
        _values.putIfAbsent('nonlocalgateway', () => true);
        _values.putIfAbsent('weight', () => 1);
        _values.putIfAbsent('data_payload', () => 1);
        _values.putIfAbsent('latencylow', () => 200);
        _values.putIfAbsent('latencyhigh', () => 500);
        _values.putIfAbsent('losslow', () => 10);
        _values.putIfAbsent('losshigh', () => 20);
        _values.putIfAbsent('interval', () => 500);
        _values.putIfAbsent('loss_interval', () => 2000);
        _values.putIfAbsent('time_period', () => 60000);
        _values.putIfAbsent('alert_interval', () => 1000);
      case RoutingResourceKind.gatewayGroup:
        _values.putIfAbsent('trigger', () => 'down');
        _values.putIfAbsent('priorities', () => <Map<String, dynamic>>[]);
      case RoutingResourceKind.staticRoute:
        _values.putIfAbsent('disabled', () => false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.routingManagementService;
    if (!session.connected || service == null) return;

    final capability = service.capabilities.forKind(widget.kind);
    final operation = _editing ? capability.update : capability.create;
    if (operation == null || !service.capabilities.canApply) {
      _message('This profile cannot save and apply this routing resource.');
      return;
    }

    final values = normaliseRoutingValues(widget.kind, _values);
    final validation = validateRoutingValues(
      kind: widget.kind,
      values: values,
      operation: operation,
      gatewayFamilies: _gatewayFamilies,
    );
    if (!validation.isValid) {
      setState(() => _errors = validation.errors);
      _message(validation.summary);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_editing ? 'Save routing changes?' : 'Create resource?'),
        content: Text(
          widget.kind == RoutingResourceKind.gateway
              ? 'Gateway changes can interrupt traffic or policy routing. The configuration will be applied immediately after the write succeeds.'
              : 'The routing configuration will be applied immediately after the write succeeds.',
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
    final service = session.routingManagementService;
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
      RoutingResourceKind.gateway => _gatewayFields(byName),
      RoutingResourceKind.gatewayGroup => _gatewayGroupFields(byName),
      RoutingResourceKind.staticRoute => _staticRouteFields(byName),
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!canApply)
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Apply operation unavailable'),
              subtitle: Text(
                'Editing is disabled because the connected schema does not report the routing apply endpoint.',
              ),
            ),
          ),
        ...widgets,
        if (_advancedFields(fields).isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            leading: const Icon(Icons.tune),
            title: const Text('Additional reported fields'),
            subtitle: const Text(
              'These controls are generated from the connected OpenAPI schema.',
            ),
            children: [
              for (final field in _advancedFields(fields))
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

  List<Widget> _gatewayFields(Map<String, PfRestFieldConstraint> fields) {
    final widgets = <Widget>[_section('Gateway')];
    _add(widgets, fields['name'], enabled: !_editing);
    _add(widgets, fields['descr']);
    _add(widgets, fields['disabled']);
    _add(widgets, fields['ipprotocol']);
    final interface = fields['interface'];
    if (interface != null) widgets.add(_interfaceField(interface));
    _add(widgets, fields['gateway']);

    widgets.add(_section('Monitoring'));
    _add(widgets, fields['monitor_disable']);
    if (!_boolean(_values['monitor_disable'])) {
      _add(widgets, fields['monitor']);
    }
    _add(widgets, fields['action_disable']);
    _add(widgets, fields['force_down']);
    _add(widgets, fields['dpinger_dont_add_static_route']);
    _add(widgets, fields['gw_down_kill_states']);

    widgets.add(_section('Advanced gateway settings'));
    for (final name in const [
      'nonlocalgateway',
      'weight',
      'data_payload',
      'latencylow',
      'latencyhigh',
      'losslow',
      'losshigh',
      'interval',
      'loss_interval',
      'time_period',
      'alert_interval',
    ]) {
      _add(widgets, fields[name]);
    }
    return _spaced(widgets);
  }

  List<Widget> _gatewayGroupFields(
    Map<String, PfRestFieldConstraint> fields,
  ) {
    final widgets = <Widget>[_section('Gateway group')];
    _add(widgets, fields['name'], enabled: !_editing);
    _add(widgets, fields['descr']);
    _add(widgets, fields['trigger']);
    if (fields['priorities'] != null) {
      widgets.add(_priorityEditor(fields['priorities']!));
    }
    return _spaced(widgets);
  }

  List<Widget> _staticRouteFields(
    Map<String, PfRestFieldConstraint> fields,
  ) {
    final widgets = <Widget>[_section('Static route')];
    _add(widgets, fields['network']);
    final gateway = fields['gateway'];
    if (gateway != null) widgets.add(_gatewayChoice(gateway));
    _add(widgets, fields['descr']);
    _add(widgets, fields['disabled']);
    return _spaced(widgets);
  }

  void _add(
    List<Widget> widgets,
    PfRestFieldConstraint? field, {
    bool enabled = true,
  }) {
    if (field != null) widgets.add(_field(field, enabled: enabled));
  }

  Widget _priorityEditor(PfRestFieldConstraint field) {
    final current = _priorityValues;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Gateway priorities',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: widget.gateways.isEmpty ? null : _addPriority,
              icon: const Icon(Icons.add),
              label: const Text('Add gateway'),
            ),
          ],
        ),
        if (_errors[field.name] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _errors[field.name]!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (widget.gateways.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('No gateways available'),
              subtitle: Text('Create a gateway before creating a gateway group.'),
            ),
          ),
        for (var index = 0; index < current.length; index++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(
                            'priority-gateway-$index-${current[index]['gateway']}',
                          ),
                          initialValue: _text(current[index]['gateway']).isEmpty
                              ? null
                              : _text(current[index]['gateway']),
                          decoration:
                              const InputDecoration(labelText: 'Gateway'),
                          items: [
                            for (final gateway in widget.gateways)
                              DropdownMenuItem(
                                value: gateway.displayName,
                                child: Text(gateway.displayName),
                              ),
                          ],
                          onChanged: (value) =>
                              _updatePriority(index, 'gateway', value),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove gateway',
                        onPressed: () => _removePriority(index),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey(
                            'priority-tier-$index-${current[index]['tier']}',
                          ),
                          initialValue: _integer(current[index]['tier']) ?? 1,
                          decoration: const InputDecoration(labelText: 'Tier'),
                          items: [
                            for (var tier = 1; tier <= 5; tier++)
                              DropdownMenuItem(
                                value: tier,
                                child: Text('Tier $tier'),
                              ),
                          ],
                          onChanged: (value) =>
                              _updatePriority(index, 'tier', value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey(
                            'priority-vip-$index-${current[index]['virtual_ip']}',
                          ),
                          initialValue:
                              _text(current[index]['virtual_ip']).isEmpty
                                  ? 'address'
                                  : _text(current[index]['virtual_ip']),
                          decoration: const InputDecoration(
                            labelText: 'Virtual IP',
                            helperText: 'Use address for the interface IP.',
                          ),
                          onChanged: (value) =>
                              _updatePriority(index, 'virtual_ip', value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> get _priorityValues {
    final value = _values['priorities'];
    if (value is! List) return const [];
    return value.whereType<Map>().map((entry) {
      return entry.map((key, item) => MapEntry(key.toString(), item));
    }).toList(growable: false);
  }

  void _addPriority() {
    final values = _priorityValues.map(Map<String, dynamic>.from).toList();
    final used = values.map((item) => _text(item['gateway'])).toSet();
    final available = widget.gateways
        .map((gateway) => gateway.displayName)
        .where((name) => !used.contains(name));
    values.add({
      'gateway': available.isEmpty ? widget.gateways.first.displayName : available.first,
      'tier': 1,
      'virtual_ip': 'address',
    });
    _setValue('priorities', values);
  }

  void _removePriority(int index) {
    final values = _priorityValues.map(Map<String, dynamic>.from).toList();
    values.removeAt(index);
    _setValue('priorities', values);
  }

  void _updatePriority(int index, String name, Object? value) {
    final values = _priorityValues.map(Map<String, dynamic>.from).toList();
    values[index][name] = value;
    _setValue('priorities', values);
  }

  Widget _gatewayChoice(PfRestFieldConstraint field) {
    final current = _text(_values[field.name]);
    final names = <String>{
      if (current.isNotEmpty) current,
      for (final item in widget.gateways) item.displayName,
      for (final item in widget.gatewayGroups) item.displayName,
    }.toList(growable: false)
      ..sort();
    if (names.isEmpty) return _field(field);
    return DropdownButtonFormField<String>(
      key: ValueKey('routing-gateway-choice-$current'),
      initialValue: current.isEmpty ? null : current,
      decoration: InputDecoration(
        labelText: _label(field.name),
        errorText: _errors[field.name],
      ),
      items: [
        for (final name in names)
          DropdownMenuItem(value: name, child: Text(name)),
      ],
      onChanged: (value) => _setValue(field.name, value),
    );
  }

  Widget _interfaceField(PfRestFieldConstraint field) {
    final current = _text(_values[field.name]);
    final names = <String>{
      if (current.isNotEmpty) current,
      for (final item in widget.availableInterfaces) item.name,
    }.toList(growable: false)
      ..sort();
    if (names.isEmpty) return _field(field);
    return DropdownButtonFormField<String>(
      key: ValueKey('routing-interface-choice-$current'),
      initialValue: current.isEmpty ? null : current,
      decoration: InputDecoration(
        labelText: _label(field.name),
        errorText: _errors[field.name],
      ),
      items: [
        for (final name in names)
          DropdownMenuItem(value: name, child: Text(_interfaceLabel(name))),
      ],
      onChanged: (value) => _setValue(field.name, value),
    );
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
      final choices = <String>{
        ...allowed,
        if (current != null) current,
      };
      return DropdownButtonFormField<String>(
        key: ValueKey('routing-field-$name-$current'),
        initialValue: current == null || current.isEmpty ? null : current,
        decoration: InputDecoration(
          labelText: _label(name),
          errorText: _errors[name],
        ),
        items: [
          for (final option in choices)
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
      key: ValueKey('routing-field-$name-${value?.hashCode ?? 0}'),
      initialValue:
          isList && value is List ? value.join(', ') : value?.toString() ?? '',
      enabled: enabled,
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
            ? text
                .split(',')
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

  List<PfRestFieldConstraint> _advancedFields(
    List<PfRestFieldConstraint> fields,
  ) {
    const common = {
      'id',
      'name',
      'descr',
      'disabled',
      'ipprotocol',
      'interface',
      'gateway',
      'monitor_disable',
      'monitor',
      'action_disable',
      'force_down',
      'dpinger_dont_add_static_route',
      'gw_down_kill_states',
      'nonlocalgateway',
      'weight',
      'data_payload',
      'latencylow',
      'latencyhigh',
      'losslow',
      'losshigh',
      'interval',
      'loss_interval',
      'time_period',
      'alert_interval',
      'trigger',
      'priorities',
      'network',
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

  String _interfaceLabel(String name) {
    for (final item in widget.availableInterfaces) {
      if (item.name == name && item.description.isNotEmpty) {
        return '$name — ${item.description}';
      }
    }
    return name;
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

bool _boolean(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
}

int? _integer(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

String _text(Object? value) => value?.toString().trim() ?? '';

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
  if (value == '-') return 'None';
  return _label(value);
}
