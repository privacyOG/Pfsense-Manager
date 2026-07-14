import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pfrest_capabilities.dart';
import '../models/vpn_management.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/vpn_management_validation.dart';
import '../widgets/slide_to_confirm.dart';

class VpnSettingsScreen extends StatefulWidget {
  const VpnSettingsScreen({
    super.key,
    required this.technology,
    required this.settings,
    this.onPermissionDenied,
  });

  final VpnTechnology technology;
  final VpnSingletonSettings settings;
  final VoidCallback? onPermissionDenied;

  @override
  State<VpnSettingsScreen> createState() => _VpnSettingsScreenState();
}

class _VpnSettingsScreenState extends State<VpnSettingsScreen> {
  late Map<String, dynamic> _values;
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.settings.raw);
  }

  Future<void> _save() async {
    if (_saving) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.vpnManagementService;
    final capability = service?.capabilities.forTechnology(widget.technology);
    final operation = capability?.settingsUpdate;
    if (!session.connected ||
        service == null ||
        operation == null ||
        capability == null ||
        !capability.canApply) {
      return;
    }

    final values = normaliseVpnValues(
      values: _values,
      operation: operation,
    );
    final validation = validateVpnSettings(
      technology: widget.technology,
      values: values,
      operation: operation,
    );
    if (!validation.isValid) {
      setState(() => _errors = validation.errors);
      _message(validation.summary);
      return;
    }
    final changes = <String, dynamic>{
      for (final entry in values.entries)
        if (!_equivalent(widget.settings.raw[entry.key], entry.value))
          entry.key: entry.value,
    };
    if (changes.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }

    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Save ${widget.technology.label} settings?',
      body:
          'This changes a live VPN service and may interrupt active tunnels. The configuration will be applied only after the settings write succeeds.',
      slideLabel: 'Slide to save and apply',
      icon: Icons.settings_input_component_outlined,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await service.updateSettings(widget.technology, widget.settings, changes);
      await service.apply(widget.technology);
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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.vpnManagementService;
    final capability = service?.capabilities.forTechnology(widget.technology);
    final operation = capability?.settingsUpdate;
    if (service == null || operation == null || capability == null) {
      return Scaffold(
        appBar: AppBar(title: Text('${widget.technology.label} settings')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('These settings are not writable for this profile.'),
          ),
        ),
      );
    }

    final fields = operation.requestFields.values
        .where((field) =>
            field.location.toLowerCase() == 'body' && !field.readOnly)
        .toList(growable: false);
    for (final field in fields) {
      _values.putIfAbsent(
        field.name,
        () => field.defaultValue ??
            (field.type == 'boolean'
                ? false
                : field.type == 'array'
                    ? <dynamic>[]
                    : field.type == 'object'
                        ? <String, dynamic>{}
                        : ''),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('${widget.technology.label} settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: const Text('Live VPN settings'),
              subtitle: const Text(
                'Disabling the service or changing global behavior can terminate active tunnels.',
              ),
            ),
          ),
          for (final field in fields) _field(field),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving || !capability.canApply ? null : _save,
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

  Widget _field(PfRestFieldConstraint field) {
    final value = _values[field.name];
    if (field.type == 'boolean' || value is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_label(field.name)),
        subtitle: _subtitle(field),
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
        key: ValueKey('vpn-setting-${field.name}-$current'),
        initialValue: current == null || current.isEmpty ? null : current,
        decoration: InputDecoration(
          labelText: _label(field.name),
          errorText: _errors[field.name],
          helperText: field.description,
        ),
        items: [
          for (final option in allowed)
            DropdownMenuItem(value: option, child: Text(_label(option))),
        ],
        onChanged: (selected) => _setValue(field.name, selected),
      );
    }

    if (field.type == 'object' ||
        (value is List && value.any((item) => item is Map)) ||
        value is Map) {
      return TextFormField(
        key: ValueKey('vpn-setting-json-${field.name}-${value.hashCode}'),
        initialValue: const JsonEncoder.withIndent('  ').convert(value),
        minLines: 4,
        maxLines: 12,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: _label(field.name),
          errorText: _errors[field.name],
          helperText: '${field.description ?? ''}\nEnter valid JSON.'.trim(),
          alignLabelWithHint: true,
        ),
        onChanged: (text) => _setValue(field.name, text),
      );
    }

    final isList = field.type == 'array' || value is List;
    return TextFormField(
      key: ValueKey('vpn-setting-${field.name}-${value?.hashCode ?? 0}'),
      initialValue: isList && value is List
          ? value.map((item) => item.toString()).join(', ')
          : value?.toString() ?? '',
      maxLines: isList ? 2 : 1,
      keyboardType: field.type == 'integer' || field.type == 'number'
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: _label(field.name),
        errorText: _errors[field.name],
        helperText: isList
            ? '${field.description ?? ''}\nSeparate values with commas.'.trim()
            : field.description,
      ),
      onChanged: (text) => _setValue(
        field.name,
        isList ? _splitValues(text) : text,
      ),
    );
  }

  Widget? _subtitle(PfRestFieldConstraint field) {
    final error = _errors[field.name];
    if (error != null) {
      return Text(
        error,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    return field.description == null ? null : Text(field.description!);
  }

  Iterable<Widget> _withSpacing(Widget widget) sync* {
    yield widget;
    if (widget is! SizedBox) yield const SizedBox(height: 12);
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
