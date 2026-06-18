import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/session_provider.dart';

/// Displays an IP address or MAC address as interactable text with a dotted
/// underline in the theme's primary colour. Tapping opens a bottom sheet with
/// copy-to-clipboard and (for IP addresses) a DNS / reverse lookup action
/// that queries the pfSense diagnostics API.
class NetworkAssetText extends StatelessWidget {
  const NetworkAssetText({
    super.key,
    required this.value,
    this.style,
    this.isIp,
  });

  /// The IP address (e.g. "192.168.1.45") or MAC address
  /// (e.g. "aa:bb:cc:dd:ee:ff") to display.
  final String value;

  /// Optional base text style. The widget will override [TextStyle.color],
  /// [TextStyle.decoration], and [TextStyle.decorationStyle].
  final TextStyle? style;

  /// Whether [value] is an IP address. When null the widget auto-detects
  /// by checking for four dot-separated numeric octets.
  final bool? isIp;

  static final _ipPattern = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  bool get _effectiveIsIp => isIp ?? _ipPattern.hasMatch(value.trim());

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final baseStyle = (style ?? Theme.of(context).textTheme.bodyMedium) ?? const TextStyle();
    return GestureDetector(
      onTap: () => _showSheet(context),
      child: Text.rich(
        TextSpan(
          text: value,
          style: baseStyle.copyWith(
            color: primary,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: primary,
          ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _NetworkAssetSheet(
        value: value,
        isIp: _effectiveIsIp,
      ),
    );
  }
}

class _NetworkAssetSheet extends StatefulWidget {
  const _NetworkAssetSheet({required this.value, required this.isIp});

  final String value;
  final bool isIp;

  @override
  State<_NetworkAssetSheet> createState() => _NetworkAssetSheetState();
}

class _NetworkAssetSheetState extends State<_NetworkAssetSheet> {
  Map<String, dynamic>? _lookupResult;
  bool _lookupLoading = false;
  Object? _lookupError;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.value} copied'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _dnsLookup() async {
    if (_lookupLoading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      setState(() => _lookupError = 'Not connected to a firewall');
      return;
    }
    setState(() {
      _lookupLoading = true;
      _lookupError = null;
      _lookupResult = null;
    });
    try {
      final result = await session.service!.runDnsLookup(
        widget.value,
        type: 'PTR', // reverse lookup for IPs
      );
      if (mounted) setState(() => _lookupResult = result);
    } catch (e) {
      if (mounted) setState(() => _lookupError = e);
    } finally {
      if (mounted) setState(() => _lookupLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          20,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    widget.isIp ? Icons.router_outlined : Icons.device_hub_outlined,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.value,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                      Text(
                        widget.isIp ? 'IPv4 address' : 'MAC address',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            // Copy action
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy to clipboard'),
              subtitle: const Text('Also triggers a light haptic confirmation'),
              onTap: _copy,
            ),
            const Divider(height: 1),
            // DNS lookup (IP only)
            if (widget.isIp) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dns_outlined),
                title: const Text('DNS / Reverse lookup'),
                subtitle: const Text('Query via pfSense diagnostics API'),
                trailing: _lookupLoading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _lookupLoading ? null : _dnsLookup,
              ),
              if (_lookupError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                  child: Text(
                    _lookupError.toString(),
                    style: TextStyle(
                      color: scheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_lookupResult != null) ...[
                const SizedBox(height: 4),
                _LookupResultCard(data: _lookupResult!),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _LookupResultCard extends StatelessWidget {
  const _LookupResultCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final output = data['output'] as String? ??
        data['result'] as String? ??
        data['hostname'] as String? ??
        data.entries.map((e) => '${e.key}: ${e.value}').join('\n');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              output,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
