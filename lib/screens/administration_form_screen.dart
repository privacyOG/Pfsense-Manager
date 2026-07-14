import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/administration_management.dart';
import '../models/pfrest_capabilities.dart';
import '../providers/session_provider.dart';
import '../utils/administration_validation.dart';
import '../utils/api_exception.dart';
import '../widgets/slide_to_confirm.dart';

class AdministrationFormScreen extends StatefulWidget {
  const AdministrationFormScreen.resource({
    super.key,
    required this.kind,
    this.resource,
  }) : action = null;

  const AdministrationFormScreen.action({
    super.key,
    required AdministrationActionKind this.action,
  })  : kind = null,
        resource = null;

  final AdministrationResourceKind? kind;
  final ManagedAdministrationResource? resource;
  final AdministrationActionKind? action;

  @override
  State<AdministrationFormScreen> createState() =>
      _AdministrationFormScreenState();
}

class _AdministrationFormScreenState extends State<AdministrationFormScreen> {
  late Map<String, dynamic> _values;
  Map<String, String> _errors = const {};
  final Set<String> _revealed = {};
  bool _saving = false;

  bool get _isAction => widget.action != null;
  bool get _editing => widget.resource != null;

  @override
  void initState() {
    super.initState();
    _values = {...?widget.resource?.raw};
  }

  PfRestOperationCapability? _operation() {
    final service = context.read<PfSenseSessionProvider>().administrationService;
    if (service == null) return null;
    if (_isAction) {
      return service.capabilities.forAction(widget.action!).operation;
    }
    final capability = service.capabilities.forResource(widget.kind!);
    if (_editing || widget.kind!.singleton) {
      return capability.writeOperation;
    }
    return capability.create;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.administrationService;
    final operation = _operation();
    if (!session.connected || service == null || operation == null) return;

    final bodyValues = normaliseAdministrationValues(
      values: _values,
      operation: operation,
    );
    final values = {..._values, ...bodyValues};
    final validation = validateAdministrationValues(
      values: values,
      operation: operation,
      editing: _editing || widget.kind?.singleton == true,
    );
    if (!validation.isValid) {
      setState(() => _errors = validation.errors);
      _message(validation.summary);
      return;
    }

    final changes = _changedValues(values, operation);
    if (!_isAction && (_editing || widget.kind!.singleton) && changes.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }

    final secretNames = operation.requestFields.values
        .where(
          (field) =>
              isAdministrationSecretField(field) &&
              _text(changes[field.name]).isNotEmpty,
        )
        .map((field) => _label(field.name))
        .toList(growable: false);
    final target = _isAction
        ? widget.action!.label
        : widget.kind!.singularLabel;
    final warning = StringBuffer(
      _isAction
          ? 'This will run $target on the selected firewall.'
          : 'This changes the live $target configuration.',
    );
    if (secretNames.isNotEmpty) {
      warning.write(
        '\n\nSecret values will be replaced for: ${secretNames.join(', ')}. Existing secrets are not loaded into this form.',
      );
    }
    if ((_isAction && widget.action!.highImpact) ||
        (!_isAction && widget.kind!.highImpact)) {
      warning.write(
        '\n\nThis is a high-impact administrative operation and may affect access, authentication, certificates, packages, or system availability.',
      );
    }

    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: _isAction ? '${widget.action!.label}?' : 'Save $target?',
      body: warning.toString(),
      slideLabel: _isAction ? 'Slide to run action' : 'Slide to save changes',
      icon: _isAction ? Icons.admin_panel_settings_outlined : Icons.save_outlined,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      AdministrationOperationResult result;
      if (_isAction) {
        result = await service.runAction(widget.action!, values);
      } else if (_editing) {
        result = await service.update(widget.resource!, changes);
      } else if (widget.kind!.singleton) {
        final current = widget.resource ??
            ManagedAdministrationResource(kind: widget.kind!, raw: const {});
        result = await service.update(current, changes);
      } else {
        result = await service.create(widget.kind!, values);
      }
      if (!mounted) return;
      if (_isAction || result.hasSecret) {
        await _showResult(result);
        if (!mounted) return;
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
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
    if (_isAction || (!_editing && widget.kind?.singleton != true)) {
      return values;
    }
    final original = widget.resource?.raw ?? const <String, dynamic>{};
    final changes = <String, dynamic>{};
    for (final field in operation.requestFields.values) {
      if (field.location.toLowerCase() != 'body' || field.readOnly) continue;
      final value = values[field.name];
      if (isAdministrationSecretField(field)) {
        if (!_empty(value)) changes[field.name] = value;
        continue;
      }
      if (!_equivalent(original[field.name], value)) {
        changes[field.name] = value;
      }
    }
    return changes;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final operation = session.administrationService == null ? null : _operation();
    final title = _isAction
        ? widget.action!.label
        : _editing || widget.kind!.singleton
            ? 'Edit ${widget.kind!.singularLabel}'
            : 'Add ${widget.kind!.singularLabel}';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: operation == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This operation is not available for the selected profile.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _form(operation),
    );
  }

  Widget _form(PfRestOperationCapability operation) {
    final fields = operation.requestFields.values
        .where(
          (field) =>
              !field.readOnly &&
              const {'body', 'query'}.contains(field.location.toLowerCase()),
        )
        .toList(growable: false);
    _applyDefaults(fields);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Secret-safe administration'),
            subtitle: Text(
              _editing || widget.kind?.singleton == true
                  ? 'Passwords, private keys, API key secrets and authentication material are never loaded into this form. Leave a secret field blank to preserve it.'
                  : 'Secret values are submitted only when entered and are not retained in the administration model.',
            ),
          ),
        ),
        if (fields.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('No parameters required'),
              subtitle: Text(
                'The connected pfREST schema reports no input fields for ${_isAction ? widget.action!.label : widget.kind!.singularLabel}.',
              ),
            ),
          ),
        for (final field in fields) _field(field),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_isAction ? Icons.play_arrow : Icons.save_outlined),
          label: Text(
            _saving
                ? 'Working…'
                : _isAction
                    ? 'Review and run'
                    : 'Review and save',
          ),
        ),
      ].expand(_spacing).toList(growable: false),
    );
  }

  Widget _field(PfRestFieldConstraint field) {
    final value = _values[field.name];
    if (isAdministrationSecretField(field)) return _secretField(field);
    if (field.type == 'boolean' || value is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_label(field.name)),
        subtitle: _subtitle(field),
        value: _boolean(value),
        onChanged: (selected) => _set(field.name, selected),
      );
    }

    final choices = field.allowedValues
        .map((item) => item?.toString())
        .whereType<String>()
        .toSet();
    final current = value?.toString() ?? '';
    if (choices.isNotEmpty && field.type != 'array') {
      if (current.isNotEmpty) choices.add(current);
      return DropdownButtonFormField<String>(
        key: ValueKey('admin-choice-${field.location}-${field.name}-$current'),
        initialValue: current.isEmpty ? null : current,
        decoration: InputDecoration(
          labelText: _label(field.name),
          helperText: field.description,
          errorText: _errors[field.name],
        ),
        items: [
          for (final choice in choices)
            DropdownMenuItem(value: choice, child: Text(choice)),
        ],
        onChanged: (selected) => _set(field.name, selected ?? ''),
      );
    }

    final nested = field.type == 'array' ||
        field.type == 'object' ||
        value is List ||
        value is Map;
    return TextFormField(
      key: ValueKey('admin-field-${field.location}-${field.name}-$current'),
      initialValue: nested && value is! String
          ? const JsonEncoder.withIndent('  ').convert(value)
          : current,
      minLines: nested ? 3 : 1,
      maxLines: nested ? 10 : 1,
      keyboardType: field.type == 'integer' || field.type == 'number'
          ? TextInputType.number
          : nested
              ? TextInputType.multiline
              : TextInputType.text,
      decoration: InputDecoration(
        labelText: _label(field.name),
        helperText: field.description,
        errorText: _errors[field.name],
        alignLabelWithHint: nested,
      ),
      onChanged: (changed) => _set(field.name, changed),
    );
  }

  Widget _secretField(PfRestFieldConstraint field) {
    final revealed = _revealed.contains(field.name);
    return TextFormField(
      key: ValueKey('admin-secret-${field.name}-$revealed'),
      initialValue: _text(_values[field.name]),
      obscureText: !revealed,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: _label(field.name),
        helperText: _editing || widget.kind?.singleton == true
            ? 'Leave blank to preserve the existing secret.'
            : field.description,
        errorText: _errors[field.name],
        suffixIcon: IconButton(
          tooltip: revealed ? 'Hide secret' : 'Show typed secret',
          onPressed: () => setState(() {
            if (revealed) {
              _revealed.remove(field.name);
            } else {
              _revealed.add(field.name);
            }
          }),
          icon: Icon(revealed ? Icons.visibility_off : Icons.visibility),
        ),
      ),
      onChanged: (changed) => _set(field.name, changed),
    );
  }

  void _applyDefaults(List<PfRestFieldConstraint> fields) {
    for (final field in fields) {
      if (_values.containsKey(field.name)) continue;
      if (isAdministrationSecretField(field)) {
        _values[field.name] = '';
      } else if (field.defaultValue != null) {
        _values[field.name] = copyAdministrationValue(field.defaultValue);
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

  Future<void> _showResult(AdministrationOperationResult result) async {
    final safeText = result.safeRecords.isEmpty
        ? 'The operation completed successfully.'
        : const JsonEncoder.withIndent('  ').convert(result.safeRecords);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(result.filename ?? 'Operation result'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.hasSecret) ...[
                const Text(
                  'This secret is shown once. Store it securely before closing this dialog.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SelectableText(result.ephemeralSecret!),
                const Divider(height: 28),
              ],
              SelectableText(safeText),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close and discard'),
          ),
        ],
      ),
    );
  }

  void _set(String name, Object? value) {
    setState(() {
      _values[name] = value;
      if (_errors.containsKey(name)) {
        _errors = {..._errors}..remove(name);
      }
    });
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget? _subtitle(PfRestFieldConstraint field) {
    final text = field.description?.trim() ?? '';
    return text.isEmpty ? null : Text(text);
  }
}

Iterable<Widget> _spacing(Widget widget) sync* {
  yield widget;
  yield const SizedBox(height: 12);
}

bool _boolean(Object? value) {
  if (value is bool) return value;
  return const {'true', '1', 'yes', 'on'}
      .contains(value?.toString().trim().toLowerCase());
}

bool _empty(Object? value) => value == null ||
    (value is String && value.trim().isEmpty) ||
    (value is Iterable && value.isEmpty) ||
    (value is Map && value.isEmpty);

bool _equivalent(Object? left, Object? right) =>
    jsonEncode(copyAdministrationValue(left)) ==
    jsonEncode(copyAdministrationValue(right));

String _text(Object? value) => value?.toString().trim() ?? '';

String _label(String name) => name
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');