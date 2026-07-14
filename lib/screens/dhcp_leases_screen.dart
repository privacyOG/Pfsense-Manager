import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/dhcp_lease.dart';
import '../models/dhcp_management.dart';
import '../models/interface_management.dart';
import '../providers/session_provider.dart';
import '../widgets/state_message.dart';
import 'dhcp_management_screen.dart';
import 'dhcp_resource_form_screen.dart';

class DhcpLeasesScreen extends StatefulWidget {
  const DhcpLeasesScreen({super.key});

  @override
  State<DhcpLeasesScreen> createState() => _DhcpLeasesScreenState();
}

class _DhcpLeasesScreenState extends State<DhcpLeasesScreen> {
  final _search = TextEditingController();
  List<DhcpLease> _leases = [];
  Object? _error;
  bool _loading = false;
  bool _actionBusy = false;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;
  DateTime? _lastSuccessfulRefresh;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final sessionChanged =
        _loadedSessionGeneration != session.sessionGeneration ||
            _loadedProfileId != profileId;

    if (sessionChanged) {
      _requestGeneration++;
      _leases = [];
      _error = null;
      _lastSuccessfulRefresh = null;
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(showSpinner: true);
        });
      }
    } else if (_leases.isEmpty && !_loading && session.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(showSpinner: true);
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      if (!mounted) return;
      final disconnected = AppStrings.of(context).t('disconnected');
      setState(() {
        _leases = [];
        _lastSuccessfulRefresh = null;
        _error = disconnected;
      });
      return;
    }

    final request = ++_requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    setState(() {
      _loading = true;
      if (showSpinner) _error = null;
    });

    try {
      final leases = await session.service!.getDhcpLeases();
      if (!mounted ||
          request != _requestGeneration ||
          sessionGeneration != session.sessionGeneration ||
          profileId != session.selectedProfile?.id) {
        return;
      }
      setState(() {
        _leases = leases;
        _error = null;
        _lastSuccessfulRefresh = DateTime.now();
      });
    } catch (error) {
      if (!mounted || request != _requestGeneration) return;
      setState(() => _error = error);
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openManagement() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const DhcpManagementScreen()),
    );
    if (mounted) await _load(showSpinner: true);
  }

  Future<void> _createStaticMapping(DhcpLease lease) async {
    if (_actionBusy) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.dhcpManagementService;
    if (!session.connected || service == null) return;
    final mappingCapability =
        service.capabilities.forKind(DhcpResourceKind.staticMapping);
    if (!mappingCapability.canCreate || !service.capabilities.canApply) return;

    setState(() => _actionBusy = true);
    try {
      final servers = service.capabilities
              .forKind(DhcpResourceKind.server)
              .canRead
          ? await service.list(DhcpResourceKind.server)
          : const <ManagedDhcpResource>[];
      if (servers.isEmpty) {
        if (mounted) {
          _message(
            'Create a DHCP server configuration before adding a static mapping.',
          );
        }
        return;
      }

      final mappings = service.capabilities
              .forKind(DhcpResourceKind.staticMapping)
              .canRead
          ? await service.list(DhcpResourceKind.staticMapping)
          : const <ManagedDhcpResource>[];
      final pools = service.capabilities
              .forKind(DhcpResourceKind.addressPool)
              .canRead
          ? await service.list(DhcpResourceKind.addressPool)
          : const <ManagedDhcpResource>[];

      var interfaces = const <ManagedInterfaceResource>[];
      final interfaceService = session.interfaceManagementService;
      if (interfaceService
              ?.capabilities
              .forKind(InterfaceResourceKind.assigned)
              .canRead ==
          true) {
        try {
          interfaces =
              await interfaceService!.list(InterfaceResourceKind.assigned);
        } catch (_) {
          interfaces = const [];
        }
      }

      if (!mounted) return;
      final parentId = await _resolveParentServer(
        lease: lease,
        servers: servers,
        interfaces: interfaces,
      );
      if (parentId == null || !mounted) return;

      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DhcpResourceFormScreen(
            kind: DhcpResourceKind.staticMapping,
            initialValues: {
              'parent_id': parentId,
              'mac': lease.macAddress,
              'ipaddr': lease.ipAddress,
              'hostname': lease.hostname,
              'descr': lease.description,
            },
            servers: servers,
            staticMappings: mappings,
            addressPools: pools,
            interfaces: interfaces,
            relayEnabled: false,
          ),
        ),
      );
      if (changed == true && mounted) await _load(showSpinner: true);
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<String?> _resolveParentServer({
    required DhcpLease lease,
    required List<ManagedDhcpResource> servers,
    required List<ManagedInterfaceResource> interfaces,
  }) async {
    final leaseInterface = _normaliseInterface(lease.interface);
    final matches = servers.where((server) {
      final serverId = _normaliseInterface(server.interfaceId);
      if (serverId == leaseInterface && serverId.isNotEmpty) return true;
      for (final interface in interfaces) {
        if (interface.id?.toString() != server.interfaceId) continue;
        final candidates = [
          interface.interfaceName,
          interface.description,
          interface.id?.toString() ?? '',
        ].map(_normaliseInterface);
        if (candidates.contains(leaseInterface)) return true;
      }
      return false;
    }).toList(growable: false);
    if (matches.length == 1) return matches.single.interfaceId;
    if (servers.length == 1) return servers.single.interfaceId;

    var selected = matches.isNotEmpty
        ? matches.first.interfaceId
        : servers.first.interfaceId;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select DHCP server'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: const InputDecoration(
              labelText: 'Parent DHCP interface',
            ),
            items: [
              for (final server in servers)
                DropdownMenuItem(
                  value: server.interfaceId,
                  child: Text(_serverLabel(server.interfaceId, interfaces)),
                ),
            ],
            onChanged: (value) =>
                setDialogState(() => selected = value ?? selected),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _wake(DhcpLease lease) async {
    if (_actionBusy) return;

    final selectedInterface = await _selectWakeInterface(lease);
    if (selectedInterface == null || selectedInterface.isEmpty || !mounted) {
      return;
    }

    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;
    setState(() => _actionBusy = true);
    try {
      await session.service!.sendWakeOnLan(
        lease.macAddress,
        interface: selectedInterface,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).f('magicPacketSent', {
                'target': lease.hostname.isNotEmpty
                    ? lease.hostname
                    : lease.macAddress,
              }),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<String?> _selectWakeInterface(DhcpLease lease) async {
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return null;

    final options = <String, String>{};
    void addInterface(String value, [String? label]) {
      final normalised = _normaliseInterface(value);
      if (normalised.isEmpty) return;
      final cleanedLabel = label?.trim() ?? '';
      options.putIfAbsent(
        normalised,
        () => cleanedLabel.isEmpty || cleanedLabel == normalised
            ? normalised
            : '$cleanedLabel ($normalised)',
      );
    }

    addInterface(lease.interface);
    try {
      final interfaces = await session.service!.getInterfaceStatuses();
      for (final interface in interfaces) {
        final value = interface.name.trim().isNotEmpty
            ? interface.name
            : interface.description;
        addInterface(value, interface.description);
      }
    } catch (_) {
      // The lease interface is enough for Wake-on-LAN; status loading is
      // best-effort so an unrelated endpoint problem does not block the action.
    }

    if (!mounted) return null;
    final leaseInterface = _normaliseInterface(lease.interface);
    var selected = options.containsKey(leaseInterface)
        ? leaseInterface
        : (options.isEmpty ? '' : options.keys.first);
    final controller = TextEditingController(text: selected);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canSend = selected.trim().isNotEmpty;
          return AlertDialog(
            title: Text(AppStrings.of(context).t('wakeOnLan')),
            content: options.isEmpty
                ? TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Interface'),
                    onChanged: (value) {
                      setDialogState(() {
                        selected = _normaliseInterface(value);
                      });
                    },
                  )
                : DropdownButtonFormField<String>(
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: 'Interface'),
                    items: [
                      for (final entry in options.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selected = value ?? '';
                      });
                    },
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppStrings.of(context).t('cancel')),
              ),
              FilledButton(
                onPressed: canSend
                    ? () => Navigator.pop(dialogContext, selected.trim())
                    : null,
                child: Text(AppStrings.of(context).t('confirm')),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _delete(DhcpLease lease) async {
    if (_actionBusy) return;
    final strings = AppStrings.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.t('deleteDhcpLease')),
        content: Text(
          strings.f('removeLeaseConfirm', {
            'target':
                lease.ipAddress.isEmpty ? lease.macAddress : lease.ipAddress,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.t('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) return;

    setState(() => _actionBusy = true);
    try {
      await session.service!.deleteDhcpLease(lease);
      await _load(showSpinner: true);
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final session = context.watch<PfSenseSessionProvider>();
    final management = session.dhcpManagementService;
    final query = _search.text.trim().toLowerCase();
    final visible = _leases
        .where(
          (lease) =>
              query.isEmpty ||
              lease.ipAddress.toLowerCase().contains(query) ||
              lease.macAddress.toLowerCase().contains(query) ||
              lease.hostname.toLowerCase().contains(query) ||
              lease.interface.toLowerCase().contains(query),
        )
        .toList();
    final active = _leases.where((lease) => lease.active).length;
    final staticCount = _leases.where((lease) => lease.staticMapping).length;
    final canManage = management?.capabilities.canReadAnything == true;
    final mappingCapability =
        management?.capabilities.forKind(DhcpResourceKind.staticMapping);
    final canCreateMapping = mappingCapability?.canCreate == true &&
        management?.capabilities.canApply == true;

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _LeaseSummary(
            total: session.connected ? _leases.length : 0,
            active: session.connected ? active : 0,
            staticCount: session.connected ? staticCount : 0,
            canManage: canManage,
            onManage: _actionBusy ? null : _openManagement,
          ),
          if (_lastSuccessfulRefresh != null) ...[
            const SizedBox(height: 8),
            Text(
              strings.f(
                'lastUpdated',
                {'time': _formatTime(_lastSuccessfulRefresh!)},
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: strings.t('searchLeases'),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            StateMessage(
              icon: Icons.cloud_off_outlined,
              text: strings.t('disconnected'),
            )
          else if (_error != null)
            StateMessage(
              icon: Icons.error_outline,
              text: _error.toString(),
            )
          else if (!_loading && visible.isEmpty)
            StateMessage(
              icon: Icons.dns_outlined,
              text: strings.t('noLeases'),
            ),
          if (session.connected)
            for (final lease in visible)
              _LeaseTile(
                lease: lease,
                onDelete: _actionBusy ? null : () => _delete(lease),
                onWake: lease.macAddress.isNotEmpty && !_actionBusy
                    ? () => _wake(lease)
                    : null,
                onReserve: canCreateMapping &&
                        !lease.staticMapping &&
                        lease.macAddress.isNotEmpty &&
                        !_actionBusy
                    ? () => _createStaticMapping(lease)
                    : null,
              ),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

String _normaliseInterface(String value) => value.trim().toLowerCase();

String _serverLabel(
  String id,
  List<ManagedInterfaceResource> interfaces,
) {
  for (final interface in interfaces) {
    if (interface.id?.toString() == id) {
      return interface.description.isEmpty
          ? id.toUpperCase()
          : '${interface.description} ($id)';
    }
  }
  return id.toUpperCase();
}

class _LeaseSummary extends StatelessWidget {
  const _LeaseSummary({
    required this.total,
    required this.active,
    required this.staticCount,
    required this.canManage,
    required this.onManage,
  });

  final int total;
  final int active;
  final int staticCount;
  final bool canManage;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.router_outlined, color: Color(0xFF00C2A8)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              strings.t('dhcpManagement'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          _MiniStat(strings.t('active'), active.toString()),
          _MiniStat(strings.t('static'), staticCount.toString()),
          _MiniStat(strings.t('total'), total.toString()),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('open-dhcp-management'),
            tooltip: 'Configure DHCP',
            onPressed: canManage ? onManage : null,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

class _LeaseTile extends StatelessWidget {
  const _LeaseTile({
    required this.lease,
    required this.onDelete,
    required this.onWake,
    required this.onReserve,
  });

  final DhcpLease lease;
  final VoidCallback? onDelete;
  final VoidCallback? onWake;
  final VoidCallback? onReserve;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final color = lease.active ? const Color(0xFF00C2A8) : Colors.orangeAccent;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .16),
          child: Icon(Icons.devices_other, color: color),
        ),
        title: Text(
          lease.hostname.isEmpty ? lease.ipAddress : lease.hostname,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          [
            if (lease.ipAddress.isNotEmpty) lease.ipAddress,
            if (lease.macAddress.isNotEmpty) lease.macAddress,
            if (lease.interface.isNotEmpty) lease.interface,
            lease.state,
          ].join('  |  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          enabled: onWake != null || onReserve != null || onDelete != null,
          onSelected: (value) {
            if (value == 'wake') onWake?.call();
            if (value == 'reserve') onReserve?.call();
            if (value == 'delete') onDelete?.call();
          },
          itemBuilder: (_) => [
            if (onReserve != null)
              const PopupMenuItem(
                value: 'reserve',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.push_pin_outlined),
                  title: Text('Create static mapping'),
                ),
              ),
            if (onWake != null)
              PopupMenuItem(
                value: 'wake',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.power_settings_new_outlined),
                  title: Text(strings.t('wakeOnLan')),
                ),
              ),
            if (onDelete != null)
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: Text(strings.t('deleteLease')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
