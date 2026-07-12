import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/firewall_nat.dart';
import '../providers/session_provider.dart';
import '../services/pfrest_feature_registry.dart';
import '../utils/api_exception.dart';
import '../widgets/slide_to_confirm.dart';
import 'firewall_nat_form_screen.dart';

class FirewallNatScreen extends StatefulWidget {
  const FirewallNatScreen({super.key});

  @override
  State<FirewallNatScreen> createState() => _FirewallNatScreenState();
}

class _FirewallNatScreenState extends State<FirewallNatScreen> {
  List<NatPortForward> _portForwards = const [];
  List<NatOneToOneMapping> _oneToOne = const [];
  List<NatOutboundMapping> _outbound = const [];
  OutboundNatMode? _outboundMode;
  final Map<PfRestFeature, Object> _errors = {};
  final Set<PfRestFeature> _permissionDenied = {};
  bool _loading = false;
  bool _actionBusy = false;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;
    if (!changed) return;

    _requestGeneration++;
    _loadedSessionGeneration = session.sessionGeneration;
    _loadedProfileId = profileId;
    _portForwards = const [];
    _oneToOne = const [];
    _outbound = const [];
    _outboundMode = null;
    _errors.clear();
    _permissionDenied.clear();
    if (session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    super.dispose();
  }

  PfRestFeatureRegistry _registry(PfSenseSessionProvider session) {
    return PfRestFeatureRegistry(
      activeProfileId: session.selectedProfile?.id,
      capabilities: session.capabilities,
    );
  }

  bool _canAttempt(
    PfSenseSessionProvider session,
    PfRestFeature feature,
  ) {
    return _registry(session).decision(feature).canAttempt;
  }

  bool _canWrite(PfSenseSessionProvider session, PfRestFeature feature) {
    return !_permissionDenied.contains(feature) && _canAttempt(session, feature);
  }

  Future<void> _load() async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.firewallNatService;
    if (!session.connected || service == null) return;

    final request = ++_requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    setState(() {
      _loading = true;
      _errors.clear();
    });

    final portDecision =
        _registry(session).decision(PfRestFeature.natPortForwardsRead);
    final oneDecision = _registry(session).decision(PfRestFeature.natOneToOneRead);
    final modeDecision =
        _registry(session).decision(PfRestFeature.natOutboundModeRead);
    final outboundDecision =
        _registry(session).decision(PfRestFeature.natOutboundMappingsRead);

    final portResult = portDecision.canAttempt
        ? await _capture(service.listPortForwards)
        : null;
    final oneResult = oneDecision.canAttempt
        ? await _capture(service.listOneToOneMappings)
        : null;
    final modeResult = modeDecision.canAttempt
        ? await _capture(service.getOutboundMode)
        : null;
    final outboundResult = outboundDecision.canAttempt
        ? await _capture(service.listOutboundMappings)
        : null;

    if (!mounted ||
        request != _requestGeneration ||
        sessionGeneration != session.sessionGeneration ||
        profileId != session.selectedProfile?.id) {
      return;
    }

    setState(() {
      if (portResult != null) {
        if (portResult.error == null) {
          _portForwards = portResult.value!;
        } else {
          _errors[PfRestFeature.natPortForwardsRead] = portResult.error!;
        }
      }
      if (oneResult != null) {
        if (oneResult.error == null) {
          _oneToOne = oneResult.value!;
        } else {
          _errors[PfRestFeature.natOneToOneRead] = oneResult.error!;
        }
      }
      if (modeResult != null) {
        if (modeResult.error == null) {
          _outboundMode = modeResult.value;
        } else {
          _errors[PfRestFeature.natOutboundModeRead] = modeResult.error!;
        }
      }
      if (outboundResult != null) {
        if (outboundResult.error == null) {
          _outbound = outboundResult.value!;
        } else {
          _errors[PfRestFeature.natOutboundMappingsRead] = outboundResult.error!;
        }
      }
      _loading = false;
    });
  }

  Future<_Outcome<T>> _capture<T>(Future<T> Function() operation) async {
    try {
      return _Outcome.success(await operation());
    } catch (error) {
      return _Outcome.failure(error);
    }
  }

  Future<void> _openForm(FirewallNatRuleType type, [Object? rule]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FirewallNatFormScreen(type: type, rule: rule),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _togglePortForward(NatPortForward rule) async {
    final id = rule.id;
    if (id == null) return;
    await _runWrite(
      feature: PfRestFeature.natPortForwardUpdate,
      confirmationTitle: rule.enabled
          ? 'Disable port forward?'
          : 'Enable port forward?',
      confirmationBody:
          'This will ${rule.enabled ? 'disable' : 'enable'} ${_ruleName(rule.description, 'port forward #$id')} and apply firewall changes.',
      operation: (session) => session.firewallNatService!
          .setPortForwardEnabled(rule, !rule.enabled),
    );
  }

  Future<void> _toggleOneToOne(NatOneToOneMapping mapping) async {
    final id = mapping.id;
    if (id == null) return;
    await _runWrite(
      feature: PfRestFeature.natOneToOneUpdate,
      confirmationTitle:
          mapping.enabled ? 'Disable 1:1 mapping?' : 'Enable 1:1 mapping?',
      confirmationBody:
          'This will ${mapping.enabled ? 'disable' : 'enable'} ${_ruleName(mapping.description, '1:1 mapping #$id')} and apply firewall changes.',
      operation: (session) => session.firewallNatService!
          .setOneToOneEnabled(mapping, !mapping.enabled),
    );
  }

  Future<void> _toggleOutbound(NatOutboundMapping mapping) async {
    final id = mapping.id;
    if (id == null) return;
    await _runWrite(
      feature: PfRestFeature.natOutboundMappingUpdate,
      confirmationTitle: mapping.enabled
          ? 'Disable outbound mapping?'
          : 'Enable outbound mapping?',
      confirmationBody:
          'This will ${mapping.enabled ? 'disable' : 'enable'} ${_ruleName(mapping.description, 'outbound mapping #$id')} and apply firewall changes.',
      operation: (session) => session.firewallNatService!
          .setOutboundMappingEnabled(mapping, !mapping.enabled),
    );
  }

  Future<void> _changeOutboundMode(OutboundNatMode mode) async {
    if (mode == _outboundMode || _actionBusy) return;
    final session = context.read<PfSenseSessionProvider>();
    final feature = PfRestFeature.natOutboundModeUpdate;
    if (!_canWrite(session, feature)) {
      _showFeatureMessage(session, feature);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Change outbound NAT to ${mode.label}?'),
        content: Text(
          '${mode.description}\n\nChanging outbound NAT mode can immediately alter internet access for internal networks. The change will be applied after pfREST accepts it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change and apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await session.firewallNatService!.updateOutboundMode(mode);
      await _load();
    } catch (error) {
      _recordWriteError(feature, error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _delete(
    FirewallNatRuleType type,
    int id,
    String label,
  ) async {
    final feature = switch (type) {
      FirewallNatRuleType.portForward => PfRestFeature.natPortForwardDelete,
      FirewallNatRuleType.oneToOne => PfRestFeature.natOneToOneDelete,
      FirewallNatRuleType.outboundMapping =>
        PfRestFeature.natOutboundMappingDelete,
    };
    final session = context.read<PfSenseSessionProvider>();
    if (!_canWrite(session, feature)) {
      _showFeatureMessage(session, feature);
      return;
    }

    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Delete NAT rule?',
      body:
          'This permanently deletes $label and applies the firewall configuration. Existing connections may be interrupted.',
      slideLabel: 'Slide to delete and apply',
      icon: Icons.delete_forever_outlined,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      final service = session.firewallNatService!;
      switch (type) {
        case FirewallNatRuleType.portForward:
          await service.deletePortForward(id);
        case FirewallNatRuleType.oneToOne:
          await service.deleteOneToOneMapping(id);
        case FirewallNatRuleType.outboundMapping:
          await service.deleteOutboundMapping(id);
      }
      await _load();
    } catch (error) {
      _recordWriteError(feature, error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _runWrite({
    required PfRestFeature feature,
    required String confirmationTitle,
    required String confirmationBody,
    required Future<void> Function(PfSenseSessionProvider session) operation,
  }) async {
    if (_actionBusy) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!_canWrite(session, feature)) {
      _showFeatureMessage(session, feature);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(confirmationTitle),
        content: Text(confirmationBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm and apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await operation(session);
      await _load();
    } catch (error) {
      _recordWriteError(feature, error);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _recordWriteError(PfRestFeature feature, Object error) {
    if (error is ApiException && error.isPermissionError && mounted) {
      setState(() => _permissionDenied.add(feature));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(pfRestFeatureRequestErrorMessage(feature, error))),
    );
  }

  void _showFeatureMessage(
    PfSenseSessionProvider session,
    PfRestFeature feature,
  ) {
    final message = _permissionDenied.contains(feature)
        ? 'This operation is read-only because the saved credential was denied permission during this session.'
        : _registry(session).decision(feature).message;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('NAT management'),
          actions: [
            IconButton(
              tooltip: 'Refresh NAT configuration',
              onPressed: _loading || !session.connected ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Port forwards'),
              Tab(text: '1:1 NAT'),
              Tab(text: 'Outbound NAT'),
              Tab(text: 'NPT'),
            ],
          ),
        ),
        body: !session.connected
            ? _message(Icons.cloud_off_outlined, 'Disconnected')
            : Column(
                children: [
                  if (_loading) const LinearProgressIndicator(minHeight: 3),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _portForwardTab(session),
                        _oneToOneTab(session),
                        _outboundTab(session),
                        _nptTab(session),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _portForwardTab(PfSenseSessionProvider session) {
    const read = PfRestFeature.natPortForwardsRead;
    final decision = _registry(session).decision(read);
    if (!decision.canAttempt) return _unsupported(decision.message);
    final error = _errors[read];
    final canCreate = _canWrite(session, PfRestFeature.natPortForwardCreate);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader(
          title: 'Port forwards',
          subtitle:
              'Translate inbound traffic to an internal host. Linked firewall-rule handling follows the selected associated rule mode.',
          onAdd: canCreate && !_actionBusy
              ? () => _openForm(FirewallNatRuleType.portForward)
              : null,
        ),
        if (error != null)
          _message(
            Icons.error_outline,
            pfRestFeatureRequestErrorMessage(read, error),
          )
        else if (!_loading && _portForwards.isEmpty)
          _message(Icons.call_received_outlined, 'No port forwards returned.'),
        for (final rule in _portForwards)
          Card(
            child: ListTile(
              leading: Icon(
                rule.enabled ? Icons.call_received : Icons.pause_circle_outline,
              ),
              title: Text(_ruleName(rule.description, 'Port forward #${rule.id ?? '-'}')),
              subtitle: Text(
                '${rule.interface} | ${rule.protocol} | ${rule.destination}'
                '${rule.destinationPort == null ? '' : ':${rule.destinationPort}'}'
                ' → ${rule.target}'
                '${rule.localPort == null ? '' : ':${rule.localPort}'}'
                '${rule.associatedRuleId.isEmpty ? '' : '\nFirewall rule: ${rule.associatedRuleId}'}',
              ),
              isThreeLine: rule.associatedRuleId.isNotEmpty,
              onTap: _canWrite(session, PfRestFeature.natPortForwardUpdate)
                  ? () => _openForm(FirewallNatRuleType.portForward, rule)
                  : null,
              trailing: _ruleMenu(
                enabled: rule.enabled,
                canUpdate:
                    _canWrite(session, PfRestFeature.natPortForwardUpdate),
                canDelete:
                    _canWrite(session, PfRestFeature.natPortForwardDelete),
                onToggle: () => _togglePortForward(rule),
                onDelete: rule.id == null
                    ? null
                    : () => _delete(
                          FirewallNatRuleType.portForward,
                          rule.id!,
                          _ruleName(rule.description, 'port forward #${rule.id}'),
                        ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _oneToOneTab(PfSenseSessionProvider session) {
    const read = PfRestFeature.natOneToOneRead;
    final decision = _registry(session).decision(read);
    if (!decision.canAttempt) return _unsupported(decision.message);
    final error = _errors[read];
    final canCreate = _canWrite(session, PfRestFeature.natOneToOneCreate);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader(
          title: '1:1 NAT mappings',
          subtitle:
              'Map an external address to an internal address or network on a selected interface.',
          onAdd: canCreate && !_actionBusy
              ? () => _openForm(FirewallNatRuleType.oneToOne)
              : null,
        ),
        if (error != null)
          _message(
            Icons.error_outline,
            pfRestFeatureRequestErrorMessage(read, error),
          )
        else if (!_loading && _oneToOne.isEmpty)
          _message(Icons.compare_arrows, 'No 1:1 mappings returned.'),
        for (final mapping in _oneToOne)
          Card(
            child: ListTile(
              leading: Icon(
                mapping.enabled ? Icons.compare_arrows : Icons.pause_circle_outline,
              ),
              title: Text(
                _ruleName(mapping.description, '1:1 mapping #${mapping.id ?? '-'}'),
              ),
              subtitle: Text(
                '${mapping.interface} | ${mapping.external} ↔ ${mapping.source}\nDestination: ${mapping.destination}',
              ),
              isThreeLine: true,
              onTap: _canWrite(session, PfRestFeature.natOneToOneUpdate)
                  ? () => _openForm(FirewallNatRuleType.oneToOne, mapping)
                  : null,
              trailing: _ruleMenu(
                enabled: mapping.enabled,
                canUpdate: _canWrite(session, PfRestFeature.natOneToOneUpdate),
                canDelete: _canWrite(session, PfRestFeature.natOneToOneDelete),
                onToggle: () => _toggleOneToOne(mapping),
                onDelete: mapping.id == null
                    ? null
                    : () => _delete(
                          FirewallNatRuleType.oneToOne,
                          mapping.id!,
                          _ruleName(mapping.description, '1:1 mapping #${mapping.id}'),
                        ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _outboundTab(PfSenseSessionProvider session) {
    final modeDecision =
        _registry(session).decision(PfRestFeature.natOutboundModeRead);
    final mappingDecision =
        _registry(session).decision(PfRestFeature.natOutboundMappingsRead);
    if (!modeDecision.canAttempt && !mappingDecision.canAttempt) {
      return _unsupported(
        '${modeDecision.message}\n${mappingDecision.message}',
      );
    }

    final modeError = _errors[PfRestFeature.natOutboundModeRead];
    final mappingError = _errors[PfRestFeature.natOutboundMappingsRead];
    final canChangeMode =
        _canWrite(session, PfRestFeature.natOutboundModeUpdate);
    final canCreate =
        _canWrite(session, PfRestFeature.natOutboundMappingCreate);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader(
          title: 'Outbound NAT',
          subtitle:
              'Automatic, hybrid and manual modes determine whether pfSense generates mappings or uses the manual list below.',
          onAdd: canCreate && !_actionBusy
              ? () => _openForm(FirewallNatRuleType.outboundMapping)
              : null,
        ),
        if (modeDecision.canAttempt)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Outbound NAT mode',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (modeError != null)
                    Text(
                      pfRestFeatureRequestErrorMessage(
                        PfRestFeature.natOutboundModeRead,
                        modeError,
                      ),
                    )
                  else if (_outboundMode != null) ...[
                    DropdownButtonFormField<OutboundNatMode>(
                      initialValue: _outboundMode,
                      decoration: const InputDecoration(labelText: 'Mode'),
                      items: [
                        for (final mode in OutboundNatMode.values)
                          DropdownMenuItem(
                            value: mode,
                            child: Text(mode.label),
                          ),
                      ],
                      onChanged: canChangeMode && !_actionBusy
                          ? (mode) {
                              if (mode != null) _changeOutboundMode(mode);
                            }
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(_outboundMode!.description),
                  ],
                ],
              ),
            ),
          ),
        if (!mappingDecision.canAttempt)
          _unsupported(mappingDecision.message)
        else if (mappingError != null)
          _message(
            Icons.error_outline,
            pfRestFeatureRequestErrorMessage(
              PfRestFeature.natOutboundMappingsRead,
              mappingError,
            ),
          )
        else if (!_loading && _outbound.isEmpty)
          _message(Icons.upload_outlined, 'No manual outbound mappings returned.'),
        for (final mapping in _outbound)
          Card(
            child: ListTile(
              leading: Icon(
                mapping.enabled ? Icons.upload_outlined : Icons.pause_circle_outline,
              ),
              title: Text(
                _ruleName(
                  mapping.description,
                  'Outbound mapping #${mapping.id ?? '-'}',
                ),
              ),
              subtitle: Text(
                '${mapping.interface} | ${mapping.protocol ?? 'any'} | ${mapping.source} → ${mapping.destination}\n'
                '${mapping.noNat ? 'No NAT' : 'Translate to ${mapping.target ?? '-'}${mapping.staticNatPort ? ' (static port)' : ''}'}',
              ),
              isThreeLine: true,
              onTap: _canWrite(
                session,
                PfRestFeature.natOutboundMappingUpdate,
              )
                  ? () => _openForm(
                        FirewallNatRuleType.outboundMapping,
                        mapping,
                      )
                  : null,
              trailing: _ruleMenu(
                enabled: mapping.enabled,
                canUpdate: _canWrite(
                  session,
                  PfRestFeature.natOutboundMappingUpdate,
                ),
                canDelete: _canWrite(
                  session,
                  PfRestFeature.natOutboundMappingDelete,
                ),
                onToggle: () => _toggleOutbound(mapping),
                onDelete: mapping.id == null
                    ? null
                    : () => _delete(
                          FirewallNatRuleType.outboundMapping,
                          mapping.id!,
                          _ruleName(
                            mapping.description,
                            'outbound mapping #${mapping.id}',
                          ),
                        ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _nptTab(PfSenseSessionProvider session) {
    final operations = session.capabilities?.operations.values ?? const [];
    final reported = operations
        .where((operation) =>
            operation.path.toLowerCase().contains('/firewall/nat/') &&
            operation.path.toLowerCase().contains('npt'))
        .toList(growable: false);
    if (reported.isEmpty) {
      return _unsupported(
        'NPT is not reported by the connected pfREST OpenAPI schema. No NPT request is attempted.',
      );
    }
    return _unsupported(
      'This installation reports an NPT endpoint, but it does not match a documented pfREST NPT model supported by this release. The endpoint remains read-only to avoid unsafe writes.\n\nReported path: ${reported.first.path}',
    );
  }

  Widget _sectionHeader({
    required String title,
    required String subtitle,
    VoidCallback? onAdd,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _ruleMenu({
    required bool enabled,
    required bool canUpdate,
    required bool canDelete,
    required VoidCallback onToggle,
    VoidCallback? onDelete,
  }) {
    return PopupMenuButton<String>(
      enabled: !_actionBusy && (canUpdate || canDelete),
      onSelected: (value) {
        if (value == 'toggle') onToggle();
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (context) => [
        if (canUpdate)
          PopupMenuItem(
            value: 'toggle',
            child: Text(enabled ? 'Disable and apply' : 'Enable and apply'),
          ),
        if (canDelete && onDelete != null)
          const PopupMenuItem(
            value: 'delete',
            child: Text('Delete and apply'),
          ),
      ],
    );
  }

  Widget _unsupported(String message) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _message(Icons.info_outline, message),
      ],
    );
  }

  Widget _message(IconData icon, String text) {
    return Card(child: ListTile(leading: Icon(icon), title: Text(text)));
  }
}

String _ruleName(String description, String fallback) {
  final text = description.trim();
  return text.isEmpty ? fallback : text;
}

class _Outcome<T> {
  const _Outcome.success(this.value) : error = null;
  const _Outcome.failure(this.error) : value = null;

  final T? value;
  final Object? error;
}
