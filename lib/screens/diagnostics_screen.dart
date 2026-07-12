import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';
import '../services/pfrest_feature_registry.dart';
import '../utils/ping_request_validation.dart';
import '../widgets/pfrest_feature_gate.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final registry = PfRestFeatureRegistry(
      activeProfileId: session.selectedProfile?.id,
      capabilities: session.capabilities,
    );
    final traceroute = registry.decision(PfRestFeature.traceroute);
    final dnsLookup = registry.decision(PfRestFeature.dnsLookup);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Refresh capabilities',
            onPressed: session.connected
                ? () => session.refreshCapabilities()
                : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(icon: Icon(Icons.network_ping_outlined), text: 'Ping'),
            Tab(
              icon: Icon(
                traceroute.isUnsupported
                    ? Icons.extension_off_outlined
                    : Icons.route_outlined,
              ),
              text: 'Traceroute',
            ),
            Tab(
              icon: Icon(
                dnsLookup.isUnsupported
                    ? Icons.extension_off_outlined
                    : Icons.dns_outlined,
              ),
              text: 'DNS Lookup',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const _PingTab(),
          traceroute.isUnsupported
              ? PfRestFeatureBlockedView(
                  decision: traceroute,
                  onRefresh: () => session.refreshCapabilities(),
                )
              : _TracerouteTab(decision: traceroute),
          dnsLookup.isUnsupported
              ? PfRestFeatureBlockedView(
                  decision: dnsLookup,
                  onRefresh: () => session.refreshCapabilities(),
                )
              : _DnsTab(decision: dnsLookup),
        ],
      ),
    );
  }
}

class _PingTab extends StatefulWidget {
  const _PingTab();

  @override
  State<_PingTab> createState() => _PingTabState();
}

class _PingTabState extends State<_PingTab>
    with AutomaticKeepAliveClientMixin {
  final _host = TextEditingController();
  int _count = 4;
  Map<String, dynamic>? _result;
  bool _running = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      setState(() => _error = 'Not connected to a firewall');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      final data = await session.service!.runPing(host, count: _count);
      if (mounted) setState(() => _result = data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HostField(
          controller: _host,
          label: 'Target host or IP',
          hint: '8.8.8.8 or example.com',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final count in pingPacketCountChoices)
              ChoiceChip(
                label: Text('$count'),
                selected: _count == count,
                onSelected: (_) => setState(() => _count = count),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _RunButton(running: _running, onPressed: _run, label: 'Run Ping'),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(message: _error.toString()),
        ],
        if (_result != null) ...[
          const SizedBox(height: 12),
          _ResultCard(data: _result!),
        ],
      ],
    );
  }
}

class _TracerouteTab extends StatefulWidget {
  const _TracerouteTab({required this.decision});

  final PfRestFeatureDecision decision;

  @override
  State<_TracerouteTab> createState() => _TracerouteTabState();
}

class _TracerouteTabState extends State<_TracerouteTab>
    with AutomaticKeepAliveClientMixin {
  final _host = TextEditingController();
  int _maxHops = 30;
  Map<String, dynamic>? _result;
  bool _running = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      setState(() => _error = 'Not connected to a firewall');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      final data = await session.service!.runTraceroute(
        host,
        maxHops: _maxHops,
      );
      if (mounted) setState(() => _result = data);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = pfRestFeatureRequestErrorMessage(
            PfRestFeature.traceroute,
            error,
          );
        });
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = context.watch<PfSenseSessionProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.decision.isUnknown) ...[
          PfRestFeatureNotice(
            decision: widget.decision,
            onRefresh: () => session.refreshCapabilities(),
          ),
          const SizedBox(height: 12),
        ],
        _HostField(
          controller: _host,
          label: 'Target host or IP',
          hint: '8.8.8.8 or example.com',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final hops in const [15, 30, 64])
              ChoiceChip(
                label: Text('$hops hops'),
                selected: _maxHops == hops,
                onSelected: (_) => setState(() => _maxHops = hops),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _RunButton(
          running: _running,
          onPressed: _run,
          label: 'Run Traceroute',
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(message: _error!),
        ],
        if (_result != null) ...[
          const SizedBox(height: 12),
          _ResultCard(data: _result!),
        ],
      ],
    );
  }
}

class _DnsTab extends StatefulWidget {
  const _DnsTab({required this.decision});

  final PfRestFeatureDecision decision;

  @override
  State<_DnsTab> createState() => _DnsTabState();
}

class _DnsTabState extends State<_DnsTab>
    with AutomaticKeepAliveClientMixin {
  final _host = TextEditingController();
  String _type = 'A';
  Map<String, dynamic>? _result;
  bool _running = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      setState(() => _error = 'Not connected to a firewall');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      final data = await session.service!.runDnsLookup(host, type: _type);
      if (mounted) setState(() => _result = data);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = pfRestFeatureRequestErrorMessage(
            PfRestFeature.dnsLookup,
            error,
          );
        });
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = context.watch<PfSenseSessionProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.decision.isUnknown) ...[
          PfRestFeatureNotice(
            decision: widget.decision,
            onRefresh: () => session.refreshCapabilities(),
          ),
          const SizedBox(height: 12),
        ],
        _HostField(
          controller: _host,
          label: 'Host or IP address',
          hint: 'example.com or 192.168.1.1',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          children: [
            for (final type in const ['A', 'AAAA', 'MX', 'PTR', 'TXT', 'CNAME'])
              ChoiceChip(
                label: Text(type),
                selected: _type == type,
                onSelected: (_) => setState(() => _type = type),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _RunButton(
          running: _running,
          onPressed: _run,
          label: 'Run DNS Lookup',
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(message: _error!),
        ],
        if (_result != null) ...[
          const SizedBox(height: 12),
          _ResultCard(data: _result!),
        ],
      ],
    );
  }
}

class _HostField extends StatelessWidget {
  const _HostField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.url,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: const Icon(Icons.language_outlined),
      ),
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({
    required this.running,
    required this.onPressed,
    required this.label,
  });

  final bool running;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: running ? null : onPressed,
      icon: running
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : const Icon(Icons.play_arrow_outlined),
      label: Text(running ? 'Running…' : label),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(
          Icons.error_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        title: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final output = data['output'] as String? ??
        data['result'] as String? ??
        data['raw'] as String? ??
        data.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Result', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: output));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                output,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
