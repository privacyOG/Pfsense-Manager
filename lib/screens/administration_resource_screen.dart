import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/administration_management.dart';
import '../providers/session_provider.dart';
import '../utils/api_exception.dart';
import '../widgets/slide_to_confirm.dart';
import 'administration_form_screen.dart';

class AdministrationResourceScreen extends StatefulWidget {
  const AdministrationResourceScreen({
    super.key,
    required this.kind,
  });

  final AdministrationResourceKind kind;

  @override
  State<AdministrationResourceScreen> createState() =>
      _AdministrationResourceScreenState();
}

class _AdministrationResourceScreenState
    extends State<AdministrationResourceScreen> {
  List<ManagedAdministrationResource> _resources = const [];
  Object? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    final service = session.administrationService;
    if (!session.connected || service == null) return;
    final request = ++_request;
    final generation = session.sessionGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resources = await service.list(widget.kind);
      if (!mounted ||
          request != _request ||
          generation != session.sessionGeneration) {
        return;
      }
      setState(() => _resources = resources);
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([ManagedAdministrationResource? resource]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdministrationFormScreen.resource(
          kind: widget.kind,
          resource: resource,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _delete(ManagedAdministrationResource resource) async {
    final session = context.read<PfSenseSessionProvider>();
    final service = session.administrationService;
    if (service == null) return;
    final confirmed = await showSlideToConfirmSheet(
      context: context,
      title: 'Delete ${widget.kind.singularLabel}?',
      body:
          'This permanently deletes ${resource.displayName}. Authentication, certificate trust, API access, package state, or system behavior may be affected.',
      slideLabel: 'Slide to delete',
      icon: Icons.delete_forever_outlined,
    );
    if (confirmed != true || !mounted) return;
    try {
      await service.delete(resource);
      if (mounted) await _load();
    } on ApiException catch (error) {
      if (mounted) _message(error.toString());
    } catch (error) {
      if (mounted) _message(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final service = session.administrationService;
    final capability = service?.capabilities.forResource(widget.kind);
    final singleton = widget.kind.singleton;
    final mutationNotice = capability?.mutationNotice;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind.label),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: !singleton && capability?.canCreate == true
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (mutationNotice != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Mutation unavailable'),
                  subtitle: Text(mutationNotice),
                ),
              ),
            if (_error != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(_error.toString()),
                  trailing: TextButton(onPressed: _load, child: const Text('Retry')),
                ),
              )
            else if (!_loading && _resources.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: Text('No ${widget.kind.label.toLowerCase()} reported'),
                  subtitle: Text(
                    singleton && capability?.canUpdate == true
                        ? 'Create or configure this singleton using the edit action below.'
                        : 'The connected firewall returned no records.',
                  ),
                  trailing: singleton && capability?.canUpdate == true
                      ? FilledButton(
                          onPressed: () => _openForm(),
                          child: const Text('Configure'),
                        )
                      : null,
                ),
              ),
            for (final resource in _resources)
              Card(
                child: ExpansionTile(
                  leading: Icon(_icon(widget.kind)),
                  title: Text(resource.displayName),
                  subtitle: resource.summary.isEmpty
                      ? null
                      : Text(resource.summary),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(resource.raw),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (capability?.canUpdate == true)
                          FilledButton.tonalIcon(
                            onPressed: () => _openForm(resource),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit'),
                          ),
                        if (!singleton && capability?.canDelete == true)
                          OutlinedButton.icon(
                            onPressed: () => _delete(resource),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

IconData _icon(AdministrationResourceKind kind) => switch (kind.section) {
      AdministrationSection.certificates => Icons.workspace_premium_outlined,
      AdministrationSection.identities => Icons.manage_accounts_outlined,
      AdministrationSection.apiAccess => Icons.key_outlined,
      AdministrationSection.system => Icons.settings_suggest_outlined,
      AdministrationSection.services => Icons.miscellaneous_services_outlined,
    };