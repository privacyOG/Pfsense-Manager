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
import '../services/pfsense_service.dart';
import 'profile_form_screen.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.watch<ProfileProvider>();
    context.watch<PfSenseSessionProvider>();
    return Scaffold(
        appBar: AppBar(title: Text(l?.profiles ?? 'Profiles'), actions: [
          IconButton(
              tooltip: l?.importJson ?? 'Import JSON',
              onPressed: () => _import(context),
              icon: const Icon(Icons.upload_file_outlined)),
          IconButton(
              tooltip: l?.exportJson ?? 'Export JSON',
              onPressed: p.profiles.isEmpty ? null : () => _export(context),
              icon: const Icon(Icons.ios_share_outlined))
        ]),
        body: RefreshIndicator(
            onRefresh: () async {
              await p.loadProfiles();
            },
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (p.isLoading)
                const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()))
              else if (p.profiles.isEmpty)
                Card(
                    child: ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: Text(l?.emptyState ?? 'Nothing to show yet.'),
                        subtitle: Text(l?.addProfile ?? 'Add profile')))
              else
                for (final profile in p.profiles) _ProfileTile(profile: profile)
            ])),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileFormScreen())),
            icon: const Icon(Icons.add),
            label: Text(l?.addProfile ?? 'Add profile')));
  }

  Future<void> _export(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final json = context.read<ProfileProvider>().exportProfiles();
    await Clipboard.setData(ClipboardData(text: json));
    await Share.share(json, subject: l?.exportJson ?? 'Export JSON');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l?.copiedToClipboard ?? 'Copied to clipboard')));
    }
  }

  Future<void> _import(BuildContext context) async {
    final l = AppLocalizations.of(context);
    try {
      final r = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json'], withData: true);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('${l?.importedProfiles ?? 'Profiles imported'}: $count')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
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
    final l = AppLocalizations.of(context);
    setState(() => _testing = true);
    PfSenseService? svc;
    try {
      final resolved = await ProfileProvider.resolveForConnection(widget.profile);
      if (!mounted) return;
      svc = PfSenseService(PfSenseApiClient(resolved));
      final ok = await svc.healthCheck();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ok
                ? (l?.connectionSuccessful ?? 'Connection successful')
                : (l?.connectionFailed ?? 'Connection failed'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      svc?.dispose();
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
                      child: Text(l?.cancel ?? 'Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(l?.delete ?? 'Delete'))
                ]));
    if (ok == true && mounted) {
      context.read<ProfileProvider>().removeProfile(widget.profile.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.watch<ProfileProvider>();
    final selected = p.selectedProfileId == widget.profile.id;
    return Card(
        child: Column(children: [
      ListTile(
          selected: selected,
          leading: Icon(selected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked),
          title: Text(widget.profile.name),
          subtitle: Text(widget.profile.baseUrl),
          onTap: () =>
              context.read<ProfileProvider>().selectProfile(widget.profile.id),
          trailing: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      ProfileFormScreen(profile: widget.profile))))),
      SwitchListTile(
          value: widget.profile.allowSelfSignedCert,
          onChanged: (v) => context
              .read<ProfileProvider>()
              .updateProfile(widget.profile.copyWith(allowSelfSignedCert: v)),
          title: Text(l?.allowSelfSigned ?? 'Allow self-signed certificate')),
      OverflowBar(alignment: MainAxisAlignment.end, children: [
        TextButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            label: Text(l?.testConnection ?? 'Test connection')),
        TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            label: Text(l?.delete ?? 'Delete'))
      ])
    ]));
  }
}
