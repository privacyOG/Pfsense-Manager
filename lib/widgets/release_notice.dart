import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/release_check_service.dart';

class ReleaseNotice extends StatefulWidget {
  const ReleaseNotice({super.key, required this.child});

  final Widget child;

  @override
  State<ReleaseNotice> createState() => _ReleaseNoticeState();
}

class _ReleaseNoticeState extends State<ReleaseNotice> {
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    try {
      final release = await ReleaseCheckService().check();
      if (!mounted || release == null) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text('Version ${release.version} is available'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'A newer pfSense Manager release is ready. Review the notes before opening the release page.',
                  ),
                  if (release.notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Release notes',
                      style: Theme.of(dialogContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(release.notes),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Later'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final opened = await launchUrl(
                  release.url,
                  mode: LaunchMode.externalApplication,
                );
                if (!dialogContext.mounted) return;
                if (opened) {
                  Navigator.of(dialogContext).pop();
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open release page'),
            ),
          ],
        ),
      );
    } catch (_) {
      // A failed release check must not interrupt normal app startup.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
