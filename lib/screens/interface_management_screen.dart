import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/interface_management.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../utils/interface_management_validation.dart';
import '../widgets/slide_to_confirm.dart';
import 'interface_resource_form_screen.dart';

class InterfaceManagementScreen extends StatefulWidget {
  const InterfaceManagementScreen({super.key});

  @override
  State<InterfaceManagementScreen> createState() =>
      _InterfaceManagementScreenState();
}

class _InterfaceManagementScreenState extends State<InterfaceManagementScreen> {
  List<AvailableInterface> _availableInterfaces = const [];
  Object? _availableError;
  bool _loadingAvailable = false;
  int? _sessionGeneration;
  String? _profileId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final changed = _sessionGeneration != session.sessionGeneration ||
        _profileId != session.selectedProfile?.id;
    if (!changed) return;
    _sessionGeneration = session.sessionGeneration;
    _profileId = session.selectedProfile?.id;
    _availableInterfaces = const [];
    _availableError = null;
    if (session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadAvailableInterfaces();
      });
    }
  }

  Future<void> _loadAvailableInterfaces() async {
    if (_loadingAvailable) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.interfaceManagementService;
    if (!session.connected || service == null) return;
    if (service.capabilities.availableInterfaces == null) return;

    final generation = session.sessionGeneration;
    setState(() {
      _loadingAvailable = true;
      _availableError = null;
    });
    try {
      final interfaces = await service.listAvailableInterfaces();
      if (!mounted || generation != session.sessionGeneration) return;
      setState(() => _availableInterfaces = interfaces);
    } catch (error) {
      if (mounted && generation == session.sessionGeneration) {
        setState(() => _availableError = error);
      }
    } finally {
      if (mounted && generation == session.sessionGeneration) {
        setState(() => _loadingAvailable = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.interfaceManagementService;
    final capabilities = service?.capabilities;
    final kinds = capabilities?.readableKinds ?? const <InterfaceResourceKind>[];

    if (!session.connected || service == null) {
      return _status(
        icon: Icons.cloud_off_outlined,
        title: 'Interface management unavailable',
        message: 'Connect to a firewall to view interface capabilities.',
      );
    }
    if (session.capabilities?.isLimited == true) {
      return _status(
        icon: Icons.schema_outlined,
        title: 'Interface capabilities not available',
        message: session.capabilities?.message ??
            'The OpenAPI schema could not be read for this profile.',
        action: () => session.refreshCapabilities(),
      );
    }
    if (kinds.isEmpty) {
      return _status(
        icon: Icons.settings_ethernet_outlined,
        title: 'No interface endpoints reported',
        message:
            'The connected OpenAPI schema does not report a supported interface collection.',
        action: () => session.refreshCapabilities(),
      );
    }

    final tabKey = kinds.map((kind) => kind.name).join('|');
    return DefaultTabController(
      key: ValueKey('${session.selectedProfile?.id}:$tabKey'),
      length: kinds.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Interfaces'),
          actions: [
            IconButton(
              tooltip: 'Refresh capabilities',
              onPressed: () async {
                await session.refreshCapabilities();
                await _loadAvailableInterfaces();
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
            if (_loadingAvailable) const LinearProgressIndicator(minHeight: 2),
            if (_availableError != null)
              MaterialBanner(
                content: Text(
                  'Available interface names could not be loaded: $_availableError',
                ),
                actions: [
                  TextButton(
                    onPressed: _loadAvailableInterfaces,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final kind in kinds)
                    _InterfaceResourceList(
                      key: ValueKey('${session.selectedProfile?.id}:${kind.name}'),
                      kind: kind,
                      availableInterfaces: _availableInterfaces,
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
      appBar: AppBar(title: const Text('Interfaces')),
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
}

class _InterfaceResourceList extends StatefulWidget {
  const _InterfaceResourceList({
    super.key,
    required this.kind,
    required this.availableInterfaces,
  });

  final InterfaceResourceKind kind;
  final List<AvailableInterface> availableInterfaces;

  @override
  State<_InterfaceResourceList> createState() => _InterfaceResourceListState();
}

class _InterfaceResourceListState extends State<_InterfaceResourceList>
    with AutomaticKeepAliveClientMixin {
  List<ManagedInterfaceResource> _resources = const [];
  Object? _error;
  bool _loading = false;
  bool _busy = false;
  bool _writePermissionDenied = false;
  int _requestGeneration = 0;
  DateTime? _lastRefresh;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resources.isEmpty && !_loading) {
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
    final service = session.interfaceManagementService;
    if (!session.connected || service == null) return;
    final generation = session.sessionGeneration;
    final request = ++_requestGeneration;
    setState(() {
      _loading = true;
      if (showSpinner) _error = null;
    });
    try {
      final resources = await service.list(widget.kind);
      if (!mounted ||
          request != _requestGeneration ||
          generation != session.sessionGeneration) {
        return;
      }
      setState(() {
        _resources = resources;
        _error = null;
        _lastRefresh = DateTime.now();
      });
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _markReadOnly() {
    if (mounted) setState(() => _writePermissionDenied = true);
  }

  Future<void> _openForm([ManagedInterfaceResource? resource]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InterfaceResourceFormScreen(
          kind: widget.kind,
          resource: resource,
          availableInterfaces: widget.availableInterfaces,
          onPermissionDenied: _markReadOnly,
        ),
      ),
    );
    if (changed == true && mounted) await _load(showSpinner: true);
  }

  Future<void> _delete(ManagedInterfaceResource resource) async {
    if (_busy || _writePermissionDenied) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.interfaceManagementService;
    if (!session.connected || service == null) return;
    final capability = service.capabilities.forKind(widget.kind);
    if (!capability.canDelete || !service.capabilities.canApply) return;

    final risk = interfaceChangeRisk(
      original: resource,
      changes: const {'enable': false},
      profile: session.selectedProfile,
    );
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: risk == InterfaceChangeRisk.managementPath
          ? 'Delete management interface?'
          : 'Delete ${widget.kind.singularLabel}?',
      body: risk == InterfaceChangeRisk.managementPath
          ? 'This interface matches the selected firewall address. Applying its deletion will close the current session and may require local recovery or a profile update.'
          : 'Delete “${resource.displayName}” and apply the interface configuration? Active traffic using this resource may be interrupted.',
      slideLabel: 'Slide to delete and apply',
      icon: Icons.delete_forever_outlined,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await service.delete(resource);
      await service.apply();
      if (!mounted) return;
      if (risk == InterfaceChangeRisk.managementPath) {
        await session.disconnect();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The management interface was deleted and the session was closed.',
            ),
            duration: Duration(seconds: 8),
          ),
        );
      } else {
        await _load(showSpinner: true);
      }
    } on ApiException catch (error) {
      if (error.isPermissionError) _markReadOnly();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.interfaceManagementService;
    final capability = service?.capabilities.forKind(widget.kind);
    final canApply = service?.capabilities.canApply == true;
    final canCreate = session.connected &&
        capability?.canCreate == true &&
        canApply &&
        !_writePermissionDenied &&
        !_busy;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(showSpinner: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CapabilitySummary(
              kind: widget.kind,
              capability: capability,
              canApply: canApply,
              writePermissionDenied: _writePermissionDenied,
            ),
            if (_lastRefresh != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last updated ${_time(_lastRefresh!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (_loading && _resources.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (_loading) const LinearProgressIndicator(minHeight: 3),
              if (_error != null)
                _message(Icons.error_outline, _error.toString()),
              if (!_loading && _error == null && _resources.isEmpty)
                _message(
                  _kindIcon(widget.kind),
                  'No ${widget.kind.label.toLowerCase()} returned.',
                ),
              for (final resource in _resources)
                _resourceCard(
                  resource,
                  canEdit: capability?.canUpdate == true &&
                      canApply &&
                      !_writePermissionDenied &&
                      !_busy,
                  canDelete: capability?.canDelete == true &&
                      canApply &&
                      !_writePermissionDenied &&
                      !_busy,
                ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canCreate ? () => _openForm() : null,
        icon: const Icon(Icons.add),
        label: Text('Add ${widget.kind.singularLabel}'),
      ),
    );
  }

  Widget _resourceCard(
    ManagedInterfaceResource resource, {
    required bool canEdit,
    required bool canDelete,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_kindIcon(widget.kind))),
        title: Text(resource.displayName),
        subtitle: Text(resource.summary),
        onTap: canEdit ? () => _openForm(resource) : null,
        trailing: PopupMenuButton<String>(
          enabled: canEdit || canDelete,
          onSelected: (value) {
            if (value == 'edit') _openForm(resource);
            if (value == 'delete') _delete(resource);
          },
          itemBuilder: (_) => [
            if (canEdit)
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                ),
              ),
            if (canDelete)
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _message(IconData icon, String text) =>
      Card(child: ListTile(leading: Icon(icon), title: Text(text)));
}

class _CapabilitySummary extends StatelessWidget {
  const _CapabilitySummary({
    required this.kind,
    required this.capability,
    required this.canApply,
    required this.writePermissionDenied,
  });

  final InterfaceResourceKind kind;
  final InterfaceResourceCapability? capability;
  final bool canApply;
  final bool writePermissionDenied;

  @override
  Widget build(BuildContext context) {
    final writes = <String>[
      if (capability?.canCreate == true) 'create',
      if (capability?.canUpdate == true) 'edit',
      if (capability?.canDelete == true) 'delete',
    ];
    final readOnly = writePermissionDenied || writes.isEmpty || !canApply;
    return Card(
      child: ListTile(
        leading: Icon(
          readOnly ? Icons.visibility_outlined : Icons.edit_note_outlined,
        ),
        title: Text(readOnly ? 'View-only ${kind.label}' : 'Managed ${kind.label}'),
        subtitle: Text(
          writePermissionDenied
              ? 'A write request was denied with 403. Changes are disabled for this session.'
              : !canApply
                  ? 'The apply endpoint is unavailable, so configuration changes are disabled.'
                  : writes.isEmpty
                      ? 'The schema reports read access only.'
                      : 'Available actions: ${writes.join(', ')}. Changes are applied explicitly after confirmation.',
        ),
      ),
    );
  }
}

IconData _kindIcon(InterfaceResourceKind kind) => switch (kind) {
      InterfaceResourceKind.assigned => Icons.settings_ethernet,
      InterfaceResourceKind.vlan => Icons.account_tree_outlined,
      InterfaceResourceKind.bridge => Icons.device_hub_outlined,
      InterfaceResourceKind.lagg => Icons.join_inner_outlined,
      InterfaceResourceKind.gre => Icons.swap_horiz_outlined,
      InterfaceResourceKind.gif => Icons.compare_arrows_outlined,
    };

String _time(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
