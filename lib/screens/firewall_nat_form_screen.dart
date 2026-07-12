import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/firewall_nat.dart';
import '../providers/session_provider.dart';
import '../services/pfrest_feature_registry.dart';
import '../utils/firewall_nat_validation.dart';

class FirewallNatFormScreen extends StatefulWidget {
  const FirewallNatFormScreen({
    super.key,
    required this.type,
    this.rule,
  });

  final FirewallNatRuleType type;
  final Object? rule;

  @override
  State<FirewallNatFormScreen> createState() => _FirewallNatFormScreenState();
}

class _FirewallNatFormScreenState extends State<FirewallNatFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _interface;
  late final TextEditingController _description;
  late final TextEditingController _source;
  late final TextEditingController _sourcePort;
  late final TextEditingController _destination;
  late final TextEditingController _destinationPort;
  late final TextEditingController _target;
  late final TextEditingController _localPort;
  late final TextEditingController _external;
  late final TextEditingController _targetSubnet;
  late final TextEditingController _natPort;
  late final TextEditingController _sourceHashKey;

  String _ipProtocol = 'inet';
  String? _protocol = 'tcp';
  String? _reflection;
  String _associatedRule = '';
  String? _poolOptions;
  bool _enabled = true;
  bool _noRedirect = false;
  bool _noSync = false;
  bool _noBinat = false;
  bool _noNat = false;
  bool _staticNatPort = false;
  bool _saving = false;

  bool get _editing => widget.rule != null;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    String interface = '';
    String description = '';
    String source = 'any';
    String? sourcePort;
    String destination = 'any';
    String? destinationPort;
    String target = '';
    String? localPort;
    String external = '';
    int? targetSubnet;
    String? natPort;
    String? sourceHashKey;

    if (rule is NatPortForward) {
      interface = rule.interface;
      description = rule.description;
      source = rule.source;
      sourcePort = rule.sourcePort;
      destination = rule.destination;
      destinationPort = rule.destinationPort;
      target = rule.target;
      localPort = rule.localPort;
      _ipProtocol = rule.ipProtocol;
      _protocol = rule.protocol;
      _reflection = rule.reflection;
      _associatedRule = rule.associatedRuleId;
      _enabled = rule.enabled;
      _noRedirect = rule.noRedirect;
      _noSync = rule.noSync;
    } else if (rule is NatOneToOneMapping) {
      interface = rule.interface;
      description = rule.description;
      source = rule.source;
      destination = rule.destination;
      external = rule.external;
      _ipProtocol = rule.ipProtocol;
      _reflection = rule.reflection;
      _enabled = rule.enabled;
      _noBinat = rule.noBinat;
    } else if (rule is NatOutboundMapping) {
      interface = rule.interface;
      description = rule.description;
      source = rule.source;
      sourcePort = rule.sourcePort;
      destination = rule.destination;
      destinationPort = rule.destinationPort;
      target = rule.target ?? '';
      targetSubnet = rule.targetSubnet;
      natPort = rule.natPort;
      sourceHashKey = rule.sourceHashKey;
      _protocol = rule.protocol;
      _enabled = rule.enabled;
      _noNat = rule.noNat;
      _noSync = rule.noSync;
      _staticNatPort = rule.staticNatPort;
      _poolOptions = rule.poolOptions;
    }

    _interface = TextEditingController(text: interface);
    _description = TextEditingController(text: description);
    _source = TextEditingController(text: source);
    _sourcePort = TextEditingController(text: sourcePort ?? '');
    _destination = TextEditingController(text: destination);
    _destinationPort = TextEditingController(text: destinationPort ?? '');
    _target = TextEditingController(text: target);
    _localPort = TextEditingController(text: localPort ?? '');
    _external = TextEditingController(text: external);
    _targetSubnet = TextEditingController(
      text: targetSubnet?.toString() ?? '',
    );
    _natPort = TextEditingController(text: natPort ?? '');
    _sourceHashKey = TextEditingController(text: sourceHashKey ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _interface,
      _description,
      _source,
      _sourcePort,
      _destination,
      _destinationPort,
      _target,
      _localPort,
      _external,
      _targetSubnet,
      _natPort,
      _sourceHashKey,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  PfRestFeature get _writeFeature => switch ((widget.type, _editing)) {
        (FirewallNatRuleType.portForward, false) =>
          PfRestFeature.natPortForwardCreate,
        (FirewallNatRuleType.portForward, true) =>
          PfRestFeature.natPortForwardUpdate,
        (FirewallNatRuleType.oneToOne, false) =>
          PfRestFeature.natOneToOneCreate,
        (FirewallNatRuleType.oneToOne, true) =>
          PfRestFeature.natOneToOneUpdate,
        (FirewallNatRuleType.outboundMapping, false) =>
          PfRestFeature.natOutboundMappingCreate,
        (FirewallNatRuleType.outboundMapping, true) =>
          PfRestFeature.natOutboundMappingUpdate,
      };

  String get _title => switch (widget.type) {
        FirewallNatRuleType.portForward =>
          _editing ? 'Edit port forward' : 'Add port forward',
        FirewallNatRuleType.oneToOne =>
          _editing ? 'Edit 1:1 mapping' : 'Add 1:1 mapping',
        FirewallNatRuleType.outboundMapping =>
          _editing ? 'Edit outbound mapping' : 'Add outbound mapping',
      };

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.firewallNatService;
    if (!session.connected || service == null) return;

    final registry = PfRestFeatureRegistry(
      activeProfileId: session.selectedProfile?.id,
      capabilities: session.capabilities,
    );
    final decision = registry.decision(_writeFeature);
    if (!decision.canAttempt) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(decision.message)),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      switch (widget.type) {
        case FirewallNatRuleType.portForward:
          final previous = widget.rule as NatPortForward?;
          final rule = NatPortForward(
            id: previous?.id,
            interface: _interface.text.trim(),
            ipProtocol: _ipProtocol,
            protocol: _protocol ?? 'tcp',
            source: _source.text.trim(),
            sourcePort: _blankToNull(_sourcePort.text),
            destination: _destination.text.trim(),
            destinationPort: _blankToNull(_destinationPort.text),
            target: _target.text.trim(),
            localPort: _blankToNull(_localPort.text),
            disabled: !_enabled,
            noRedirect: _noRedirect,
            noSync: _noSync,
            description: _description.text.trim(),
            reflection: _reflection,
            associatedRuleId: _associatedRule,
            raw: previous?.raw ?? const {},
          );
          if (_editing) {
            await service.updatePortForward(rule);
          } else {
            await service.createPortForward(rule);
          }
        case FirewallNatRuleType.oneToOne:
          final previous = widget.rule as NatOneToOneMapping?;
          final mapping = NatOneToOneMapping(
            id: previous?.id,
            interface: _interface.text.trim(),
            disabled: !_enabled,
            noBinat: _noBinat,
            reflection: _reflection,
            ipProtocol: _ipProtocol,
            external: _external.text.trim(),
            source: _source.text.trim(),
            destination: _destination.text.trim(),
            description: _description.text.trim(),
            raw: previous?.raw ?? const {},
          );
          if (_editing) {
            await service.updateOneToOneMapping(mapping);
          } else {
            await service.createOneToOneMapping(mapping);
          }
        case FirewallNatRuleType.outboundMapping:
          final previous = widget.rule as NatOutboundMapping?;
          final mapping = NatOutboundMapping(
            id: previous?.id,
            interface: _interface.text.trim(),
            protocol: _protocol,
            disabled: !_enabled,
            noNat: _noNat,
            noSync: _noSync,
            source: _source.text.trim(),
            sourcePort: _blankToNull(_sourcePort.text),
            destination: _destination.text.trim(),
            destinationPort: _blankToNull(_destinationPort.text),
            target: _blankToNull(_target.text),
            targetSubnet: int.tryParse(_targetSubnet.text.trim()),
            natPort: _blankToNull(_natPort.text),
            staticNatPort: _staticNatPort,
            poolOptions: _poolOptions,
            sourceHashKey: _blankToNull(_sourceHashKey.text),
            description: _description.text.trim(),
            raw: previous?.raw ?? const {},
          );
          if (_editing) {
            await service.updateOutboundMapping(mapping);
          } else {
            await service.createOutboundMapping(mapping);
          }
      }
      if (mounted) Navigator.of(context).pop(true);
    } on NatValidationException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError(pfRestFeatureRequestErrorMessage(_writeFeature, error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final portProtocol = natPortProtocols.contains(_protocol);
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _textField(_interface, 'Interface', required: true),
            const SizedBox(height: 12),
            if (widget.type != FirewallNatRuleType.outboundMapping) ...[
              DropdownButtonFormField<String>(
                initialValue: _ipProtocol,
                decoration: const InputDecoration(labelText: 'IP protocol'),
                items: [
                  for (final value in widget.type == FirewallNatRuleType.portForward
                      ? const ['inet', 'inet6', 'inet46']
                      : const ['inet', 'inet6'])
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) => setState(() => _ipProtocol = value!),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.type != FirewallNatRuleType.oneToOne) ...[
              DropdownButtonFormField<String?>(
                initialValue: _protocol,
                decoration: const InputDecoration(labelText: 'Protocol'),
                items: [
                  if (widget.type == FirewallNatRuleType.outboundMapping)
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Any'),
                    ),
                  for (final value in natProtocols.where((value) => value != 'any'))
                    DropdownMenuItem<String?>(
                      value: value,
                      child: Text(value),
                    ),
                ],
                onChanged: (value) => setState(() => _protocol = value),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.type == FirewallNatRuleType.oneToOne) ...[
              _textField(_external, 'External address', required: true),
              const SizedBox(height: 12),
            ],
            _textField(
              _source,
              widget.type == FirewallNatRuleType.outboundMapping
                  ? 'Source network'
                  : 'Source',
              required: true,
            ),
            if (portProtocol && widget.type != FirewallNatRuleType.oneToOne) ...[
              const SizedBox(height: 12),
              _textField(_sourcePort, 'Source port or alias'),
            ],
            const SizedBox(height: 12),
            _textField(
              _destination,
              widget.type == FirewallNatRuleType.outboundMapping
                  ? 'Destination network'
                  : 'Destination',
              required: true,
            ),
            if (portProtocol && widget.type != FirewallNatRuleType.oneToOne) ...[
              const SizedBox(height: 12),
              _textField(_destinationPort, 'Destination port or alias'),
            ],
            if (widget.type == FirewallNatRuleType.portForward) ...[
              const SizedBox(height: 12),
              _textField(_target, 'Internal target', required: true),
              if (portProtocol) ...[
                const SizedBox(height: 12),
                _textField(_localPort, 'Internal port', required: true),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _reflection,
                decoration: const InputDecoration(labelText: 'NAT reflection'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('System default')),
                  DropdownMenuItem(value: 'enable', child: Text('Enable')),
                  DropdownMenuItem(value: 'disable', child: Text('Disable')),
                  DropdownMenuItem(value: 'purenat', child: Text('Pure NAT')),
                ],
                onChanged: (value) => setState(() => _reflection = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _associatedRule,
                decoration: const InputDecoration(
                  labelText: 'Linked firewall rule',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Require a separate firewall rule'),
                  ),
                  const DropdownMenuItem(
                    value: 'new',
                    child: Text('Create and maintain a linked rule'),
                  ),
                  const DropdownMenuItem(
                    value: 'pass',
                    child: Text('Pass traffic without a separate rule'),
                  ),
                  if (_associatedRule.isNotEmpty &&
                      !const {'new', 'pass'}.contains(_associatedRule))
                    DropdownMenuItem(
                      value: _associatedRule,
                      child: Text('Existing rule: $_associatedRule'),
                    ),
                ],
                onChanged: (value) => setState(() => _associatedRule = value!),
              ),
              SwitchListTile(
                value: _noRedirect,
                onChanged: (value) => setState(() => _noRedirect = value),
                title: const Text('No redirect'),
              ),
            ],
            if (widget.type == FirewallNatRuleType.oneToOne) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _reflection,
                decoration: const InputDecoration(labelText: 'NAT reflection'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('System default')),
                  DropdownMenuItem(value: 'enable', child: Text('Enable')),
                  DropdownMenuItem(value: 'disable', child: Text('Disable')),
                ],
                onChanged: (value) => setState(() => _reflection = value),
              ),
              SwitchListTile(
                value: _noBinat,
                onChanged: (value) => setState(() => _noBinat = value),
                title: const Text('Exclude from later mappings'),
              ),
            ],
            if (widget.type == FirewallNatRuleType.outboundMapping) ...[
              SwitchListTile(
                value: _noNat,
                onChanged: (value) => setState(() => _noNat = value),
                title: const Text('Do not translate matching traffic'),
              ),
              if (!_noNat) ...[
                _textField(_target, 'Translation target', required: true),
                const SizedBox(height: 12),
                _textField(
                  _targetSubnet,
                  'Target subnet bits',
                  keyboardType: TextInputType.number,
                ),
                SwitchListTile(
                  value: _staticNatPort,
                  onChanged: (value) => setState(() => _staticNatPort = value),
                  title: const Text('Static source port'),
                ),
                if (!_staticNatPort) ...[
                  _textField(_natPort, 'Translated source port or range'),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String?>(
                  initialValue: _poolOptions,
                  decoration: const InputDecoration(labelText: 'Pool option'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Default')),
                    for (final value in outboundPoolOptions)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) => setState(() => _poolOptions = value),
                ),
                if (_poolOptions == 'source-hash') ...[
                  const SizedBox(height: 12),
                  _textField(_sourceHashKey, 'Source hash key'),
                ],
              ],
            ],
            SwitchListTile(
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
              title: const Text('Enabled'),
            ),
            if (widget.type != FirewallNatRuleType.oneToOne)
              SwitchListTile(
                value: _noSync,
                onChanged: (value) => setState(() => _noSync = value),
                title: const Text('Do not sync to HA peers'),
              ),
            _textField(_description, 'Description'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save and apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (value) => value == null || value.trim().isEmpty
              ? '$label is required.'
              : null
          : null,
    );
  }
}

String? _blankToNull(String value) {
  final text = value.trim();
  return text.isEmpty ? null : text;
}
