import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pfrest_capabilities.dart';
import '../models/vpn_management.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/vpn_management_validation.dart';
import '../widgets/slide_to_confirm.dart';

class VpnResourceFormScreen extends StatefulWidget {
  const VpnResourceFormScreen({
    super.key,
    required this.kind,
    required this.resources,
    this.resource,
    this.initialValues = const {},
    this.onPermissionDenied,
  });

  final VpnResourceKind kind;
  final ManagedVpnResource? resource;
  final List<ManagedVpnResource> resources;
  final Map<String, dynamic> initialValues;
  final VoidCallback? onPermissionDenied;

  @override
  State<VpnResourceFormScreen> createState() =>
      _VpnResourceFormScreenState();
}

class _VpnResourceFormScreenState extends State<VpnResourceFormScreen> {
  late Map<String, dynamic> _values;
  Map<String, String> _errors = const {};
  bool _saving = false;
  final Set<String> _revealedSecrets = {};

  bool get _editing => widget.resource != null;

  @override
  void initState() {
    super.initState();
    _values = {
      ...?widget.resource?.raw,
      ...widget.initialValues,
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.vpnManagementService;
    if (!session.connected || service == null) return;

    final capability = service.capabilities.forKind(widget.kind);
    final operation = _editing ? capability.update : capability.create;
    final technology = service.capabilities.forTechnology(widget.kind.technology);
    if (operation == null || !technology.canApply) {
      _message('This profile cannot save this VPN resource.');
      return;
    }

    final values = normaliseVpnValues(
      values: _values,
      operation: operation,
    );
    final validation = validateVpnResource(
      kind: widget.kind,
      values: values,
      operation: operation,
      editing: _editing,
      context: VpnValidationContext(
        resources: widget.resources,
        editing: widget.resource,
      ),
    );
    if (!validation.isValid) {
      setState(() => _errors = validation.errors);
      _message(validation.summary);
      return;
    }

    final changes = _changedValues(values, operation);
    if (_editing && changes.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }

    final secretChanges = operation.requestFields.values
        .where((field) =>
            isVpnSecretField(field) &&
            _text(changes[field.name]).isNotEmpty)
        .map((field) => _label(field.name))
        .toList(growable: false);
    final body = StringBuffer(
      'This changes a live ${widget.kind.technology.label} configuration and may interrupt VPN connectivity.',
    );
    if (secretChanges.isNotEmpty) {
      body.write(
        '\n\nThe following secret values will be replaced: ${secretChanges.join(', ')}. Existing secret values cannot be viewed or recovered from this form.',
      );
    }
    body.write(
      widget.kind.technology.requiresExplicitApply
          ? '\n\nThe configuration will be applied after the write succeeds.'
          : '\n\nThe pfREST model applies this change immediately.',
    );

    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: _editing
          ? 'Save ${widget.kind.singularLabel}?'
          : 'Create ${widget.kind.singularLabel}?',
      body: body.toString(),
      slideLabel: 'Slide to save changes',
      icon: Icons.vpn_key_outlined,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      if (_editing) {
        await service.update(widget.resource!, changes);
      } else {
        await service.create(widget.kind, values);
      }
      await service.apply(widget.kind.technology);
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

  Map<String, dynamic> _changedValues(
    Map<String, dynamic> values,
    PfRestOperationCapability operation,
  ) {
    final original = widget.resource?.raw;
    if (original == null) return values;
    final changes = <String, dynamic>{};
    for (final entry in values.entries) {
      final field = operation.field(entry.key, location: 'body');
      if (field?.readOnly == true) continue;
      if (field != null && isVpnSecretField(field)) {
        if (_text(entry.value).isNotEmpty) changes[entry.key] = entry.value;
        continue;
      }
      if (!_equivalent(original[entry.key], entry.value)) {
        changes[entry.key] = entry.value;
      }
    }
    return changes;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.vpnManagementService;
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
              service.capabilities
                  .forTechnology(widget.kind.technology)
                  .canApply,
            ),
    );
  }

  Widget _form(PfRestOperationCapability operation, bool canApply) {
    final fields = operation.requestFields.values
        .where((field) =>
            field.location.toLowerCase() == 'body' && !field.readOnly)
        .toList(growable: false);
    _applyDefaults(fields);
    final relationshipNames = _relationshipFields;
    final regularFields = fields
        .where((field) => !relationshipNames.contains(field.name))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _securityNotice(),
        if (!canApply)
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Apply operation unavailable'),
              subtitle: Text(
                'Editing is disabled because this technology requires an apply endpoint that the connected schema does not report.',
              ),
            ),
          ),
        if (relationshipNames.isNotEmpty) ...[
          _section('Relationships'),
          for (final field in fields)
            if (relationshipNames.contains(field.name))
              _relationshipField(
                field: field,
                parentKind: _parentKindFor(field.name),
              ),
        ],
        _section('Reported configuration'),
        for (final field in regularFields) _field(field),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving || !canApply ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(
            _saving
                ? 'Saving…'
                : widget.kind.technology.requiresExplicitApply
                    ? 'Save and apply'
                    : 'Save',
          ),
        ),
      ].expand(_withSpacing).toList(growable: false),
    );
  }

  Set<String> get _relationshipFields {
    final names = <String>{};
    if (widget.kind.child) names.add('parent_id');
    if (widget.kind == VpnResourceKind.ipsecPhase2) names.add('ikeid');
    if (widget.kind == VpnResourceKind.wireGuardPeer) names.add('tun');
    return names;
  }

  VpnResourceKind? _parentKindFor(String fieldName) {
    return switch (fieldName) {
      'parent_id' => widget.kind.parentKind,
      'ikeid' => VpnResourceKind.ipsecPhase1,
      'tun' => VpnResourceKind.wireGuardTunnel,
      _ => null,
    };
  }

  void _applyDefaults(List<PfRestFieldConstraint> fields) {
    for (final field in fields) {
      if (_values.containsKey(field.name)) continue;
      if (isVpnSecretField(field)) {
        _values[field.name] = '';
      } else if (field.defaultValue != null) {
        _values[field.name] = field.defaultValue;
      } else if (field.type == 'boolean') {
        _values[field.name] = false;
      } else if (field.type == 'array') {
        _values[field.name] = <dynamic>[];
      } else if (field.type == 'object') {
        _values[field.name] = <String, dynamic>{};
      } else {
        _values[field.name] = '';
      }
    }
  }

  Widget _securityNotice() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.security_outlined),
        title: const Text('Secret-safe editing'),
        subtitle: Text(
          _editing
              ? 'Private keys, passwords, pre-shared keys and TLS keys are never loaded into this form. Leave a secret field blank to preserve the existing value.'
              : 'Secret values are submitted only when entered and are never shown in summaries or retained by the management model.',
        ),
      ),
    );
  }

  Widget _relationshipField({
    required PfRestFieldConstraint field,
    required VpnResourceKind? parentKind,
  }) {
    final current = _text(_values[field.name]);
    final parents = parentKind == null
        ? const <ManagedVpnResource>[]
        : widget.resources
            .where((resource) => resource.kind == parentKind)
            .toList(growable: false);
    final choices = <String, String>{
      for (final parent in parents)
        if (vpnRelationshipIdentifier(parent, field.name).isNotEmpty)
          vpnRelationshipIdentifier(parent, field.name): parent.displayName,
      if (current.isNotEmpty) current: current,
    };
    if (choices.isEmpty) {
      return TextFormField(
        initialValue: current,
        enabled: !_editing || field.name != 'parent_id',
        decoration: InputDecoration(
          labelText: _label(field.name),
          errorText: _errors[field.name],
          helperText: 'Enter the identifier reported by pfREST.',
        ),
        onChanged: (value) => _setValue(field.name, value),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('vpn-relation-${field.name}-$current'),
      initialValue: current.isEmpty ? null : current,
      decoration: InputDecoration(
        labelText: _label(field.name),
        errorText: _errors[field.name],
        helperText: field.description,
      ),
      items: [
        for (final entry in choices.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: _editing && field.name == 'parent_id'
          ? null
          : (value) => _setValue(field.name, value ?? ''),
    );
  }

  Widget _field(PfRestFieldConstraint field) {
    if (isVpnSecretField(field)) return _secretField(field);
    final value = _values[field.name];
    if (field.type == 'boolean' || value is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_label(field.name)),
        subtitle: _fieldSubtitle(field),
        value: _boolean(value),
        onChanged: (selected) => _setValue(field.name, selected),
      );
    }

    final allowed = field.allowedValues
        .map((item) => item?.toString())
        .whereType<String>()
        .toSet();
    if (allowed.isNotEmpty && field.type != 'array') {
      final current = value?.toString();
      if (current != null && current.isNotEmpty) allowed.add(current);
      return DropdownButtonFormField<String>(
        key: ValueKey('vpn-field-${field.name}-$current'),
        initialValue: current == null || current.isEmpty ? null : current,
        decoration: InputDecoration(
          labelText: _label(field.name),
          errorText: _errors[field.name],
          helperText: field.description,
        ),
        items: [
          for (final option in allowed)
            DropdownMenuItem(value: option, child: Text(_displayValue(option))),
        ],
        onChanged: (selected) => _setValue(field.name, selected),
      );
    }

    if (_isNestedObjectField(field.name, value)) return _jsonField(field);
    if (field.type == 'array' || value is List) {
      return TextFormField(
        key: ValueKey('vpn-list-${field.name}-${value.hashCode}'),
        initialValue: _stringList(value).join(', '),
        maxLines: 2,
        decoration: InputDecoration(
          labelText: _label(field.name),
          errorText: _errors[field.name],
          helperText: field.description == null
              ? 'Separate values with commas.'
              : '${field.description}\nSeparate values with commas.',
          alignLabelWithHint: true,
        ),
        onChanged: (text) => _setValue(field.name, _splitValues(text)),
      );
    }

    return TextFormField(
      key: ValueKey('vpn-field-${field.name}-${value?.hashCode ?? 0}'),
      initialValue: value?.toString() ?? '',
      keyboardType: field.type == 'integer' || field.type == 'number'
          ? TextInputType.number
          : TextInputType.text,
      maxLines: field.name == 'custom_options' ? 6 : 1,
      decoration: InputDecoration(
        labelText: _label(field.name),
        errorText: _errors[field.name],
        helperText: field.description,
        alignLabelWithHint: field.name == 'custom_options',
      ),
      onChanged: (text) => _setValue(field.name, text),
    );
  }

  Widget _secretField(PfRestFieldConstraint field) {
    final revealed = _revealedSecrets.contains(field.name);
    return TextFormField(
      key: ValueKey('vpn-secret-${field.name}'),
      initialValue: '',
      obscureText: !revealed,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: _label(field.name),
        errorText: _errors[field.name],
        helperText: _editing
            ? 'Leave blank to preserve the existing secret.'
            : field.description,
        suffixIcon: IconButton(
          tooltip: revealed ? 'Hide secret' : 'Show secret',
          onPressed: () {
            setState(() {
              revealed
                  ? _revealedSecrets.remove(field.name)
                  : _revealedSecrets.add(field.name);
            });
          },
          icon: Icon(revealed ? Icons.visibility_off : Icons.visibility),
        ),
      ),
      onChanged: (value) => _setValue(field.name, value),
    );
  }

  Widget _jsonField(PfRestFieldConstraint field) {
    final value = _values[field.name];
    String initialValue;
    try {
      initialValue = const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      initialValue = value?.toString() ?? '';
    }
    return TextFormField(
      key: ValueKey('vpn-json-${field.name}-${value?.hashCode ?? 0}'),
      initialValue: initialValue,
      minLines: 4,
      maxLines: 12,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: _label(field.name),
        errorText: _errors[field.name],
        helperText: field.description == null
            ? 'Enter valid JSON using the field names reported by pfREST.'
            : '${field.description}\nEnter valid JSON.',
        alignLabelWithHint: true,
      ),
      onChanged: (value) => _setValue(field.name, value),
    );
  }

  Widget? _fieldSubtitle(PfRestFieldConstraint field) {
    final error = _errors[field.name];
    if (error != null) {
      return Text(
        error,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    return field.description == null ? null : Text(field.description!);
  }

  Widget _section(String label) => Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      );

  Iterable<Widget> _withSpacing(Widget widget) sync* {
    yield widget;
    if (widget is! SizedBox) yield const SizedBox(height: 12);
  }

  bool _isNestedObjectField(String name, Object? value) {
    return _nestedObjectFields.contains(name) ||
        value is Map ||
        (value is List && value.any((item) => item is Map));
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

const _nestedObjectFields = <String>{
  'encryption',
  'addresses',
  'allowedips',
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

String _displayValue(String value) {
  if (value.isEmpty) return 'Automatic';
  return _label(value);
}
