import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../providers/session_provider.dart';
import '../services/api_client.dart';
import '../services/certificate_trust.dart';
import '../services/connection_check.dart';
import 'profile_form_screen.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.watch<ProfileProvider>();
    context.watch<PfSenseSessionProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l?.profiles ?? 'Profiles'),
        actions: [
          IconButton(
            tooltip: l?.importJson ?? 'Import JSON',
            onPressed: () => _import(context),
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: l?.exportJson ?? 'Export profiles',
            onPressed:
                p.profiles.isEmpty ? null : () => _showExportActions(context),
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await p.loadProfiles();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (p.isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (p.profiles.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(l?.emptyState ?? 'Nothing to show yet.'),
                  subtitle: Text(l?.addProfile ?? 'Add profile'),
                ),
              )
            else
              for (final profile in p.profiles)
                _ProfileTile(profile: profile),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: Text(l?.addProfile ?? 'Add profile'),
      ),
    );
  }

  Future<void> _showExportActions(BuildContext context) async {
    final json = context.read<ProfileProvider>().exportProfiles();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Export profiles',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Connection details are included. API keys and passwords are never exported.',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.save_alt_outlined),
                title: const Text('Save JSON file'),
                subtitle: const Text('Choose where to store the profile export'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _saveExport(context, json);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share JSON'),
                subtitle: const Text('Send the export using another application'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Share.share(
                    json,
                    subject: 'pfSense Manager profile export',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_copy_outlined),
                title: const Text('Copy JSON'),
                subtitle: const Text('Place the export on the clipboard'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Clipboard.setData(ClipboardData(text: json));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profile JSON copied.')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveExport(BuildContext context, String json) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save profile export',
        fileName: 'pfsense-manager-profiles.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile export saved.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save profile export: $error')),
        );
      }
    }
  }

  Future<void> _import(BuildContext context) async {
    final l = AppLocalizations.of(context);
    try {
      final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (r == null || r.files.isEmpty) return;
      final b = r.files.single.bytes;
      if (b == null) {
        throw const FormatException('Unable to read selected file.');
      }
      if (!context.mounted) return;
      final count = await context
          .read<ProfileProvider>()
          .importProfiles(String.fromCharCodes(b));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${l?.importedProfiles ?? 'Profiles imported'}: $count',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}

class _ProfileTile extends StatefulWidget {
  const _ProfileTile({required this.profile});

  final PfSenseProfile profile;

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  bool _testing = false;

  Future<void> _test() async {
    setState(() => _testing = true);
    PfSenseApiClient? client;
    try {
      final resolved = await ProfileProvider.resolveForConnection(widget.profile);
      if (!mounted) return;
      client = PfSenseApiClient(resolved);
      final result = await PfSenseConnectionChecker(client).check();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.userMessage),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      client?.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l?.deleteProfile ?? 'Delete profile'),
        content: Text(widget.profile.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l?.delete ?? 'Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      context.read<ProfileProvider>().removeProfile(widget.profile.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.watch<ProfileProvider>();
    final selected = p.selectedProfileId == widget.profile.id;
    final pinned = widget.profile.allowSelfSignedCert;
    final validFingerprint = isValidCertificateFingerprint(
      widget.profile.trustedCertificateSha256,
    );

    return Card(
      child: Column(
        children: [
          ListTile(
            selected: selected,
            isThreeLine: pinned,
            leading: Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(widget.profile.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.profile.baseUrl),
                if (pinned)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          validFingerprint
                              ? Icons.verified_user_outlined
                              : Icons.warning_amber_rounded,
                          size: 16,
                          color: validFingerprint
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            validFingerprint
                                ? 'Firewall certificate pinned'
                                : 'Certificate trust requires review',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            onTap: () => context
                .read<ProfileProvider>()
                .selectProfile(widget.profile.id),
            trailing: IconButton(
              tooltip: 'Edit profile',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileFormScreen(profile: widget.profile),
                ),
              ),
            ),
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check),
                label: Text(l?.testConnection ?? 'Test connection'),
              ),
              TextButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: Text(l?.delete ?? 'Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
