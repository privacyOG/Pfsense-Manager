import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/vpn_management.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/vpn_management_validation.dart';
import '../widgets/slide_to_confirm.dart';
import 'vpn_resource_form_screen.dart';
import 'vpn_settings_screen.dart';

class VpnManagementScreen extends StatefulWidget {
  const VpnManagementScreen({super.key});

  @override
  State<VpnManagementScreen> createState() => _VpnManagementScreenState();
}

class _VpnManagementScreenState extends State<VpnManagementScreen> {
  final Map<VpnResourceKind, List<ManagedVpnResource>> _resources = {};
  final Map<VpnResourceKind, Object> _errors = {};
  final Map<VpnTechnology, bool> _pending = {};
  VpnSingletonSettings? _wireGuardSettings;
  Object? _wireGuardSettingsError;
  bool _loading = false;
  bool _busy = false;
  bool _writePermissionDenied = false;
  int _requestGeneration = 0;
  int? _sessionGeneration;
  String? _profileId;

  List<ManagedVpnResource> get _allResources => [
        for (final values in _resources.values) ...values,
      ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final changed = _sessionGeneration != session.sessionGeneration ||
        _profileId != session.selectedProfile?.id;
    if (!changed) return;
    _requestGeneration++;
    _sessionGeneration = session.sessionGeneration;
    _profileId = session.selectedProfile?.id;
    _resources.clear();
    _errors.clear();
    _pending.clear();
    _wireGuardSettings = null;
    _wireGuardSettingsError = null;
    _writePermissionDenied = false;
    if (session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(showSpinner: true);
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.vpnManagementService;
    if (!session.connected || service == null) return;

    final request = ++_requestGeneration;
    final generation = session.sessionGeneration;
    setState(() {
      _loading = true;
      if (showSpinner) {
        _errors.clear();
        _wireGuardSettingsError = null;
      }
    });

    final resources = <VpnResourceKind, List<ManagedVpnResource>>{};
    final errors = <VpnResourceKind, Object>{};
    final readableKinds = VpnResourceKind.values
        .where((kind) => service.capabilities.forKind(kind).canRead)
        .toList(growable: false);

    for (final kind in readableKinds.where((kind) => !kind.child)) {
      try {
        resources[kind] = await service.list(kind);
      } catch (error) {
        errors[kind] = error;
      }
    }

    for (final kind in readableKinds.where((kind) => kind.child)) {
      final parents = resources[kind.parentKind] ?? const <ManagedVpnResource>[];
      final children = <ManagedVpnResource>[];
      try {
        for (final parent in parents) {
          final parentId = parent.id;
          if (parentId == null) continue;
          children.addAll(await service.list(kind, parentId: parentId));
        }
        resources[kind] = List.unmodifiable(children);
      } catch (error) {
        errors[kind] = error;
      }
    }

    VpnSingletonSettings? wireGuardSettings;
    Object? wireGuardSettingsError;
    final wireGuardCapabilities =
        service.capabilities.forTechnology(VpnTechnology.wireGuard);
    if (wireGuardCapabilities.settingsRead != null) {
      try {
        wireGuardSettings =
            await service.getSettings(VpnTechnology.wireGuard);
      } catch (error) {
        wireGuardSettingsError = error;
      }
    }

    final pending = <VpnTechnology, bool>{};
    for (final technology in service.capabilities.readableTechnologies) {
      if (!technology.requiresExplicitApply) continue;
      try {
        pending[technology] = await service.hasPendingChanges(technology);
      } catch (_) {
        pending[technology] = false;
      }
    }

    if (!mounted ||
        request != _requestGeneration ||
        generation != session.sessionGeneration) {
      return;
    }
    setState(() {
      _resources
        ..clear()
        ..addAll(resources);
      _errors
        ..clear()
        ..addAll(errors);
      _pending
        ..clear()
        ..addAll(pending);
      _wireGuardSettings = wireGuardSettings;
      _wireGuardSettingsError = wireGuardSettingsError;
      _loading = false;
    });
  }

  void _markReadOnly() {
    if (mounted) setState(() => _writePermissionDenied = true);
  }

  Future<void> _openForm(
    VpnResourceKind kind, {
    ManagedVpnResource? resource,
    Map<String, dynamic> initialValues = const {},
  }) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VpnResourceFormScreen(
          kind: kind,
          resource: resource,
          initialValues: initialValues,
          resources: _allResources,
          onPermissionDenied: _markReadOnly,
        ),
      ),
    );
    if (changed == true && mounted) await _load(showSpinner: true);
  }

  Future<void> _openWireGuardSettings() async {
    final settings = _wireGuardSettings;
    if (settings == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VpnSettingsScreen(
          technology: VpnTechnology.wireGuard,
          settings: settings,
          onPermissionDenied: _markReadOnly,
        ),
      ),
    );
    if (changed == true && mounted) await _load(showSpinner: true);
  }

  Future<void> _delete(ManagedVpnResource resource) async {
    if (_busy || _writePermissionDenied) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.vpnManagementService;
    if (!session.connected || service == null) return;
    final capability = service.capabilities.forKind(resource.kind);
    final technology =
        service.capabilities.forTechnology(resource.kind.technology);
    if (!capability.canDelete || !technology.canApply) return;

    final dependencies = _dependencies(resource);
    if (dependencies.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('VPN resource still has dependencies'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Delete or move these dependent entries before deleting the parent resource:',
                ),
                const SizedBox(height: 12),
                for (final dependency in dependencies)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $dependency'),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Delete ${resource.kind.singularLabel}?',
      body:
          'Delete “${resource.displayName}”? This can interrupt active VPN tunnels and cannot be undone.${resource.kind.technology.requiresExplicitApply ? ' The change will be applied after deletion succeeds.' : ' The pfREST model applies the deletion immediately.'}',
      slideLabel: 'Slide to delete',
      icon: Icons.delete_forever_outlined,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await service.delete(resource);
      await service.apply(resource.kind.technology);
      if (mounted) await _load(showSpinner: true);
    } on ApiException catch (error) {
      if (error.isPermissionError) _markReadOnly();
      if (mounted) _message(error.toString());
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _dependencies(ManagedVpnResource resource) {
  final id = resource.id?.toString();
  if (id == null || id.isEmpty) return const [];
  if (resource.kind == VpnResourceKind.ipsecPhase1) {
    final identifiers = <String>{id, _text(resource.raw['ikeid'])}
      ..removeWhere((value) => value.isEmpty);
    return [
      for (final phase2 in
          _resources[VpnResourceKind.ipsecPhase2] ?? const [])
        if (identifiers.contains(_text(phase2.raw['ikeid'])) ||
            (phase2.parentId != null &&
                identifiers.contains(phase2.parentId)))
          'Phase 2: ${phase2.displayName}',
    ];
  }
  if (resource.kind == VpnResourceKind.wireGuardTunnel) {
    final identifiers = <String>{id, _text(resource.raw['name'])}
      ..removeWhere((value) => value.isEmpty);
    return [
      for (final address in
          _resources[VpnResourceKind.wireGuardTunnelAddress] ?? const [])
        if (address.parentId != null &&
            identifiers.contains(address.parentId))
          'Tunnel address: ${address.displayName}',
      for (final peer in
          _resources[VpnResourceKind.wireGuardPeer] ?? const [])
        if (identifiers.contains(_text(peer.raw['tun'])))
          'Peer: ${peer.displayName}',
    ];
  }
  if (resource.kind == VpnResourceKind.wireGuardPeer) {
    final identifiers = <String>{id, _text(resource.raw['name'])}
      ..removeWhere((value) => value.isEmpty);
    return [
      for (final allowedIp in
          _resources[VpnResourceKind.wireGuardPeerAllowedIp] ?? const [])
        if (allowedIp.parentId != null &&
            identifiers.contains(allowedIp.parentId))
          'Allowed IP: ${allowedIp.displayName}',
    ];
  }
  if (resource.kind == VpnResourceKind.openVpnServer) {
    final identifiers = <String>{id, _text(resource.raw['vpnid'])}
      ..removeWhere((value) => value.isEmpty);
    return [
      for (final cso in
          _resources[VpnResourceKind.openVpnCso] ?? const [])
        if (identifiers.any(
          (identifier) =>
              _containsIdentifier(cso.raw['server_list'], identifier),
        ))
          'Client override: ${cso.displayName}',
      for (final export in
          _resources[VpnResourceKind.openVpnExportConfig] ?? const [])
        if (identifiers.contains(_text(export.raw['server'])))
          'Export default: ${export.displayName}',
    ];
  }
  return const [];
}

  Future<void> _exportOpenVpnClient() async {
    if (_busy) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.vpnManagementService;
    final operation = service?.capabilities.clientExport;
    if (service == null || operation == null) return;

    final fields = operation.requestFields.values
        .where((field) =>
            field.location.toLowerCase() == 'body' && !field.readOnly)
        .toList(growable: false);
    final values = <String, dynamic>{
      for (final field in fields)
        field.name: field.defaultValue ??
            (field.type == 'boolean'
                ? false
                : field.type == 'array'
                    ? <dynamic>[]
                    : ''),
    };
    final errors = <String, String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Export OpenVPN client configuration'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.security_outlined),
                      title: Text('Sensitive client material'),
                      subtitle: Text(
                        'The generated export may include private keys and credentials. It is displayed only once and is not stored by the app.',
                      ),
                    ),
                  ),
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _exportField(
                        field: field,
                        value: values[field.name],
                        error: errors[field.name],
                        onChanged: (value) => values[field.name] = value,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final normalised = normaliseVpnValues(
                  values: values,
                  operation: operation,
                );
                final validation = validateOpenVpnExport(
                  values: normalised,
                  operation: operation,
                );
                if (!validation.isValid) {
                  setDialogState(() {
                    errors
                      ..clear()
                      ..addAll(validation.errors);
                  });
                  return;
                }
                values
                  ..clear()
                  ..addAll(normalised);
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Generate export'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final export = await service.exportOpenVpnClient(values);
      if (!mounted) return;
      await _showExport(export);
    } on ApiException catch (error) {
      if (error.isPermissionError) _markReadOnly();
      if (mounted) _message(error.toString());
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      values.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _exportField({
    required dynamic field,
    required Object? value,
    required String? error,
    required ValueChanged<Object?> onChanged,
  }) {
    final allowed = field.allowedValues
        .map((item) => item?.toString())
        .whereType<String>()
        .toSet();
    if (allowed.isNotEmpty && field.type != 'array') {
      final current = value?.toString();
      if (current != null && current.isNotEmpty) allowed.add(current);
      return DropdownButtonFormField<String>(
        initialValue: current == null || current.isEmpty ? null : current,
        decoration: InputDecoration(
          labelText: _label(field.name),
          errorText: error,
          helperText: field.description,
        ),
        items: [
          for (final option in allowed)
            DropdownMenuItem(value: option, child: Text(_label(option))),
        ],
        onChanged: onChanged,
      );
    }
    if (field.type == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_label(field.name)),
        subtitle: error == null ? null : Text(error),
        value: _boolean(value),
        onChanged: onChanged,
      );
    }
    return TextFormField(
      initialValue: value?.toString() ?? '',
      decoration: InputDecoration(
        labelText: _label(field.name),
        errorText: error,
        helperText: field.description,
      ),
      onChanged: onChanged,
    );
  }

  Future<void> _showExport(VpnExportResult export) async {
    var copied = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(export.filename),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.visibility_off_outlined),
                  title: Text('One-time display'),
                  subtitle: Text(
                    'This exported material is not retained after this dialog closes. Store it only in a secure location.',
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: SingleChildScrollView(
                    child: SelectableText(export.data),
                  ),
                ),
                if (copied)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Copied to clipboard. Clear it after use.'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: export.data));
                setDialogState(() => copied = true);
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close and discard'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.vpnManagementService;
    final capabilities = service?.capabilities;
    final technologies =
        capabilities?.readableTechnologies ?? const <VpnTechnology>[];

    if (!session.connected || service == null) {
      return _status(
        icon: Icons.cloud_off_outlined,
        title: 'VPN management unavailable',
        message: 'Connect to a firewall to view VPN capabilities.',
      );
    }
    if (session.capabilities?.isLimited == true) {
      return _status(
        icon: Icons.schema_outlined,
        title: 'VPN capabilities not available',
        message: session.capabilities?.message ??
            'The OpenAPI schema could not be read for this profile.',
        action: () async {
          await session.refreshCapabilities();
          await _load(showSpinner: true);
        },
      );
    }
    if (technologies.isEmpty) {
      return _status(
        icon: Icons.vpn_lock_outlined,
        title: 'No VPN configuration endpoints reported',
        message:
            'The connected schema does not report supported OpenVPN, IPsec or WireGuard configuration operations.',
        action: () async {
          await session.refreshCapabilities();
          await _load(showSpinner: true);
        },
      );
    }

    final tabKey = technologies.map((item) => item.name).join('|');
    return DefaultTabController(
      key: ValueKey('${session.selectedProfile?.id}:$tabKey'),
      length: technologies.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('VPN configuration'),
          actions: [
            IconButton(
              tooltip: 'Refresh capabilities and VPN data',
              onPressed: _loading
                  ? null
                  : () async {
                      await session.refreshCapabilities();
                      await _load(showSpinner: true);
                    },
              icon: const Icon(Icons.schema_outlined),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final technology in technologies)
                Tab(
                  icon: Icon(_technologyIcon(technology)),
                  text: technology.label,
                ),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 3),
            Expanded(
              child: TabBarView(
                children: [
                  for (final technology in technologies)
                    _technologyTab(technology),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _technologyTab(VpnTechnology technology) {
    final service = context.watch<PfSenseSessionProvider>().vpnManagementService!;
    final capability = service.capabilities.forTechnology(technology);
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(_technologyIcon(technology)),
              title: Text(technology.label),
              subtitle: Text(
                technology.requiresExplicitApply
                    ? 'Configuration changes use the reported pending/apply workflow.'
                    : 'OpenVPN configuration models apply successful writes immediately.',
              ),
              trailing: _pending[technology] == true
                  ? const Chip(label: Text('Changes pending'))
                  : null,
            ),
          ),
          if (technology == VpnTechnology.wireGuard) ...[
            const SizedBox(height: 10),
            _wireGuardSettingsCard(capability),
          ],
          if (technology == VpnTechnology.openVpn &&
              service.capabilities.canExportOpenVpnClient) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Client export'),
                subtitle: const Text(
                  'Generate a one-time OpenVPN client export without storing the exported material in the app.',
                ),
                trailing: FilledButton.tonal(
                  onPressed: _busy ? null : _exportOpenVpnClient,
                  child: const Text('Export'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (capability.resources.isEmpty)
            _messageCard(
              Icons.vpn_lock_outlined,
              'No ${technology.label} resource collections were reported.',
            )
          else
            for (final kind in capability.resources) ...[
              _resourceSection(kind),
              const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }

  Widget _wireGuardSettingsCard(VpnTechnologyCapabilities capability) {
    final canEdit = capability.settingsUpdate != null &&
        capability.canApply &&
        !_writePermissionDenied &&
        !_busy;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.settings_outlined),
        title: const Text('WireGuard settings'),
        subtitle: _wireGuardSettingsError != null
            ? Text(_wireGuardSettingsError.toString())
            : _wireGuardSettings == null
                ? const Text('WireGuard settings are not available.')
                : Text(
                    _boolean(_wireGuardSettings!.raw['enable'])
                        ? 'WireGuard is enabled.'
                        : 'WireGuard is disabled.',
                  ),
        trailing: capability.settingsRead == null
            ? null
            : IconButton(
                tooltip: 'Edit WireGuard settings',
                onPressed: canEdit ? _openWireGuardSettings : null,
                icon: const Icon(Icons.edit_outlined),
              ),
      ),
    );
  }

  Widget _resourceSection(VpnResourceKind kind) {
    final service = context.watch<PfSenseSessionProvider>().vpnManagementService!;
    final capability = service.capabilities.forKind(kind);
    final technology = service.capabilities.forTechnology(kind.technology);
    final canWrite = technology.canApply && !_writePermissionDenied && !_busy;
    final items = _resources[kind] ?? const <ManagedVpnResource>[];
    final error = _errors[kind];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_resourceIcon(kind)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kind.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Add ${kind.singularLabel}',
                  onPressed: capability.canCreate && canWrite
                      ? () => _openForm(kind)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_writePermissionDenied)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Write permission was denied. VPN configuration is read-only for this session.',
                ),
              )
            else if (!technology.canApply &&
                (capability.canCreate ||
                    capability.canUpdate ||
                    capability.canDelete))
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Writes are disabled because the technology-specific apply endpoint is unavailable.',
                ),
              ),
            if (error != null)
              Text(error.toString())
            else if (!_loading && items.isEmpty)
              Text('No ${kind.label.toLowerCase()} returned.')
            else
              for (final resource in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    resource.disabled
                        ? Icons.pause_circle_outline
                        : Icons.check_circle_outline,
                  ),
                  title: Text(resource.displayName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (resource.summary.isNotEmpty) Text(resource.summary),
                      if (resource.description.isNotEmpty &&
                          resource.description != resource.displayName)
                        Text(resource.description),
                    ],
                  ),
                  onTap: capability.canUpdate && canWrite
                      ? () => _openForm(kind, resource: resource)
                      : null,
                  trailing: PopupMenuButton<String>(
                    enabled: canWrite &&
                        (capability.canUpdate || capability.canDelete),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _openForm(kind, resource: resource);
                      } else if (value == 'delete') {
                        _delete(resource);
                      }
                    },
                    itemBuilder: (_) => [
                      if (capability.canUpdate)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                      if (capability.canDelete)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _status({
    required IconData icon,
    required String title,
    required String message,
    Future<void> Function()? action,
  }) {
    return Scaffold(
      appBar: AppBar(title: const Text('VPN configuration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(message),
              trailing: action == null
                  ? null
                  : IconButton(
                      onPressed: action,
                      icon: const Icon(Icons.refresh),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageCard(IconData icon, String text) {
    return Card(
      child: ListTile(leading: Icon(icon), title: Text(text)),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

IconData _technologyIcon(VpnTechnology technology) {
  return switch (technology) {
    VpnTechnology.openVpn => Icons.vpn_key_outlined,
    VpnTechnology.ipsec => Icons.shield_outlined,
    VpnTechnology.wireGuard => Icons.lock_outlined,
  };
}

IconData _resourceIcon(VpnResourceKind kind) {
  return switch (kind) {
    VpnResourceKind.openVpnServer => Icons.dns_outlined,
    VpnResourceKind.openVpnClient => Icons.laptop_outlined,
    VpnResourceKind.openVpnCso => Icons.person_pin_outlined,
    VpnResourceKind.openVpnExportConfig => Icons.tune_outlined,
    VpnResourceKind.ipsecPhase1 => Icons.shield_outlined,
    VpnResourceKind.ipsecPhase2 => Icons.account_tree_outlined,
    VpnResourceKind.wireGuardTunnel => Icons.cable_outlined,
    VpnResourceKind.wireGuardPeer => Icons.people_outline,
    VpnResourceKind.wireGuardTunnelAddress => Icons.lan_outlined,
    VpnResourceKind.wireGuardPeerAllowedIp => Icons.route_outlined,
  };
}

bool _containsIdentifier(Object? value, String id) {
  if (value is List) return value.any((item) => item.toString() == id);
  return value?.toString().split(',').map((item) => item.trim()).contains(id) ==
      true;
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
