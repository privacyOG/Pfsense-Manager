import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/interface_management.dart';
import '../models/pfrest_capabilities.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/interface_management_validation.dart';
import '../widgets/slide_to_confirm.dart';

class InterfaceResourceFormScreen extends StatefulWidget {
  const InterfaceResourceFormScreen({
    super.key,
    required this.kind,
    required this.availableInterfaces,
    this.resource,
    this.onPermissionDenied,
  });

  final InterfaceResourceKind kind;
  final ManagedInterfaceResource? resource;
  final List<AvailableInterface> availableInterfaces;
  final VoidCallback? onPermissionDenied;

  @override
  State<InterfaceResourceFormScreen> createState() =>
      _InterfaceResourceFormScreenState();
}

class _InterfaceResourceFormScreenState
    extends State<InterfaceResourceFormScreen> {
  late Map<String, dynamic> _values;
  Map<String, String> _errors = const {};
  bool _saving = false;

  bool get _editing => widget.resource != null;

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.resource?.raw ?? const {});
    _values.putIfAbsent('enable', () => true);
    if (widget.kind.isAssigned) {
      _values.putIfAbsent('typev4', () => 'none');
      _values.putIfAbsent('typev6', () => 'none');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.interfaceManagementService;
    if (!session.connected || service == null) return;

    final resourceCapability = service.capabilities.forKind(widget.kind);
    final operation =
        _editing ? resourceCapability.update : resourceCapability.create;
    if (operation == null || !service.capabilities.canApply) {
      _showMessage(
        'This profile cannot save and apply this interface resource.',
      );
      return;
    }

    final values = normaliseInterfaceValues(widget.kind, _values);
    final validation = validateInterfaceValues(
      kind: widget.kind,
      values: values,
      operation: operation,
    );
    if (!validation.isValid) {
      setState(() => _errors = validation.errors);
      _showMessage(validation.summary);
      return;
    }

    final changes = _changedValues(values);
    final risk = interfaceChangeRisk(
      original: widget.resource,
      changes: changes,
      profile: session.selectedProfile,
    );
    final confirmed = await _confirm(risk);
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      if (_editing) {
        await service.update(widget.resource!, changes);
      } else {
        await service.create(widget.kind, values);
      }
      await service.apply();

      if (!mounted) return;
      if (risk == InterfaceChangeRisk.managementPath) {
        await session.disconnect();
        if (!mounted) return;
        _showMessage(
          'The management interface change was applied. The current session was closed because the firewall address may have changed.',
          duration: const Duration(seconds: 8),
        );
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (error.isPermissionError) widget.onPermissionDenied?.call();
      if (mounted) _showMessage(error.toString());
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirm(InterfaceChangeRisk risk) {
    final name = widget.resource?.displayName ?? widget.kind.singularLabel;
    if (risk == InterfaceChangeRisk.managementPath) {
      return showSlideToConfirmSheet(
        context: context,
        title: 'Apply management interface change?',
        body:
            'This interface currently matches the selected firewall address. Applying the change may immediately disconnect this device and require editing the profile before reconnecting.',
        slideLabel: 'Slide to save and apply',
        icon: Icons.warning_amber_rounded,
      );
    }
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _editing ? 'Save and apply changes?' : 'Create and apply $name?',
        ),
        content: Text(
          risk == InterfaceChangeRisk.connectivity
              ? 'This change affects interface connectivity. Active traffic may be interrupted while pfSense applies the new configuration.'
              : 'The configuration will be written and applied immediately.',
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
  }

  Map<String, dynamic> _changedValues(Map<String, dynamic> values) {
    final original = widget.resource?.raw;
    if (original == null) return values;
    return <String, dynamic>{
      for (final entry in values.entries)
        if (!_equivalent(original[entry.key], entry.value))
          entry.key: entry.value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.interfaceManagementService;
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
          : _buildForm(service, operation),
    );
  }

  Widget _buildForm(
    dynamic service,
    PfRestOperationCapability operation,
  ) {
    final fields = operation.requestFields.values
        .where((field) => field.location.toLowerCase() == 'body')
        .toList(growable: false);
    final canApply = service.capabilities.canApply == true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!canApply)
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Apply operation unavailable'),
              subtitle: Text(
                'Editing is disabled because this installation does not report the interface apply endpoint.',
              ),
            ),
          ),
        if (widget.kind.isAssigned)
          ..._assignedFields(fields)
        else
          ..._virtualFields(fields),
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

  List<Widget> _assignedFields(List<PfRestFieldConstraint> fields) {
    final byName = {for (final field in fields) field.name: field};
    final widgets = <Widget>[
      _section('Assignment'),
      if (byName['if'] != null) _interfaceField(byName['if']!),
      if (byName['enable'] != null) _field(byName['enable']!),
      if (byName['descr'] != null) _field(byName['descr']!),
      if (byName['mtu'] != null) _field(byName['mtu']!),
      if (byName['mss'] != null) _field(byName['mss']!),
      _section('IPv4'),
      if (byName['typev4'] != null) _field(byName['typev4']!),
    ];

    final typev4 = _text(_values['typev4']).toLowerCase();
    if (typev4 == 'static') {
      _appendFields(widgets, byName, const ['ipaddr', 'subnet', 'gateway']);
    } else if (typev4 == 'dhcp') {
      _appendFields(
        widgets,
        byName,
        const ['dhcphostname', 'alias_address', 'alias_subnet'],
      );
    }

    widgets.add(_section('IPv6'));
    if (byName['typev6'] != null) widgets.add(_field(byName['typev6']!));
    final typev6 = _text(_values['typev6']).toLowerCase();
    if (typev6 == 'static') {
      _appendFields(
        widgets,
        byName,
        const ['ipaddrv6', 'subnetv6', 'gatewayv6'],
      );
    } else if (typev6 == 'track6') {
      final track = byName['track6_interface'];
      if (track != null) widgets.add(_interfaceField(track));
      final prefix = byName['track6_prefix_id_hex'];
      if (prefix != null) widgets.add(_field(prefix));
    }
    return _spaced(widgets);
  }

  List<Widget> _virtualFields(List<PfRestFieldConstraint> fields) {
    final preferred = switch (widget.kind) {
      InterfaceResourceKind.vlan =>
        const ['if', 'parent', 'tag', 'pcp', 'descr'],
      InterfaceResourceKind.bridge => const ['members', 'descr'],
      InterfaceResourceKind.lagg => const ['members', 'laggproto', 'descr'],
      InterfaceResourceKind.gre || InterfaceResourceKind.gif => const [
          'if',
          'parent',
          'local',
          'remote',
          'local_addr',
          'remote_addr',
          'descr',
        ],
      InterfaceResourceKind.assigned => const <String>[],
    };
    final byName = {for (final field in fields) field.name: field};
    final widgets = <Widget>[_section(widget.kind.label)];
    for (final name in preferred) {
      final field = byName[name];
      if (field == null) continue;
      widgets.add(
        const {'if', 'parent'}.contains(name)
            ? _interfaceField(field)
            : _field(field),
      );
    }
    return _spaced(widgets);
  }

  void _appendFields(
    List<Widget> widgets,
    Map<String, PfRestFieldConstraint> byName,
    List<String> names,
  ) {
    for (final name in names) {
      final field = byName[name];
      if (field != null) widgets.add(_field(field));
    }
  }

  List<PfRestFieldConstraint> _advancedFields(
    List<PfRestFieldConstraint> fields,
  ) {
    const common = {
      'id',
      'if',
      'parent',
      'enable',
      'descr',
      'mtu',
      'mss',
      'typev4',
      'ipaddr',
      'subnet',
      'gateway',
      'dhcphostname',
      'alias_address',
      'alias_subnet',
      'typev6',
      'ipaddrv6',
      'subnetv6',
      'gatewayv6',
      'track6_interface',
      'track6_prefix_id_hex',
      'tag',
      'pcp',
      'members',
      'laggproto',
      'local',
      'remote',
      'local_addr',
      'remote_addr',
    };
    return fields
        .where((field) => !common.contains(field.name))
        .toList(growable: false);
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
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (allowed.isNotEmpty) {
      final current = value?.toString();
      final choices = <String>{
        ...allowed,
        if (current != null && current.isNotEmpty) current,
      };
      return DropdownButtonFormField<String>(
        key: ValueKey('interface-field-$name-$current'),
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
        onChanged: (selected) => _setValue(name, selected),
      );
    }

    final isList = field.type == 'array' || value is List;
    return TextFormField(
      key: ValueKey('interface-field-$name-${value?.hashCode ?? 0}'),
      initialValue:
          isList && value is List ? value.join(', ') : value?.toString() ?? '',
      obscureText: name.toLowerCase().contains('password'),
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

  Widget _interfaceField(PfRestFieldConstraint field) {
    final current = _text(_values[field.name]);
    final names = <String>{
      if (current.isNotEmpty) current,
      for (final item in widget.availableInterfaces) item.name,
    }.toList(growable: false)
      ..sort();
    if (names.isEmpty) return _field(field);
    return DropdownButtonFormField<String>(
      key: ValueKey('interface-choice-${field.name}-$current'),
      initialValue: current.isEmpty ? null : current,
      decoration: InputDecoration(
        labelText: _label(field.name),
        errorText: _errors[field.name],
      ),
      items: [
        for (final name in names)
          DropdownMenuItem(value: name, child: Text(_interfaceLabel(name))),
      ],
      onChanged: (selected) => _setValue(field.name, selected),
    );
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

  void _showMessage(
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: duration),
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
  return first?.toString() == second?.toString();
}

bool _boolean(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes' || text == 'on';
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
  if (value.isEmpty) return 'None';
  return value
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}
