import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dashboard.dart';
import '../models/interface_management.dart';
import '../models/routing_management.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/routing_management_validation.dart';
import '../widgets/slide_to_confirm.dart';
import 'routing_resource_form_screen.dart';

class RoutingManagementScreen extends StatefulWidget {
  const RoutingManagementScreen({super.key});

  @override
  State<RoutingManagementScreen> createState() =>
      _RoutingManagementScreenState();
}

class _RoutingManagementScreenState extends State<RoutingManagementScreen> {
  final Map<RoutingResourceKind, List<ManagedRoutingResource>> _resources = {};
  final Map<RoutingResourceKind, Object> _errors = {};
  List<AvailableInterface> _availableInterfaces = const [];
  Map<String, GatewayStatus> _gatewayStatus = const {};
  RoutingDefaults? _defaults;
  Object? _defaultsError;
  bool _loading = false;
  bool _busy = false;
  bool _writePermissionDenied = false;
  int _requestGeneration = 0;
  int? _sessionGeneration;
  String? _profileId;

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
    _availableInterfaces = const [];
    _gatewayStatus = const {};
    _defaults = null;
    _defaultsError = null;
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
    final service = session.routingManagementService;
    if (!session.connected || service == null) return;
    final request = ++_requestGeneration;
    final generation = session.sessionGeneration;
    setState(() {
      _loading = true;
      if (showSpinner) {
        _errors.clear();
        _defaultsError = null;
      }
    });

    final resources = <RoutingResourceKind, List<ManagedRoutingResource>>{};
    final errors = <RoutingResourceKind, Object>{};
    for (final kind in service.capabilities.readableKinds) {
      try {
        resources[kind] = await service.list(kind);
      } catch (error) {
        errors[kind] = error;
      }
    }

    RoutingDefaults? defaults;
    Object? defaultsError;
    if (service.capabilities.canReadDefaults) {
      try {
        defaults = await service.getDefaults();
      } catch (error) {
        defaultsError = error;
      }
    }

    var interfaces = const <AvailableInterface>[];
    final interfaceService = session.interfaceManagementService;
    if (interfaceService?.capabilities.availableInterfaces != null) {
      try {
        interfaces = await interfaceService!.listAvailableInterfaces();
      } catch (_) {
        interfaces = const [];
      }
    }

    var status = const <GatewayStatus>[];
    try {
      status = (await session.service!.getDashboard()).gateways;
    } catch (_) {
      status = const [];
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
      _defaults = defaults;
      _defaultsError = defaultsError;
      _availableInterfaces = interfaces;
      _gatewayStatus = {
        for (final item in status) item.name: item,
      };
      _loading = false;
    });
  }

  void _markReadOnly() {
    if (mounted) setState(() => _writePermissionDenied = true);
  }

  List<ManagedRoutingResource> _items(RoutingResourceKind kind) =>
      _resources[kind] ?? const [];

  List<ManagedRoutingResource> get _gateways =>
      _items(RoutingResourceKind.gateway);

  List<ManagedRoutingResource> get _gatewayGroups =>
      _items(RoutingResourceKind.gatewayGroup);

  Future<void> _openForm(
    RoutingResourceKind kind, [
    ManagedRoutingResource? resource,
  ]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RoutingResourceFormScreen(
          kind: kind,
          resource: resource,
          gateways: _gateways,
          gatewayGroups: _gatewayGroups,
          availableInterfaces: _availableInterfaces,
          onPermissionDenied: _markReadOnly,
        ),
      ),
    );
    if (changed == true && mounted) await _load(showSpinner: true);
  }

  Future<void> _delete(ManagedRoutingResource resource) async {
    if (_busy || _writePermissionDenied) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.routingManagementService;
    if (!session.connected || service == null) return;
    final capability = service.capabilities.forKind(resource.kind);
    if (!capability.canDelete || !service.capabilities.canApply) return;

    GatewayDependencyReport? report;
    if (resource.kind == RoutingResourceKind.gateway) {
      setState(() => _busy = true);
      try {
        report = await service.findGatewayDependencies(resource.displayName);
      } catch (error) {
        if (mounted) _message(error.toString());
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      if (!mounted) return;
      if (report.hasDependencies) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Gateway is still in use'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Remove or update these dependencies before deleting the gateway:',
                  ),
                  const SizedBox(height: 12),
                  for (final dependency in report!.descriptions)
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
    }

    final unchecked = report?.uncheckedSources.toList() ?? const <String>[];
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Delete ${resource.kind.singularLabel}?',
      body: unchecked.isEmpty
          ? 'Delete “${resource.displayName}” and apply the routing configuration? Active traffic may be interrupted.'
          : 'No dependency was found in the available data, but ${unchecked.join(', ')} could not be checked. pfSense will perform its own validation. Delete “${resource.displayName}” and apply the routing configuration?',
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

  Future<void> _editDefaults() async {
    final session = context.read<PfSenseSessionProvider>();
    final service = session.routingManagementService;
    final defaults = _defaults;
    final operation = service?.capabilities.defaultUpdate;
    if (service == null || defaults == null || operation == null) return;

    var ipv4 = defaults.ipv4;
    var ipv6 = defaults.ipv6;
    final options4 = _defaultOptions('inet', ipv4);
    final options6 = _defaultOptions('inet6', ipv6);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Default gateways'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: ipv4,
                  decoration:
                      const InputDecoration(labelText: 'Default IPv4 gateway'),
                  items: [
                    for (final option in options4)
                      DropdownMenuItem(
                        value: option,
                        child: Text(_defaultLabel(option)),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => ipv4 = value ?? ''),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: ipv6,
                  decoration:
                      const InputDecoration(labelText: 'Default IPv6 gateway'),
                  items: [
                    for (final option in options6)
                      DropdownMenuItem(
                        value: option,
                        child: Text(_defaultLabel(option)),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => ipv6 = value ?? ''),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Automatic lets pfSense select the default. None explicitly disables a default gateway for that IP version.',
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
              child: const Text('Save and apply'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final values = {'defaultgw4': ipv4, 'defaultgw6': ipv6};
    final validation = validateDefaultGatewayValues(
      values: values,
      operation: operation,
      gatewayFamilies: {
        for (final item in [..._gateways, ..._gatewayGroups])
          item.displayName: item.ipProtocol,
      },
    );
    if (!validation.isValid) {
      _message(validation.summary);
      return;
    }

    setState(() => _busy = true);
    try {
      await service.updateDefaults(defaults, values);
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

  List<String> _defaultOptions(String family, String current) {
    final names = <String>{
      '',
      '-',
      if (current.isNotEmpty) current,
      for (final item in [..._gateways, ..._gatewayGroups])
        if (item.ipProtocol == family) item.displayName,
    }.toList(growable: false);
    names.sort((first, second) {
      if (first.isEmpty) return -1;
      if (second.isEmpty) return 1;
      if (first == '-') return -1;
      if (second == '-') return 1;
      return first.compareTo(second);
    });
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.routingManagementService;
    final capabilities = service?.capabilities;
    final kinds = capabilities?.readableKinds ?? const <RoutingResourceKind>[];

    if (!session.connected || service == null) {
      return _status(
        icon: Icons.cloud_off_outlined,
        title: 'Routing management unavailable',
        message: 'Connect to a firewall to view routing capabilities.',
      );
    }
    if (session.capabilities?.isLimited == true) {
      return _status(
        icon: Icons.schema_outlined,
        title: 'Routing capabilities not available',
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
        icon: Icons.alt_route_outlined,
        title: 'No routing endpoints reported',
        message:
            'The connected OpenAPI schema does not report a supported routing collection.',
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
          title: const Text('Routing'),
          actions: [
            IconButton(
              tooltip: 'Refresh capabilities and routing data',
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

  Widget _resourceTab(RoutingResourceKind kind) {
    final service = context.watch<PfSenseSessionProvider>().routingManagementService!;
    final capability = service.capabilities.forKind(kind);
    final canApply = service.capabilities.canApply;
    final canCreate = capability.canCreate &&
        canApply &&
        !_writePermissionDenied &&
        !_busy;
    final error = _errors[kind];
    final items = _items(kind);

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _capabilityCard(kind, capability, canApply),
          if (kind == RoutingResourceKind.gateway) ...[
            const SizedBox(height: 10),
            _defaultGatewayCard(service.capabilities),
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
    RoutingResourceKind kind,
    RoutingResourceCapability capability,
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
              ? 'Write permission was denied. This screen is read-only for the current session.'
              : !writable
                  ? 'The connected schema reports read-only access.'
                  : !canApply
                      ? 'Writes are disabled because the routing apply endpoint is unavailable.'
                      : 'Supported operations are enabled from the connected OpenAPI schema.',
        ),
      ),
    );
  }

  Widget _defaultGatewayCard(RoutingManagementCapabilities capabilities) {
    final canEdit = capabilities.canUpdateDefaults &&
        capabilities.canApply &&
        !_writePermissionDenied &&
        !_busy;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.route_outlined),
        title: const Text('Default gateways'),
        subtitle: _defaultsError != null
            ? Text(_defaultsError.toString())
            : _defaults == null
                ? const Text('Default gateway information is not available.')
                : Text(
                    'IPv4: ${_defaultLabel(_defaults!.ipv4)}\nIPv6: ${_defaultLabel(_defaults!.ipv6)}',
                  ),
        trailing: capabilities.canReadDefaults
            ? IconButton(
                tooltip: 'Edit default gateways',
                onPressed: canEdit ? _editDefaults : null,
                icon: const Icon(Icons.edit_outlined),
              )
            : null,
      ),
    );
  }

  Widget _resourceCard(
    ManagedRoutingResource resource, {
    required bool canEdit,
    required bool canDelete,
  }) {
    final status = resource.kind == RoutingResourceKind.gateway
        ? _gatewayStatus[resource.displayName]
        : null;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_kindIcon(resource.kind))),
        title: Text(resource.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (resource.summary.isNotEmpty) Text(resource.summary),
            if (resource.description.isNotEmpty) Text(resource.description),
            if (status != null)
              Text(
                '${status.status} • ${status.latency.toStringAsFixed(1)} ms • ${status.packetLoss.toStringAsFixed(1)}% loss',
                style: TextStyle(
                  color: status.online
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        isThreeLine: resource.description.isNotEmpty || status != null,
        onTap: canEdit ? () => _openForm(resource.kind, resource) : null,
        trailing: PopupMenuButton<String>(
          enabled: canEdit || canDelete,
          onSelected: (value) {
            if (value == 'edit') _openForm(resource.kind, resource);
            if (value == 'delete') _delete(resource);
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
      appBar: AppBar(title: const Text('Routing')),
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

IconData _kindIcon(RoutingResourceKind kind) {
  return switch (kind) {
    RoutingResourceKind.gateway => Icons.router_outlined,
    RoutingResourceKind.gatewayGroup => Icons.account_tree_outlined,
    RoutingResourceKind.staticRoute => Icons.alt_route_outlined,
  };
}

String _defaultLabel(String value) {
  if (value.isEmpty) return 'Automatic';
  if (value == '-') return 'None';
  return value;
}
