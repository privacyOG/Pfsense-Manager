import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dhcp_management.dart';
import '../models/interface_management.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/dhcp_management_validation.dart';
import '../widgets/slide_to_confirm.dart';
import 'dhcp_resource_form_screen.dart';

class DhcpManagementScreen extends StatefulWidget {
  const DhcpManagementScreen({super.key});

  @override
  State<DhcpManagementScreen> createState() => _DhcpManagementScreenState();
}

class _DhcpManagementScreenState extends State<DhcpManagementScreen> {
  final Map<DhcpResourceKind, List<ManagedDhcpResource>> _resources = {};
  final Map<DhcpResourceKind, Object> _errors = {};
  List<ManagedInterfaceResource> _interfaces = const [];
  DhcpSingletonConfiguration? _relay;
  Object? _relayError;
  bool _loading = false;
  bool _busy = false;
  bool _writePermissionDenied = false;
  int _requestGeneration = 0;
  int? _sessionGeneration;
  String? _profileId;

  List<ManagedDhcpResource> get _servers =>
      _resources[DhcpResourceKind.server] ?? const [];
  List<ManagedDhcpResource> get _mappings =>
      _resources[DhcpResourceKind.staticMapping] ?? const [];
  List<ManagedDhcpResource> get _pools =>
      _resources[DhcpResourceKind.addressPool] ?? const [];

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
    _interfaces = const [];
    _relay = null;
    _relayError = null;
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
    final service = session.dhcpManagementService;
    if (!session.connected || service == null) return;
    final request = ++_requestGeneration;
    final generation = session.sessionGeneration;
    setState(() {
      _loading = true;
      if (showSpinner) {
        _errors.clear();
        _relayError = null;
      }
    });

    final resources = <DhcpResourceKind, List<ManagedDhcpResource>>{};
    final errors = <DhcpResourceKind, Object>{};
    for (final kind in service.capabilities.readableKinds) {
      try {
        resources[kind] = await service.list(kind);
      } catch (error) {
        errors[kind] = error;
      }
    }

    var interfaces = const <ManagedInterfaceResource>[];
    final interfaceService = session.interfaceManagementService;
    if (interfaceService
            ?.capabilities
            .forKind(InterfaceResourceKind.assigned)
            .canRead ==
        true) {
      try {
        interfaces = await interfaceService!.list(InterfaceResourceKind.assigned);
      } catch (_) {
        interfaces = const [];
      }
    }

    DhcpSingletonConfiguration? relay;
    Object? relayError;
    if (service.capabilities.canReadRelay) {
      try {
        relay = await service.getRelay();
      } catch (error) {
        relayError = error;
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
      _interfaces = interfaces;
      _relay = relay;
      _relayError = relayError;
      _loading = false;
    });
  }

  void _markReadOnly() {
    if (mounted) setState(() => _writePermissionDenied = true);
  }

  Future<void> _openForm(
    DhcpResourceKind kind, {
    ManagedDhcpResource? resource,
    Map<String, dynamic> initialValues = const {},
  }) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DhcpResourceFormScreen(
          kind: kind,
          resource: resource,
          initialValues: initialValues,
          servers: _servers,
          staticMappings: _mappings,
          addressPools: _pools,
          interfaces: _interfaces,
          relayEnabled: _relay?.enabled == true,
          onPermissionDenied: _markReadOnly,
        ),
      ),
    );
    if (changed == true && mounted) await _load(showSpinner: true);
  }

  Future<void> _delete(ManagedDhcpResource resource) async {
    if (_busy || _writePermissionDenied) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.dhcpManagementService;
    if (!session.connected || service == null) return;
    final capability = service.capabilities.forKind(resource.kind);
    if (!capability.canDelete || !service.capabilities.canApply) return;

    if (resource.kind == DhcpResourceKind.server) {
      final children = <String>[
        for (final mapping in _mappings)
          if (mapping.parentId == resource.interfaceId)
            'Static mapping: ${mapping.displayName}',
        for (final pool in _pools)
          if (pool.parentId == resource.interfaceId)
            'Address pool: ${pool.displayName}',
      ];
      if (children.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('DHCP server still has child resources'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Delete or move these resources before deleting the DHCP server:',
                  ),
                  const SizedBox(height: 12),
                  for (final child in children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $child'),
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
    }

    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Delete ${resource.kind.singularLabel}?',
      body:
          'Delete “${resource.displayName}” and apply the DHCP configuration? Address assignment may be interrupted.',
      slideLabel: 'Slide to delete and apply',
      icon: Icons.delete_forever_outlined,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await service.delete(resource);
      await service.apply();
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

  Future<void> _editRelay() async {
    final session = context.read<PfSenseSessionProvider>();
    final service = session.dhcpManagementService;
    final relay = _relay;
    final operation = service?.capabilities.relayUpdate;
    if (service == null || relay == null || operation == null) return;

    var enabled = relay.enabled;
    var interfaces = List<String>.from(relay.interfaces);
    var destinations = List<String>.from(relay.servers);
    var agentOption = _boolean(relay.raw['agentoption']);
    var carpStatusVip = relay.raw['carpstatusvip']?.toString() ?? 'none';
    String? error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('DHCP relay'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable DHCP relay'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: interfaces.join(', '),
                    decoration: const InputDecoration(
                      labelText: 'Downstream interfaces',
                      helperText: 'Separate interface IDs with commas.',
                    ),
                    onChanged: (value) => interfaces = _splitValues(value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: destinations.join(', '),
                    decoration: const InputDecoration(
                      labelText: 'Upstream DHCP servers',
                      helperText: 'Separate IPv4 addresses with commas.',
                    ),
                    onChanged: (value) => destinations = _splitValues(value),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Append relay agent option'),
                    value: agentOption,
                    onChanged: (value) =>
                        setDialogState(() => agentOption = value),
                  ),
                  if (operation.field('carpstatusvip', location: 'body') != null)
                    TextFormField(
                      initialValue: carpStatusVip,
                      decoration: const InputDecoration(
                        labelText: 'CARP status VIP',
                        helperText: 'Use none when no CARP status VIP is required.',
                      ),
                      onChanged: (value) => carpStatusVip = value.trim(),
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'The relay and DHCP servers cannot be enabled at the same time. Relay changes apply immediately.',
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
                final values = <String, dynamic>{
                  'enable': enabled,
                  'interface': interfaces,
                  'server': destinations,
                  'agentoption': agentOption,
                  if (operation.field('carpstatusvip', location: 'body') != null)
                    'carpstatusvip': carpStatusVip,
                };
                final validation = validateDhcpRelayValues(
                  values: values,
                  operation: operation,
                  servers: _servers,
                  interfaces: _interfaces,
                );
                if (!validation.isValid) {
                  setDialogState(() => error = validation.summary);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save relay'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final values = <String, dynamic>{
      'enable': enabled,
      'interface': interfaces,
      'server': destinations,
      'agentoption': agentOption,
      if (operation.field('carpstatusvip', location: 'body') != null)
        'carpstatusvip': carpStatusVip,
    };
    setState(() => _busy = true);
    try {
      await service.updateRelay(relay, values);
      if (mounted) await _load(showSpinner: true);
    } on ApiException catch (apiError) {
      if (apiError.isPermissionError) _markReadOnly();
      if (mounted) _message(apiError.toString());
    } catch (otherError) {
      if (mounted) _message(otherError.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchBackend() async {
    final session = context.read<PfSenseSessionProvider>();
    final service = session.dhcpManagementService;
    final operation = service?.capabilities.backendUpdate;
    final field = operation?.field('dhcpbackend', location: 'body');
    if (service == null || operation == null || field == null) return;
    final options = field.allowedValues
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (options.isEmpty) return;

    var backend = options.contains('kea') ? 'kea' : options.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select DHCP backend'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: backend,
                  decoration: const InputDecoration(labelText: 'Backend'),
                  items: [
                    for (final option in options)
                      DropdownMenuItem(
                        value: option,
                        child: Text(option.toUpperCase()),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => backend = value ?? backend),
                ),
                const SizedBox(height: 14),
                const Text(
                  'The installed API reports backend selection but not the currently active backend. Selecting a value applies it immediately and may restart DHCP services.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Switch backend'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final validation = validateDhcpBackendValue(
      backend: backend,
      operation: operation,
    );
    if (!validation.isValid) {
      _message(validation.summary);
      return;
    }
    final slideConfirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Switch DHCP backend?',
      body:
          'Switch to ${backend.toUpperCase()} now? DHCP service availability may be briefly interrupted.',
      slideLabel: 'Slide to switch backend',
      icon: Icons.swap_horiz,
    );
    if (slideConfirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await service.switchBackend(backend);
      if (mounted) _message('DHCP backend switch requested.');
    } on ApiException catch (error) {
      if (error.isPermissionError) _markReadOnly();
      if (mounted) _message(error.toString());
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.dhcpManagementService;
    final capabilities = service?.capabilities;
    final kinds = capabilities?.readableKinds ?? const <DhcpResourceKind>[];

    if (!session.connected || service == null) {
      return _status(
        icon: Icons.cloud_off_outlined,
        title: 'DHCP management unavailable',
        message: 'Connect to a firewall to view DHCP capabilities.',
      );
    }
    if (session.capabilities?.isLimited == true) {
      return _status(
        icon: Icons.schema_outlined,
        title: 'DHCP capabilities not available',
        message: session.capabilities?.message ??
            'The OpenAPI schema could not be read for this profile.',
        action: () async {
          await session.refreshCapabilities();
          await _load(showSpinner: true);
        },
      );
    }
    if (kinds.isEmpty) {
      return _status(
        icon: Icons.dns_outlined,
        title: 'No DHCP configuration endpoints reported',
        message:
            'Lease status may still be available, but the connected schema does not report a supported DHCP configuration collection.',
        action: () async {
          await session.refreshCapabilities();
          await _load(showSpinner: true);
        },
      );
    }

    final tabKey = kinds.map((kind) => kind.name).join('|');
    return DefaultTabController(
      key: ValueKey('${session.selectedProfile?.id}:$tabKey'),
      length: kinds.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('DHCP'),
          actions: [
            IconButton(
              tooltip: 'Refresh capabilities and DHCP data',
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
              for (final kind in kinds)
                Tab(icon: Icon(_kindIcon(kind)), text: kind.label),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 3),
            Expanded(
              child: TabBarView(
                children: [
                  for (final kind in kinds) _resourceTab(kind),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resourceTab(DhcpResourceKind kind) {
    final service = context.watch<PfSenseSessionProvider>().dhcpManagementService!;
    final capability = service.capabilities.forKind(kind);
    final canApply = service.capabilities.canApply;
    final canCreate = capability.canCreate &&
        canApply &&
        !_writePermissionDenied &&
        !_busy;
    final error = _errors[kind];
    final items = _resources[kind] ?? const <ManagedDhcpResource>[];

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _capabilityCard(kind, capability, canApply),
          if (kind == DhcpResourceKind.server) ...[
            const SizedBox(height: 10),
            _operationsCard(service.capabilities),
            const SizedBox(height: 10),
            _dhcpV6Card(service.capabilities),
          ],
          const SizedBox(height: 12),
          if (error != null)
            _messageCard(Icons.error_outline, error.toString())
          else if (!_loading && items.isEmpty)
            _messageCard(
              _kindIcon(kind),
              'No ${kind.label.toLowerCase()} returned.',
            )
          else
            for (final resource in items)
              _resourceCard(
                resource,
                canEdit: capability.canUpdate &&
                    canApply &&
                    !_writePermissionDenied &&
                    !_busy,
                canDelete: capability.canDelete &&
                    canApply &&
                    !_writePermissionDenied &&
                    !_busy,
              ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: canCreate ? () => _openForm(kind) : null,
            icon: const Icon(Icons.add),
            label: Text('Add ${kind.singularLabel}'),
          ),
        ],
      ),
    );
  }

  Widget _capabilityCard(
    DhcpResourceKind kind,
    DhcpResourceCapability capability,
    bool canApply,
  ) {
    final writable = capability.canCreate ||
        capability.canUpdate ||
        capability.canDelete;
    return Card(
      child: ListTile(
        leading: Icon(_kindIcon(kind)),
        title: Text(kind.label),
        subtitle: Text(
          _writePermissionDenied
              ? 'Write permission was denied. DHCP configuration is read-only for this session.'
              : !writable
                  ? 'The connected schema reports read-only access.'
                  : !canApply
                      ? 'Writes are disabled because the DHCP apply endpoint is unavailable.'
                      : 'Supported operations are enabled from the connected OpenAPI schema.',
        ),
      ),
    );
  }

  Widget _operationsCard(DhcpManagementCapabilities capabilities) {
    final canEditRelay = capabilities.canUpdateRelay &&
        _relay != null &&
        !_writePermissionDenied &&
        !_busy;
    final canSwitchBackend = capabilities.canSwitchBackend &&
        !_writePermissionDenied &&
        !_busy;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.compare_arrows_outlined),
            title: const Text('DHCP relay'),
            subtitle: _relayError != null
                ? Text(_relayError.toString())
                : _relay == null
                    ? const Text('Relay configuration is not reported.')
                    : Text(
                        _relay!.enabled
                            ? 'Enabled • ${_relay!.interfaces.join(', ')} • ${_relay!.servers.join(', ')}'
                            : 'Disabled',
                      ),
            trailing: capabilities.canReadRelay
                ? IconButton(
                    tooltip: 'Edit DHCP relay',
                    onPressed: canEditRelay ? _editRelay : null,
                    icon: const Icon(Icons.edit_outlined),
                  )
                : null,
          ),
          if (capabilities.canSwitchBackend) const Divider(height: 1),
          if (capabilities.canSwitchBackend)
            ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('DHCP backend'),
              subtitle: const Text(
                'The API permits backend selection but does not report the current backend.',
              ),
              trailing: IconButton(
                tooltip: 'Switch DHCP backend',
                onPressed: canSwitchBackend ? _switchBackend : null,
                icon: const Icon(Icons.swap_horiz),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dhcpV6Card(DhcpManagementCapabilities capabilities) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.language_outlined),
        title: const Text('DHCPv6 configuration'),
        subtitle: Text(
          capabilities.reportsDhcpV6
              ? 'The schema reports DHCPv6 paths: ${capabilities.dhcpV6Paths.join(', ')}. These endpoints require a dedicated compatible editor before writes are enabled.'
              : 'The connected schema does not report DHCPv6 server configuration endpoints. No unsupported path is assumed.',
        ),
      ),
    );
  }

  Widget _resourceCard(
    ManagedDhcpResource resource, {
    required bool canEdit,
    required bool canDelete,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_kindIcon(resource.kind))),
        title: Text(resource.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (resource.summary.isNotEmpty) Text(resource.summary),
            if (resource.description.isNotEmpty) Text(resource.description),
          ],
        ),
        isThreeLine: resource.description.isNotEmpty,
        onTap: canEdit
            ? () => _openForm(resource.kind, resource: resource)
            : null,
        trailing: PopupMenuButton<String>(
          enabled: canEdit || canDelete,
          onSelected: (value) {
            if (value == 'edit') {
              _openForm(resource.kind, resource: resource);
            } else if (value == 'delete') {
              _delete(resource);
            }
          },
          itemBuilder: (_) => [
            if (canEdit)
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (canDelete)
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
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
      appBar: AppBar(title: const Text('DHCP')),
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

IconData _kindIcon(DhcpResourceKind kind) {
  return switch (kind) {
    DhcpResourceKind.server => Icons.dns_outlined,
    DhcpResourceKind.staticMapping => Icons.push_pin_outlined,
    DhcpResourceKind.addressPool => Icons.view_stream_outlined,
  };
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
