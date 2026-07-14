import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dns_management.dart';
import '../models/interface_management.dart';
import '../models/system_service.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../widgets/slide_to_confirm.dart';
import 'dns_resolver_settings_screen.dart';
import 'dns_resource_form_screen.dart';

class DnsManagementScreen extends StatefulWidget {
  const DnsManagementScreen({super.key});

  @override
  State<DnsManagementScreen> createState() => _DnsManagementScreenState();
}

class _DnsManagementScreenState extends State<DnsManagementScreen> {
  final Map<DnsResourceKind, List<ManagedDnsResource>> _resources = {};
  final Map<DnsResourceKind, Object> _errors = {};
  final Map<DnsServiceKind, bool> _pending = {};
  List<ManagedInterfaceResource> _interfaces = const [];
  List<SystemService> _systemServices = const [];
  DnsResolverSettings? _settings;
  Object? _settingsError;
  bool _loading = false;
  bool _busy = false;
  bool _writePermissionDenied = false;
  int _requestGeneration = 0;
  int? _sessionGeneration;
  String? _profileId;

  List<ManagedDnsResource> get _allResources => [
        for (final resources in _resources.values) ...resources,
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
    _interfaces = const [];
    _systemServices = const [];
    _settings = null;
    _settingsError = null;
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
    final service = session.dnsManagementService;
    if (!session.connected || service == null) return;
    final request = ++_requestGeneration;
    final generation = session.sessionGeneration;
    setState(() {
      _loading = true;
      if (showSpinner) {
        _errors.clear();
        _settingsError = null;
      }
    });

    final resources = <DnsResourceKind, List<ManagedDnsResource>>{};
    final errors = <DnsResourceKind, Object>{};
    final readable = DnsResourceKind.values
        .where((kind) => service.capabilities.forKind(kind).canRead)
        .toList(growable: false);

    for (final kind in readable.where((kind) => !kind.child)) {
      try {
        resources[kind] = await service.list(kind);
      } catch (error) {
        errors[kind] = error;
      }
    }

    for (final kind in readable.where((kind) => kind.child)) {
      final parentKind = _parentKind(kind);
      final parents = resources[parentKind] ?? const <ManagedDnsResource>[];
      final children = <ManagedDnsResource>[];
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

    DnsResolverSettings? settings;
    Object? settingsError;
    if (service.capabilities.canReadSettings) {
      try {
        settings = await service.getResolverSettings();
      } catch (error) {
        settingsError = error;
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

    var systemServices = const <SystemService>[];
    try {
      systemServices = await session.service!.getServices();
    } catch (_) {
      systemServices = const [];
    }

    final pending = <DnsServiceKind, bool>{};
    for (final dnsService in service.capabilities.readableServices) {
      try {
        pending[dnsService] = await service.hasPendingChanges(dnsService);
      } catch (_) {
        pending[dnsService] = false;
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
      _settings = settings;
      _settingsError = settingsError;
      _interfaces = interfaces;
      _systemServices = systemServices;
      _pending
        ..clear()
        ..addAll(pending);
      _loading = false;
    });
  }

  void _markReadOnly() {
    if (mounted) setState(() => _writePermissionDenied = true);
  }

  Future<void> _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DnsResolverSettingsScreen(
          settings: settings,
          interfaces: _interfaces,
          onPermissionDenied: _markReadOnly,
        ),
      ),
    );
    if (changed == true && mounted) await _load(showSpinner: true);
  }

  Future<void> _openForm(
    DnsResourceKind kind, {
    ManagedDnsResource? resource,
    Map<String, dynamic> initialValues = const {},
  }) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DnsResourceFormScreen(
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

  Future<void> _delete(ManagedDnsResource resource) async {
    if (_busy || _writePermissionDenied) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.dnsManagementService;
    if (!session.connected || service == null) return;
    final capability = service.capabilities.forKind(resource.kind);
    final serviceCapability =
        service.capabilities.forService(resource.kind.service);
    if (!capability.canDelete || !serviceCapability.canApply) return;

    final dependencies = _dependencies(resource);
    if (dependencies.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('DNS resource still has child entries'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Delete or move these entries before deleting the parent resource:',
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
          'Delete “${resource.displayName}” and apply the ${resource.kind.service.label} configuration? Name resolution may be affected.',
      slideLabel: 'Slide to delete and apply',
      icon: Icons.delete_forever_outlined,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await service.delete(resource);
      await service.apply(resource.kind.service);
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

  List<String> _dependencies(ManagedDnsResource resource) {
    final id = resource.id?.toString();
    if (id == null) return const [];
    if (resource.kind == DnsResourceKind.resolverHostOverride) {
      return [
        for (final alias
            in _resources[DnsResourceKind.resolverHostAlias] ?? const [])
          if (alias.parentId == id) 'Host alias: ${alias.displayName}',
      ];
    }
    if (resource.kind == DnsResourceKind.forwarderHostOverride) {
      return [
        for (final alias
            in _resources[DnsResourceKind.forwarderHostAlias] ?? const [])
          if (alias.parentId == id) 'Host alias: ${alias.displayName}',
      ];
    }
    if (resource.kind == DnsResourceKind.resolverAccessList) {
      return [
        for (final network in
            _resources[DnsResourceKind.resolverAccessListNetwork] ?? const [])
          if (network.parentId == id) 'Network: ${network.displayName}',
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.dnsManagementService;
    final capabilities = service?.capabilities;
    final services = capabilities?.readableServices ?? const <DnsServiceKind>[];

    if (!session.connected || service == null) {
      return _status(
        icon: Icons.cloud_off_outlined,
        title: 'DNS management unavailable',
        message: 'Connect to a firewall to view DNS capabilities.',
      );
    }
    if (session.capabilities?.isLimited == true) {
      return _status(
        icon: Icons.schema_outlined,
        title: 'DNS capabilities not available',
        message: session.capabilities?.message ??
            'The OpenAPI schema could not be read for this profile.',
        action: () async {
          await session.refreshCapabilities();
          await _load(showSpinner: true);
        },
      );
    }
    if (services.isEmpty) {
      return _status(
        icon: Icons.dns_outlined,
        title: 'No DNS configuration endpoints reported',
        message:
            'The connected schema does not report supported DNS Resolver or DNS Forwarder configuration operations.',
        action: () async {
          await session.refreshCapabilities();
          await _load(showSpinner: true);
        },
      );
    }

    final tabKey = services.map((item) => item.name).join('|');
    return DefaultTabController(
      key: ValueKey('${session.selectedProfile?.id}:$tabKey'),
      length: services.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('DNS services'),
          actions: [
            IconButton(
              tooltip: 'Refresh capabilities and DNS data',
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
              for (final dnsService in services)
                Tab(
                  icon: Icon(_serviceIcon(dnsService)),
                  text: dnsService.label,
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
                  for (final dnsService in services)
                    _serviceTab(dnsService),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serviceTab(DnsServiceKind dnsService) {
    final service = context.watch<PfSenseSessionProvider>().dnsManagementService!;
    final capability = service.capabilities.forService(dnsService);
    final kinds = capability.resources;
    final active = _activeStatus(dnsService);

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                active == true
                    ? Icons.check_circle_outline
                    : active == false
                        ? Icons.pause_circle_outline
                        : Icons.help_outline,
                color: active == true
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(dnsService.label),
              subtitle: Text(
                active == true
                    ? 'This service is currently running.'
                    : active == false
                        ? 'This service is currently stopped.'
                        : 'Live service status could not be determined.',
              ),
              trailing: _pending[dnsService] == true
                  ? const Chip(label: Text('Changes pending'))
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          if (dnsService == DnsServiceKind.resolver)
            _resolverSettingsCard(service.capabilities)
          else
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Forwarder settings endpoint not reported'),
                subtitle: Text(
                  'The current pfREST schema exposes DNS Forwarder host overrides and apply operations, but does not report a global Forwarder settings endpoint. No unsupported path is assumed.',
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (kinds.isEmpty)
            _messageCard(
              Icons.dns_outlined,
              'No ${dnsService.label} resource collections were reported.',
            )
          else
            for (final kind in kinds) ...[
              _resourceSection(kind),
              const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }

  Widget _resolverSettingsCard(DnsManagementCapabilities capabilities) {
    final canEdit = capabilities.canUpdateSettings &&
        capabilities.forService(DnsServiceKind.resolver).canApply &&
        !_writePermissionDenied &&
        !_busy;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.settings_outlined),
        title: const Text('Resolver settings'),
        subtitle: _settingsError != null
            ? Text(_settingsError.toString())
            : _settings == null
                ? const Text('Resolver settings are not available.')
                : Text(
                    '${_settings!.enabled ? 'Enabled' : 'Disabled'} • '
                    '${_settings!.forwarding ? 'Forwarding mode' : 'Recursive mode'} • '
                    '${_settings!.dnssec ? 'DNSSEC enabled' : 'DNSSEC disabled'} • '
                    'Port ${_settings!.port ?? 53}',
                  ),
        trailing: capabilities.canReadSettings
            ? IconButton(
                tooltip: 'Edit Resolver settings',
                onPressed: canEdit ? _openSettings : null,
                icon: const Icon(Icons.edit_outlined),
              )
            : null,
      ),
    );
  }

  Widget _resourceSection(DnsResourceKind kind) {
    final service = context.watch<PfSenseSessionProvider>().dnsManagementService!;
    final capability = service.capabilities.forKind(kind);
    final canApply = service.capabilities.forService(kind.service).canApply;
    final canCreate = capability.canCreate &&
        canApply &&
        !_writePermissionDenied &&
        !_busy;
    final items = _resources[kind] ?? const <ManagedDnsResource>[];
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
                  onPressed: canCreate ? () => _openForm(kind) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_writePermissionDenied)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Write permission was denied. DNS configuration is read-only for this session.',
                ),
              )
            else if (!canApply &&
                (capability.canCreate ||
                    capability.canUpdate ||
                    capability.canDelete))
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Writes are disabled because the matching apply endpoint is unavailable.',
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
                  title: Text(
                    resource.displayName.isEmpty
                        ? 'Unnamed ${kind.singularLabel}'
                        : resource.displayName,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (resource.summary.isNotEmpty) Text(resource.summary),
                      if (resource.description.isNotEmpty)
                        Text(resource.description),
                    ],
                  ),
                  onTap: capability.canUpdate &&
                          canApply &&
                          !_writePermissionDenied &&
                          !_busy
                      ? () => _openForm(kind, resource: resource)
                      : null,
                  trailing: PopupMenuButton<String>(
                    enabled: (capability.canUpdate || capability.canDelete) &&
                        canApply &&
                        !_writePermissionDenied &&
                        !_busy,
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

  bool? _activeStatus(DnsServiceKind dnsService) {
    final matches = _systemServices.where(
      (service) =>
          service.name.trim().toLowerCase() == dnsService.serviceName,
    );
    if (matches.isEmpty) return null;
    return matches.any((service) => service.running);
  }

  Widget _status({
    required IconData icon,
    required String title,
    required String message,
    Future<void> Function()? action,
  }) {
    return Scaffold(
      appBar: AppBar(title: const Text('DNS services')),
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

DnsResourceKind? _parentKind(DnsResourceKind kind) {
  return switch (kind) {
    DnsResourceKind.resolverHostAlias =>
      DnsResourceKind.resolverHostOverride,
    DnsResourceKind.forwarderHostAlias =>
      DnsResourceKind.forwarderHostOverride,
    DnsResourceKind.resolverAccessListNetwork =>
      DnsResourceKind.resolverAccessList,
    _ => null,
  };
}

IconData _serviceIcon(DnsServiceKind service) {
  return switch (service) {
    DnsServiceKind.resolver => Icons.hub_outlined,
    DnsServiceKind.forwarder => Icons.forward_outlined,
  };
}

IconData _resourceIcon(DnsResourceKind kind) {
  return switch (kind) {
    DnsResourceKind.resolverHostOverride ||
    DnsResourceKind.forwarderHostOverride => Icons.dns_outlined,
    DnsResourceKind.resolverDomainOverride => Icons.language_outlined,
    DnsResourceKind.resolverAccessList => Icons.policy_outlined,
    DnsResourceKind.resolverHostAlias ||
    DnsResourceKind.forwarderHostAlias => Icons.link_outlined,
    DnsResourceKind.resolverAccessListNetwork => Icons.lan_outlined,
  };
}
