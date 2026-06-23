import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Diagnostics'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.network_ping_outlined), text: 'Ping'),
            Tab(icon: Icon(Icons.route_outlined), text: 'Traceroute'),
            Tab(icon: Icon(Icons.dns_outlined), text: 'DNS Lookup'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _PingTab(),
          _TracerouteTab(),
          _DnsTab(),
        ],
      ),
    );
  }
}

// ── Ping ─────────────────────────────────────────────────────────────────────

class _PingTab extends StatefulWidget {
  const _PingTab();
  @override
  State<_PingTab> createState() => _PingTabState();
}

class _PingTabState extends State<_PingTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _host = TextEditingController();
  int _count = 4;
  Map<String, dynamic>? _result;
  bool _running = false;
  Object? _error;

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
    } catch (e) {
      if (mounted) setState(() => _error = e);
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
        _HostField(controller: _host, label: 'Target host or IP', hint: '8.8.8.8 or example.com'),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Packets: '),
            for (final n in [1, 4, 8, 16])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text('$n'),
                  selected: _count == n,
                  onSelected: (_) => setState(() => _count = n),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _RunButton(running: _running, onPressed: _run, label: 'Run Ping'),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(error: _error!),
        ],
        if (_result != null) ...[
          const SizedBox(height: 12),
          _ResultCard(data: _result!),
        ],
      ],
    );
  }
}

// ── Traceroute ────────────────────────────────────────────────────────────────

class _TracerouteTab extends StatefulWidget {
  const _TracerouteTab();
  @override
  State<_TracerouteTab> createState() => _TracerouteTabState();
}

class _TracerouteTabState extends State<_TracerouteTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _host = TextEditingController();
  int _maxHops = 30;
  Map<String, dynamic>? _result;
  bool _running = false;
  Object? _error;

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
      final data = await session.service!.runTraceroute(host, maxHops: _maxHops);
      if (mounted) setState(() => _result = data);
    } catch (e) {
      if (mounted) setState(() => _error = e);
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
        _HostField(controller: _host, label: 'Target host or IP', hint: '8.8.8.8 or example.com'),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Max hops: '),
            for (final n in [15, 30, 64])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text('$n'),
                  selected: _maxHops == n,
                  onSelected: (_) => setState(() => _maxHops = n),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _RunButton(running: _running, onPressed: _run, label: 'Run Traceroute'),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(error: _error!),
        ],
        if (_result != null) ...[
          const SizedBox(height: 12),
          _ResultCard(data: _result!),
        ],
      ],
    );
  }
}

// ── DNS Lookup ────────────────────────────────────────────────────────────────

class _DnsTab extends StatefulWidget {
  const _DnsTab();
  @override
  State<_DnsTab> createState() => _DnsTabState();
}

class _DnsTabState extends State<_DnsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _host = TextEditingController();
  String _type = 'A';
  Map<String, dynamic>? _result;
  bool _running = false;
  Object? _error;

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
    } catch (e) {
      if (mounted) setState(() => _error = e);
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
        _HostField(controller: _host, label: 'Host or IP address', hint: 'example.com or 192.168.1.1'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          children: [
            for (final t in ['A', 'AAAA', 'MX', 'PTR', 'TXT', 'CNAME'])
              ChoiceChip(
                label: Text(t),
                selected: _type == t,
                onSelected: (_) => setState(() => _type = t),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _RunButton(running: _running, onPressed: _run, label: 'Run DNS Lookup'),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(error: _error!),
        ],
        if (_result != null) ...[
          const SizedBox(height: 12),
          _ResultCard(data: _result!),
        ],
      ],
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _HostField extends StatelessWidget {
  const _HostField({required this.controller, required this.label, required this.hint});
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
  const _RunButton({required this.running, required this.onPressed, required this.label});
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
  const _ErrorCard({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
        title: Text(
          error.toString(),
          style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
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
    // Build a formatted display from whatever keys the API returns
    final output = data['output'] as String? ??
        data['result'] as String? ??
        data['raw'] as String? ??
        data.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('\n');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline, size: 18, color: Theme.of(context).colorScheme.primary),
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
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
              ),
            ),
            // Show structured stats if available
            if (data['rtt_avg'] != null || data['rtt_min'] != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                children: [
                  if (data['rtt_min'] != null) _Stat('Min RTT', '${data['rtt_min']} ms'),
                  if (data['rtt_avg'] != null) _Stat('Avg RTT', '${data['rtt_avg']} ms'),
                  if (data['rtt_max'] != null) _Stat('Max RTT', '${data['rtt_max']} ms'),
                  if (data['loss'] != null) _Stat('Packet loss', '${data['loss']}%'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
