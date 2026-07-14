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
            changes.containsKey(field.name) &&
            changes[field.name].toString().trim().isNotEmpty)
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
    if (widget.kind.technology.requiresExplicitApply) {
      body.write('\n\nThe configuration will be applied after the write succeeds.');
    } else {
      body.write('\n\nThe pfREST model applies this change immediately.');
    }

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
        final text = entry.value?.toString().trim() ?? '';
        if (text.isNotEmpty) changes[entry.key] = entry.value;
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
    final coreNames = _coreFields[widget.kind] ?? const <String>[];
    final coreFields = <PfRestFieldConstraint>[];
    final additionalFields = <PfRestFieldConstraint>[];
    for (final field in fields) {
      if (coreNames.contains(field.name)) {
        coreFields.add(field);
      } else {
        additionalFields.add(field);
      }
    }
    coreFields.sort(
      (a, b) => coreNames.indexOf(a.name).compareTo(coreNames.indexOf(b.name)),
    );

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
        if (widget.kind.child) ...[
          _section('Parent resource'),
          _parentField(operation.field('parent_id', location: 'body')),
        ],
        if (widget.kind == VpnResourceKind.ipsecPhase2 &&
            fields.any((field) => field.name == 'ikeid')) ...[
          _section('Parent Phase 1'),
          _relationshipField(
            field: fields.firstWhere((field) => field.name == 'ikeid'),
            parentKind: VpnResourceKind.ipsecPhase1,
          ),
        ],
        if (widget.kind == VpnResourceKind.wireGuardPeer &&
            fields.any((field) => field.name == 'tun')) ...[
          _section('Tunnel assignment'),
          _relationshipField(
            field: fields.firstWhere((field) => field.name == 'tun'),
            parentKind: VpnResourceKind.wireGuardTunnel,
          ),
        ],
        _section('Primary settings'),
        for (final field in coreFields)
          if (!_isRelationshipField(field.name)) _field(field),
        if (additionalFields.isNotEmpty)
          ExpansionTile(
            initiallyExpanded: coreFields.isEmpty,
            leading: const Icon(Icons.tune),
            title: Text(
              coreFields.isEmpty
                  ? 'Reported configuration fields'
                  : 'Additional reported fields',
            ),
            subtitle: const Text(
              'Every control below comes from the connected OpenAPI schema.',
            ),
            children: [
              for (final field in additionalFields)
                if (!_isRelationshipField(field.name))
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

  Widget _parentField(PfRestFieldConstraint? field) {
    final parentKind = widget.kind.parentKind;
    if (field == null || parentKind == null) {
      return const SizedBox.shrink();
    }
    return _relationshipField(field: field, parentKind: parentKind);
  }

  Widget _relationshipField({
    required PfRestFieldConstraint field,
    required VpnResourceKind parentKind,
  }) {
    final parents = widget.resources
        .where((resource) => resource.kind == parentKind && resource.id != null)
        .toList(growable: false);
    final current = _text(_values[field.name]);
    final choices = <String, String>{
      for (final parent in parents)
        parent.id.toString(): parent.displayName,
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

    if (_isNestedObjectField(field.name, value)) {
      return _jsonField(field);
    }
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
      key: ValueKey('vpn-secret-${field.name}-$revealed'),
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
    if (field.description == null) return null;
    return Text(field.description!);
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

  bool _isRelationshipField(String name) {
    if (name == 'parent_id' && widget.kind.child) return true;
    if (name == 'ikeid' && widget.kind == VpnResourceKind.ipsecPhase2) {
      return true;
    }
    if (name == 'tun' && widget.kind == VpnResourceKind.wireGuardPeer) {
      return true;
    }
    return false;
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

const _coreFields = <VpnResourceKind, List<String>>{
  VpnResourceKind.openVpnServer: [
    'description',
    'disable',
    'mode',
    'authmode',
    'dev_mode',
    'protocol',
    'interface',
    'local_port',
    'use_tls',
    'tls',
    'tls_type',
    'tlsauth_keydir',
    'caref',
    'certref',
    'data_ciphers',
    'data_ciphers_fallback',
    'digest',
    'tunnel_network',
    'tunnel_networkv6',
    'local_network',
    'local_networkv6',
    'remote_network',
    'remote_networkv6',
    'custom_options',
  ],
  VpnResourceKind.openVpnClient: [
    'description',
    'disable',
    'mode',
    'dev_mode',
    'protocol',
    'interface',
    'server_addr',
    'server_port',
    'local_port',
    'proxy_addr',
    'proxy_port',
    'proxy_authtype',
    'proxy_user',
    'proxy_passwd',
    'auth_user',
    'auth_pass',
    'tls',
    'tls_type',
    'tlsauth_keydir',
    'caref',
    'certref',
    'data_ciphers',
    'data_ciphers_fallback',
    'digest',
    'custom_options',
  ],
  VpnResourceKind.openVpnCso: [
    'common_name',
    'description',
    'disable',
    'server_list',
    'tunnel_network',
    'tunnel_networkv6',
    'local_network',
    'local_networkv6',
    'remote_network',
    'remote_networkv6',
    'custom_options',
  ],
  VpnResourceKind.openVpnExportConfig: [
    'server',
    'description',
    'useaddr',
    'usepkcs11',
    'usetoken',
    'useproxy',
    'proxy_type',
    'proxy_addr',
    'proxy_port',
    'proxy_authtype',
    'proxy_user',
    'proxy_password',
  ],
  VpnResourceKind.ipsecPhase1: [
    'descr',
    'disabled',
    'iketype',
    'mode',
    'protocol',
    'interface',
    'remote_gateway',
    'authentication_method',
    'myid_type',
    'myid_data',
    'peerid_type',
    'peerid_data',
    'pre_shared_key',
    'certref',
    'caref',
    'lifetime',
    'rekey_time',
    'reauth_time',
    'rand_time',
    'startaction',
    'closeaction',
    'nat_traversal',
    'mobike',
    'ikeport',
    'nattport',
    'dpd_delay',
    'dpd_maxfail',
    'encryption',
  ],
  VpnResourceKind.ipsecPhase2: [
    'ikeid',
    'descr',
    'disabled',
    'mode',
    'localid_type',
    'localid_address',
    'localid_netbits',
    'remoteid_type',
    'remoteid_address',
    'remoteid_netbits',
    'protocol',
    'lifetime',
    'rekey_time',
    'rand_time',
    'pinghost',
    'keepalive',
    'encryption',
  ],
  VpnResourceKind.wireGuardTunnel: [
    'enabled',
    'descr',
    'listenport',
    'privatekey',
    'mtu',
    'addresses',
  ],
  VpnResourceKind.wireGuardPeer: [
    'enabled',
    'tun',
    'endpoint',
    'port',
    'descr',
    'persistentkeepalive',
    'publickey',
    'presharedkey',
    'allowedips',
  ],
  VpnResourceKind.wireGuardTunnelAddress: [
    'parent_id',
    'address',
    'mask',
    'descr',
  ],
  VpnResourceKind.wireGuardPeerAllowedIp: [
    'parent_id',
    'address',
    'mask',
    'descr',
  ],
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
