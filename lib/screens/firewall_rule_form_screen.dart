import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/firewall_rule.dart';
import '../models/pfrest_capabilities.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/firewall_rule_validation.dart';

class FirewallRuleFormScreen extends StatefulWidget {
  const FirewallRuleFormScreen({
    super.key,
    this.rule,
    this.availableInterfaces = const [],
    this.onPermissionDenied,
  });

  final FirewallRule? rule;
  final List<String> availableInterfaces;
  final VoidCallback? onPermissionDenied;

  @override
  State<FirewallRuleFormScreen> createState() =>
      _FirewallRuleFormScreenState();
}

class _FirewallRuleFormScreenState extends State<FirewallRuleFormScreen> {
  static const _fallbackInterfaces = ['wan', 'lan', 'opt1', 'opt2', 'any'];

  final _key = GlobalKey<FormState>();
  late String _type = widget.rule?.type ?? 'pass';
  late List<String> _interfaces = [...?widget.rule?.interfaces];
  late String _ipProtocol = widget.rule?.ipProtocol ?? 'inet';
  late String _protocol = widget.rule?.protocol ?? 'tcp';
  late bool _enabled = widget.rule?.enabled ?? true;
  late bool _floating = widget.rule?.floating ?? false;
  late bool _quick = widget.rule?.quick ?? false;
  late String _direction = widget.rule?.direction ?? 'any';
  late bool _sourceInverted = widget.rule?.sourceInverted ?? false;
  late bool _destinationInverted = widget.rule?.destinationInverted ?? false;
  late bool _log = widget.rule?.log ?? false;
  late String _stateType = widget.rule?.stateType ?? 'keep state';
  late bool _tcpFlagsAny = widget.rule?.tcpFlagsAny ?? false;
  late final Set<String> _tcpFlagsOutOf = {...?widget.rule?.tcpFlagsOutOf};
  late final Set<String> _tcpFlagsSet = {...?widget.rule?.tcpFlagsSet};

  late final _source = TextEditingController(
    text: widget.rule?.sourceNetwork ?? 'any',
  );
  late final _destination = TextEditingController(
    text: widget.rule?.destinationNetwork ?? 'any',
  );
  late final _sourcePortFrom = TextEditingController(
    text: _portParts(widget.rule?.sourcePort).$1,
  );
  late final _sourcePortTo = TextEditingController(
    text: _portParts(widget.rule?.sourcePort).$2,
  );
  late final _destinationPortFrom = TextEditingController(
    text: _portParts(widget.rule?.destinationPort).$1,
  );
  late final _destinationPortTo = TextEditingController(
    text: _portParts(widget.rule?.destinationPort).$2,
  );
  late final _description = TextEditingController(
    text: widget.rule?.description ?? '',
  );
  late final _icmpTypes = TextEditingController(
    text: (widget.rule?.icmpTypes ?? const ['any']).join(', '),
  );
  late final _tag = TextEditingController(text: widget.rule?.tag ?? '');
  late final _gateway = TextEditingController(text: widget.rule?.gateway ?? '');
  late final _schedule = TextEditingController(text: widget.rule?.schedule ?? '');
  late final _dnpipe = TextEditingController(text: widget.rule?.dnpipe ?? '');
  late final _pdnpipe = TextEditingController(text: widget.rule?.pdnpipe ?? '');
  late final _defaultQueue =
      TextEditingController(text: widget.rule?.defaultQueue ?? '');
  late final _ackQueue =
      TextEditingController(text: widget.rule?.ackQueue ?? '');
  late final _placement = TextEditingController(
    text: widget.rule?.placement?.toString() ?? '',
  );

  FirewallRuleValidationResult? _validation;
  bool _saving = false;
  bool _permissionDenied = false;

  bool get _editing => widget.rule != null;
  bool get _supportsPorts =>
      _protocol == 'tcp' || _protocol == 'udp' || _protocol == 'tcp/udp';
  bool get _isTcp => _protocol == 'tcp';
  bool get _isIpv4Icmp => _protocol == 'icmp' && _ipProtocol == 'inet';

  @override
  void initState() {
    super.initState();
    if (_interfaces.isEmpty) _interfaces = ['wan'];
  }

  @override
  void dispose() {
    for (final controller in [
      _source,
      _destination,
      _sourcePortFrom,
      _sourcePortTo,
      _destinationPortFrom,
      _destinationPortTo,
      _description,
      _icmpTypes,
      _tag,
      _gateway,
      _schedule,
      _dnpipe,
      _pdnpipe,
      _defaultQueue,
      _ackQueue,
      _placement,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  PfRestOperationCapability? _operation(PfSenseSessionProvider session) {
    return session.capabilities?.operation(
      '/api/v2/firewall/rule',
      _editing ? 'PATCH' : 'POST',
    );
  }

  bool _supports(PfRestOperationCapability? operation, String field) =>
      operation == null || operation.field(field) != null;

  bool _schemaBlocksWrite(
    PfSenseSessionProvider session,
    PfRestOperationCapability? operation,
  ) =>
      session.capabilities?.isAvailable == true && operation == null;

  FirewallRule _draft() {
    final base = widget.rule ?? FirewallRule(createdTime: '');
    return base.copyWith(
      type: _type,
      interfaces: _interfaces,
      ipProtocol: _ipProtocol,
      protocol: _protocol == 'any' ? null : _protocol,
      icmpTypes: _csv(_icmpTypes.text, fallback: const ['any']),
      sourceNetwork: _source.text.trim(),
      sourceInverted: _sourceInverted,
      sourcePort: _supportsPorts
          ? _portSpec(_sourcePortFrom.text, _sourcePortTo.text)
          : null,
      destinationNetwork: _destination.text.trim(),
      destinationInverted: _destinationInverted,
      destinationPort: _supportsPorts
          ? _portSpec(_destinationPortFrom.text, _destinationPortTo.text)
          : null,
      description: _description.text.trim(),
      enabled: _enabled,
      log: _log,
      tag: _tag.text.trim(),
      stateType: _stateType,
      tcpFlagsAny: _isTcp ? _tcpFlagsAny : false,
      tcpFlagsOutOf:
          _isTcp && !_tcpFlagsAny ? _tcpFlagsOutOf.toList() : const [],
      tcpFlagsSet:
          _isTcp && !_tcpFlagsAny ? _tcpFlagsSet.toList() : const [],
      gateway: _nullable(_gateway.text),
      schedule: _nullable(_schedule.text),
      dnpipe: _nullable(_dnpipe.text),
      pdnpipe: _nullable(_pdnpipe.text),
      defaultQueue: _nullable(_defaultQueue.text),
      ackQueue: _nullable(_ackQueue.text),
      floating: _editing ? widget.rule!.floating : _floating,
      quick: _floating ? _quick : false,
      direction: _floating ? _direction : 'any',
      placement: int.tryParse(_placement.text.trim()),
    );
  }

  Future<void> _save() async {
    if (_saving || _permissionDenied) return;
    final session = context.read<PfSenseSessionProvider>();
    final strings = AppLocalizations.of(context);
    if (!session.connected || session.service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings?.disconnectedMessage ?? 'Disconnected')),
      );
      return;
    }

    final operation = _operation(session);
    if (_schemaBlocksWrite(session, operation)) return;

    final draft = _draft();
    final validation = validateFirewallRule(draft, operation: operation);
    setState(() => _validation = validation);
    if (!_key.currentState!.validate() || !validation.isValid) return;

    if (_placementChanged(draft) && !await _confirmPlacement(draft)) return;
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      final ruleService = session.firewallRuleService;
      if (ruleService != null) {
        if (_editing) {
          await ruleService.update(draft, operation: operation);
        } else {
          await ruleService.create(draft, operation: operation);
        }
      } else {
        final legacy = session.service!;
        if (_editing) {
          await legacy.updateFirewallRule(
            draft.id!,
            draft.toUpdatePayload(operation: operation),
          );
        } else {
          await legacy.createFirewallRule(
            draft.toCreatePayload(operation: operation),
          );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (error.isPermissionError) {
        widget.onPermissionDenied?.call();
        if (mounted) {
          setState(() => _permissionDenied = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permission denied (403). Firewall rule editing is now read-only for this session.',
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _placementChanged(FirewallRule draft) =>
      draft.placement != null && draft.placement != widget.rule?.placement;

  Future<bool> _confirmPlacement(FirewallRule draft) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_editing ? 'Move firewall rule?' : 'Place firewall rule?'),
            content: Text(
              'Place this rule at position ${draft.placement}. Firewall rules are order-sensitive; an incorrect position can block or allow unintended traffic.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_editing ? 'Move rule' : 'Place rule'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final session = context.watch<PfSenseSessionProvider>();
    final operation = _operation(session);
    final blocked = _schemaBlocksWrite(session, operation);
    final canSave =
        session.connected && !_saving && !_permissionDenied && !blocked;

    final typeValues = firewallRuleAllowedValues(
      operation,
      'type',
      const ['pass', 'block', 'reject'],
    );
    final ipValues = firewallRuleAllowedValues(
      operation,
      'ipprotocol',
      const ['inet', 'inet6', 'inet46'],
    );
    final protocolValues = <String>[
      'any',
      ...firewallRuleAllowedValues(
        operation,
        'protocol',
        firewallRuleProtocols,
      ),
    ];
    final stateValues = firewallRuleAllowedValues(
      operation,
      'statetype',
      firewallRuleStateTypes,
    );
    final directionValues = firewallRuleAllowedValues(
      operation,
      'direction',
      const ['any', 'in', 'out'],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing
              ? (strings?.editRule ?? 'Edit rule')
              : (strings?.addRule ?? 'Add rule'),
        ),
      ),
      body: Form(
        key: _key,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (blocked)
              _notice(
                Icons.extension_off_outlined,
                'Firewall rule writes are not reported by the installed pfREST schema.',
              ),
            if (_permissionDenied)
              _notice(
                Icons.lock_outline,
                'This credential cannot write firewall rules. Reconnect after changing its permissions.',
              ),
            SegmentedButton<String>(
              selected: {_safeValue(_type, typeValues)},
              segments: [
                for (final value in typeValues)
                  ButtonSegment(value: value, label: Text(_title(value))),
              ],
              onSelectionChanged: canSave
                  ? (values) => setState(() => _type = values.first)
                  : null,
            ),
            if (_validation?.errorFor('type') != null)
              _errorText(_validation!.errorFor('type')!),
            SwitchListTile(
              value: _enabled,
              onChanged:
                  canSave ? (value) => setState(() => _enabled = value) : null,
              title: Text(
                _enabled
                    ? (strings?.enabled ?? 'Enabled')
                    : (strings?.disabled ?? 'Disabled'),
              ),
            ),
            _interfaceEditor(canSave),
            const SizedBox(height: 12),
            _drop(
              label: 'IP version',
              value: _safeValue(_ipProtocol, ipValues),
              values: ipValues,
              onChanged: canSave
                  ? (value) => setState(() {
                        _ipProtocol = value;
                        if (!_isIpv4Icmp) _icmpTypes.text = 'any';
                      })
                  : null,
              key: const Key('firewall-ip-protocol'),
              itemLabel: _ipProtocolLabel,
              errorText: _validation?.errorFor('ipprotocol'),
            ),
            const SizedBox(height: 12),
            _drop(
              label: strings?.protocol ?? 'Protocol',
              value: _safeValue(_protocol, protocolValues),
              values: protocolValues,
              onChanged: canSave ? _setProtocol : null,
              key: const Key('firewall-protocol'),
              itemLabel: (value) => value.toUpperCase(),
              errorText: _validation?.errorFor('protocol'),
            ),
            const SizedBox(height: 12),
            _field(
              _source,
              strings?.source ?? 'Source',
              validator: (_) =>
                  _validation?.errorFor('source') ?? _required(_source.text),
            ),
            _field(
              _destination,
              strings?.destination ?? 'Destination',
              validator: (_) => _validation?.errorFor('destination') ??
                  _required(_destination.text),
            ),
            if (_supportsPorts) ...[
              _portEditor(
                title: 'Source port',
                from: _sourcePortFrom,
                to: _sourcePortTo,
                fromKey: const Key('source-port-from'),
                toKey: const Key('source-port-to'),
                error: _validation?.errorFor('source_port'),
              ),
              _portEditor(
                title: 'Destination port',
                from: _destinationPortFrom,
                to: _destinationPortTo,
                fromKey: const Key('destination-port-from'),
                toKey: const Key('destination-port-to'),
                error: _validation?.errorFor('destination_port'),
              ),
            ],
            _field(
              _description,
              strings?.description ?? 'Description',
              maxLines: 3,
              validator: (_) => _validation?.errorFor('descr'),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              key: const Key('firewall-rule-advanced'),
              initiallyExpanded: _hasAdvancedValues(),
              tilePadding: EdgeInsets.zero,
              title: const Text('Advanced options'),
              subtitle: const Text(
                'Logging, floating rules, policy routing, state handling and traffic shaping',
              ),
              children: [
                if (_supports(operation, 'floating'))
                  SwitchListTile(
                    key: const Key('firewall-floating'),
                    contentPadding: EdgeInsets.zero,
                    value: _floating,
                    onChanged: !_editing && canSave
                        ? (value) => setState(() {
                              _floating = value;
                              if (!value && _interfaces.length > 1) {
                                _interfaces = [_interfaces.first];
                              }
                              if (!value) {
                                _quick = false;
                                _direction = 'any';
                              }
                            })
                        : null,
                    title: const Text('Floating rule'),
                    subtitle: Text(
                      _editing
                          ? 'pfREST does not allow an existing rule to change between interface and floating mode.'
                          : 'Floating rules can match several interfaces and directions.',
                    ),
                  ),
                if (_floating && _supports(operation, 'quick'))
                  SwitchListTile(
                    key: const Key('firewall-quick'),
                    contentPadding: EdgeInsets.zero,
                    value: _quick,
                    onChanged: canSave
                        ? (value) => setState(() => _quick = value)
                        : null,
                    title: const Text('Quick match'),
                    subtitle: const Text(
                      'Apply the action immediately when this rule matches.',
                    ),
                  ),
                if (_floating && _supports(operation, 'direction'))
                  _drop(
                    label: 'Direction',
                    value: _safeValue(_direction, directionValues),
                    values: directionValues,
                    onChanged: canSave
                        ? (value) => setState(() => _direction = value)
                        : null,
                    key: const Key('firewall-direction'),
                    errorText: _validation?.errorFor('direction'),
                  ),
                if (_supports(operation, 'log'))
                  SwitchListTile(
                    key: const Key('firewall-log'),
                    contentPadding: EdgeInsets.zero,
                    value: _log,
                    onChanged:
                        canSave ? (value) => setState(() => _log = value) : null,
                    title: const Text('Log matching traffic'),
                  ),
                if (_supports(operation, 'tag'))
                  _field(
                    _tag,
                    'Packet tag',
                    validator: (_) => _validation?.errorFor('tag'),
                  ),
                SwitchListTile(
                  key: const Key('firewall-source-invert'),
                  contentPadding: EdgeInsets.zero,
                  value: _sourceInverted,
                  onChanged: canSave
                      ? (value) => setState(() => _sourceInverted = value)
                      : null,
                  title: const Text('Invert source'),
                ),
                SwitchListTile(
                  key: const Key('firewall-destination-invert'),
                  contentPadding: EdgeInsets.zero,
                  value: _destinationInverted,
                  onChanged: canSave
                      ? (value) => setState(() => _destinationInverted = value)
                      : null,
                  title: const Text('Invert destination'),
                ),
                if (_isIpv4Icmp && _supports(operation, 'icmptype'))
                  _field(
                    _icmpTypes,
                    'ICMP types',
                    key: const Key('firewall-icmp-types'),
                    helperText:
                        'Comma-separated values; use “any” for all types.',
                    validator: (_) => _validation?.errorFor('icmptype'),
                  ),
                if (_supports(operation, 'statetype'))
                  _drop(
                    label: 'State type',
                    value: _safeValue(_stateType, stateValues),
                    values: stateValues,
                    onChanged: canSave
                        ? (value) => setState(() => _stateType = value)
                        : null,
                    key: const Key('firewall-state-type'),
                    errorText: _validation?.errorFor('statetype'),
                  ),
                if (_isTcp && _supports(operation, 'tcp_flags_any'))
                  _tcpFlagEditor(canSave),
                if (_supports(operation, 'gateway'))
                  _field(
                    _gateway,
                    'Gateway or gateway group',
                    key: const Key('firewall-gateway'),
                    helperText: 'Leave empty to use the default route.',
                    validator: (_) => _validation?.errorFor('gateway'),
                  ),
                if (_supports(operation, 'sched'))
                  _field(
                    _schedule,
                    'Schedule',
                    key: const Key('firewall-schedule'),
                    helperText: 'Existing pfSense schedule name.',
                  ),
                if (_supports(operation, 'dnpipe'))
                  _field(
                    _dnpipe,
                    'Inbound limiter',
                    key: const Key('firewall-dnpipe'),
                  ),
                if (_supports(operation, 'pdnpipe'))
                  _field(
                    _pdnpipe,
                    'Outbound limiter',
                    key: const Key('firewall-pdnpipe'),
                    validator: (_) => _validation?.errorFor('pdnpipe'),
                  ),
                if (_supports(operation, 'defaultqueue'))
                  _field(
                    _defaultQueue,
                    'Default queue',
                    key: const Key('firewall-default-queue'),
                  ),
                if (_supports(operation, 'ackqueue'))
                  _field(
                    _ackQueue,
                    'ACK queue',
                    key: const Key('firewall-ack-queue'),
                    validator: (_) => _validation?.errorFor('ackqueue'),
                  ),
                if (_supports(operation, 'placement'))
                  _field(
                    _placement,
                    'Rule placement',
                    key: const Key('firewall-placement'),
                    number: true,
                    helperText:
                        'Optional configuration position. Changing this moves the rule and requires confirmation.',
                    validator: (_) => _validation?.errorFor('placement'),
                  ),
              ],
            ),
            if (_validation?.summary != null) ...[
              const SizedBox(height: 8),
              _errorText(_validation!.summary!),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('save-firewall-rule'),
              onPressed: canSave ? _save : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : (strings?.save ?? 'Save')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _interfaceEditor(bool enabled) {
    final values = <String>{
      ..._fallbackInterfaces,
      ...widget.availableInterfaces,
      ..._interfaces,
    }.where((value) => value.trim().isNotEmpty).toList();

    if (!_floating) {
      final selected =
          values.contains(_interfaces.first) ? _interfaces.first : values.first;
      return DropdownButtonFormField<String>(
        key: const Key('firewall-interface'),
        initialValue: selected,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context)?.interface ?? 'Interface',
          errorText: _validation?.errorFor('interface'),
        ),
        items: [
          for (final value in values)
            DropdownMenuItem(value: value, child: Text(value.toUpperCase())),
        ],
        onChanged: enabled
            ? (value) {
                if (value != null) setState(() => _interfaces = [value]);
              }
            : null,
      );
    }

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Interfaces',
        helperText: 'Select one or more interfaces for this floating rule.',
        errorText: _validation?.errorFor('interface'),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final value in values)
            FilterChip(
              key: Key('firewall-interface-$value'),
              label: Text(value.toUpperCase()),
              selected: _interfaces.contains(value),
              onSelected: enabled
                  ? (selected) => setState(() {
                        if (selected) {
                          if (!_interfaces.contains(value)) {
                            _interfaces.add(value);
                          }
                        } else if (_interfaces.length > 1) {
                          _interfaces.remove(value);
                        }
                      })
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _portEditor({
    required String title,
    required TextEditingController from,
    required TextEditingController to,
    required Key fromKey,
    required Key toKey,
    required String? error,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text(
            'Use a port or alias in the first field. Add an ending port only for a numeric range.',
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: fromKey,
                  controller: from,
                  decoration: InputDecoration(
                    labelText: 'Port or alias',
                    errorText: error,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: toKey,
                  controller: to,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Range end'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tcpFlagEditor(bool enabled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('firewall-tcp-flags-any'),
          contentPadding: EdgeInsets.zero,
          value: _tcpFlagsAny,
          onChanged: enabled
              ? (value) => setState(() => _tcpFlagsAny = value)
              : null,
          title: const Text('Allow any TCP flags'),
        ),
        if (!_tcpFlagsAny) ...[
          Text('Flags out of', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 6,
            children: [
              for (final flag in firewallRuleTcpFlags)
                FilterChip(
                  key: Key('firewall-tcp-out-$flag'),
                  label: Text(flag.toUpperCase()),
                  selected: _tcpFlagsOutOf.contains(flag),
                  onSelected: enabled
                      ? (selected) => setState(() {
                            if (selected) {
                              _tcpFlagsOutOf.add(flag);
                            } else {
                              _tcpFlagsOutOf.remove(flag);
                              _tcpFlagsSet.remove(flag);
                            }
                          })
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Flags that must be set',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final flag in firewallRuleTcpFlags)
                FilterChip(
                  key: Key('firewall-tcp-set-$flag'),
                  label: Text(flag.toUpperCase()),
                  selected: _tcpFlagsSet.contains(flag),
                  onSelected: enabled && _tcpFlagsOutOf.contains(flag)
                      ? (selected) => setState(() {
                            selected
                                ? _tcpFlagsSet.add(flag)
                                : _tcpFlagsSet.remove(flag);
                          })
                      : null,
                ),
            ],
          ),
          if (_validation?.errorFor('tcp_flags_set') != null)
            _errorText(_validation!.errorFor('tcp_flags_set')!),
          if (_validation?.errorFor('tcp_flags') != null)
            _errorText(_validation!.errorFor('tcp_flags')!),
        ],
      ],
    );
  }

  Widget _drop({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String>? onChanged,
    Key? key,
    String Function(String)? itemLabel,
    String? errorText,
  }) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: _safeValue(value, values),
      decoration: InputDecoration(labelText: label, errorText: errorText),
      items: [
        for (final item in values)
          DropdownMenuItem(
            value: item,
            child: Text(itemLabel?.call(item) ?? _title(item)),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (value) {
              if (value != null) onChanged(value);
            },
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    Key? key,
    bool number = false,
    int maxLines = 1,
    String? helperText,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: key,
        controller: controller,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, helperText: helperText),
        validator: validator,
      ),
    );
  }

  Widget _notice(IconData icon, String text) =>
      Card(child: ListTile(leading: Icon(icon), title: Text(text)));

  Widget _errorText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  void _setProtocol(String value) {
    setState(() {
      _protocol = value;
      if (!_supportsPorts) {
        _sourcePortFrom.clear();
        _sourcePortTo.clear();
        _destinationPortFrom.clear();
        _destinationPortTo.clear();
      }
      if (!_isIpv4Icmp) _icmpTypes.text = 'any';
      if (!_isTcp) {
        _tcpFlagsAny = false;
        _tcpFlagsOutOf.clear();
        _tcpFlagsSet.clear();
        if (_stateType == 'synproxy state') _stateType = 'keep state';
      }
    });
  }

  bool _hasAdvancedValues() {
    final rule = widget.rule;
    return rule != null &&
        (rule.floating ||
            rule.log ||
            rule.sourceInverted ||
            rule.destinationInverted ||
            rule.tag.isNotEmpty ||
            rule.stateType != 'keep state' ||
            rule.tcpFlagsAny ||
            rule.tcpFlagsOutOf.isNotEmpty ||
            rule.tcpFlagsSet.isNotEmpty ||
            rule.gateway != null ||
            rule.schedule != null ||
            rule.dnpipe != null ||
            rule.pdnpipe != null ||
            rule.defaultQueue != null ||
            rule.ackQueue != null ||
            rule.placement != null);
  }

  static (String, String) _portParts(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return ('', '');
    final parts = text.split(RegExp('[:-]'));
    if (parts.length == 2 &&
        int.tryParse(parts.first) != null &&
        int.tryParse(parts.last) != null) {
      return (parts.first, parts.last);
    }
    return (text, '');
  }

  static String? _portSpec(String from, String to) {
    final start = from.trim();
    final end = to.trim();
    if (start.isEmpty && end.isEmpty) return null;
    if (end.isEmpty) return start;
    return '$start:$end';
  }

  static List<String> _csv(String value, {List<String> fallback = const []}) {
    final values = value
        .split(',')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return values.isEmpty ? fallback : values;
  }

  static String? _nullable(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String _safeValue(String value, List<String> values) =>
      values.contains(value) ? value : values.first;

  static String _title(String value) {
    return value
        .split(' ')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static String? _required(String value) =>
      value.trim().isEmpty ? 'Required' : null;

  static String _ipProtocolLabel(String value) => switch (value) {
        'inet6' => 'IPv6',
        'inet46' => 'IPv4 + IPv6',
        _ => 'IPv4',
      };
}
