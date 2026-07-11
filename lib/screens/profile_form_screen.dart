import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../utils/pfsense_endpoint.dart';

class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, this.profile});

  final PfSenseProfile? profile;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile?.name ?? '');
  late final _host = TextEditingController(text: widget.profile?.host ?? '');
  late final _port = TextEditingController(
    text: (widget.profile?.port ?? 443).toString(),
  );
  late final _user = TextEditingController(
    text: widget.profile?.username ?? '',
  );
  final _secret = TextEditingController();
  late bool _https = true;
  late bool _self = widget.profile?.allowSelfSignedCert ?? false;
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;

    final endpoint = _readEndpoint();
    if (endpoint == null) return;

    setState(() => _saving = true);
    final profile = PfSenseProfile(
      id: widget.profile?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      host: endpoint.host,
      port: endpoint.port,
      useHttps: endpoint.useHttps,
      allowSelfSignedCert: _self,
      username: _user.text.trim(),
      apiKey: _secret.text,
    );

    final provider = context.read<ProfileProvider>();
    if (widget.profile == null) {
      await provider.addProfile(profile);
    } else {
      await provider.updateProfile(profile);
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  PfSenseEndpoint? _readEndpoint() {
    final fallbackPort = int.tryParse(_port.text.trim());
    if (fallbackPort == null) return null;

    try {
      final endpoint = parsePfSenseEndpoint(
        _host.text,
        fallbackPort: fallbackPort,
        fallbackUseHttps: _https,
        requireHttps: true,
      );
      _host.text = endpoint.host;
      _port.text = endpoint.port.toString();
      _https = endpoint.useHttps;
      return endpoint;
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    context.watch<ProfileProvider>();
    final editing = widget.profile != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          editing
              ? (l?.editProfile ?? 'Edit profile')
              : (l?.addProfile ?? 'Add profile'),
        ),
      ),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(
              _name,
              l?.name ?? 'Name',
              Icons.label_outline,
              validator: _req,
            ),
            _field(
              _host,
              l?.host ?? 'Host, IP, or URL',
              Icons.router_outlined,
              helperText:
                  'Examples: firewall.local, 192.168.1.1, [2001:db8::1]:8443',
              validator: _hostVal,
            ),
            _field(
              _port,
              l?.port ?? 'Port',
              Icons.numbers,
              number: true,
              validator: _portVal,
            ),
            SwitchListTile(
              value: _https,
              onChanged: null,
              title: Text(l?.https ?? 'HTTPS'),
              subtitle: const Text('Required for all API communications'),
              secondary: const Icon(Icons.enhanced_encryption_outlined),
            ),
            CheckboxListTile(
              value: _self,
              onChanged: (v) => setState(() => _self = v ?? false),
              title: Text(
                l?.allowSelfSigned ?? 'Allow self-signed certificate',
              ),
              secondary: const Icon(Icons.verified_user_outlined),
            ),
            _field(
              _user,
              l?.username ?? 'Username',
              Icons.person_outline,
              validator: _req,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: _secret,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: editing
                      ? 'Replace API key (optional)'
                      : (l?.apiKeyOrPassword ?? 'API key'),
                  helperText:
                      editing ? 'Leave blank to keep the saved API key.' : null,
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: editing ? null : _req,
              ),
            ),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : (l?.save ?? 'Save')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool number = false,
    String? helperText,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          prefixIcon: Icon(icon),
        ),
        validator: validator,
      ),
    );
  }

  String? _req(String? value) => value == null || value.trim().isEmpty
      ? (AppLocalizations.of(context)?.requiredField ?? 'Required')
      : null;

  String? _hostVal(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return AppLocalizations.of(context)?.requiredField ?? 'Required';
    }

    final port = int.tryParse(_port.text.trim());
    final fallbackPort = port != null && port >= 1 && port <= 65535
        ? port
        : 443;
    try {
      parsePfSenseEndpoint(
        text,
        fallbackPort: fallbackPort,
        fallbackUseHttps: _https,
        requireHttps: true,
      );
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _portVal(String? value) {
    final port = int.tryParse(value?.trim() ?? '');
    return port == null || port < 1 || port > 65535
        ? (AppLocalizations.of(context)?.invalidPort ?? 'Invalid port')
        : null;
  }
}
