import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../services/certificate_trust.dart';
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
  late PfSenseAuthMode _authMode =
      widget.profile?.authMode ?? PfSenseAuthMode.apiKey;
  late bool _https = true;
  late bool _pinCertificate = widget.profile?.allowSelfSignedCert ?? false;
  late String _trustedCertificateSha256 = normalizeCertificateFingerprint(
    widget.profile?.trustedCertificateSha256 ?? '',
  );
  bool _obscure = true;
  bool _saving = false;
  bool _inspectingCertificate = false;

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
    if (_pinCertificate &&
        !isValidCertificateFingerprint(_trustedCertificateSha256)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Inspect and trust the firewall certificate before saving this profile.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final secret = _secret.text;
    final profile = PfSenseProfile(
      id: widget.profile?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      host: endpoint.host,
      port: endpoint.port,
      useHttps: endpoint.useHttps,
      allowSelfSignedCert: _pinCertificate,
      trustedCertificateSha256:
          _pinCertificate ? _trustedCertificateSha256 : '',
      username: _authMode == PfSenseAuthMode.jwtPassword
          ? _user.text.trim()
          : '',
      authMode: _authMode,
      apiKey: _authMode == PfSenseAuthMode.apiKey ? secret : '',
      password: _authMode == PfSenseAuthMode.jwtPassword ? secret : '',
    );

    try {
      final provider = context.read<ProfileProvider>();
      if (widget.profile == null) {
        await provider.addProfile(profile);
      } else {
        await provider.updateProfile(profile);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _inspectAndTrustCertificate() async {
    if (_inspectingCertificate) return;
    final endpoint = _readEndpoint();
    if (endpoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid firewall address and port.')),
      );
      return;
    }

    setState(() => _inspectingCertificate = true);
    try {
      final inspection = await inspectCertificate(
        host: endpoint.host,
        port: endpoint.port,
      );
      if (!mounted) return;
      final trust = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Trust firewall certificate?'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Verify this fingerprint against the certificate shown by pfSense before trusting it.',
                ),
                const SizedBox(height: 16),
                Text(
                  'SHA-256 fingerprint',
                  style: Theme.of(dialogContext).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  formatCertificateFingerprint(inspection.sha256Fingerprint),
                ),
                const SizedBox(height: 16),
                Text('Subject: ${inspection.subject}'),
                const SizedBox(height: 6),
                Text('Issuer: ${inspection.issuer}'),
                const SizedBox(height: 6),
                Text('Valid from: ${inspection.startValidity.toLocal()}'),
                const SizedBox(height: 6),
                Text('Valid until: ${inspection.endValidity.toLocal()}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Trust certificate'),
            ),
          ],
        ),
      );
      if (trust == true && mounted) {
        setState(() {
          _pinCertificate = true;
          _trustedCertificateSha256 = normalizeCertificateFingerprint(
            inspection.sha256Fingerprint,
          );
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _inspectingCertificate = false);
    }
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
    final usesApiKey = _authMode == PfSenseAuthMode.apiKey;
    final modeChanged = editing && widget.profile!.authMode != _authMode;
    final secretOptional = editing && !modeChanged;
    final fingerprintValid =
        isValidCertificateFingerprint(_trustedCertificateSha256);

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
            SwitchListTile(
              value: _pinCertificate,
              onChanged: (value) {
                setState(() {
                  _pinCertificate = value;
                  if (!value) _trustedCertificateSha256 = '';
                });
              },
              title: const Text('Pin firewall certificate'),
              subtitle: const Text(
                'Use for a self-signed or private-CA certificate. Connections are accepted only when the SHA-256 fingerprint matches.',
              ),
              secondary: const Icon(Icons.verified_user_outlined),
            ),
            if (_pinCertificate)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fingerprintValid
                            ? 'Trusted SHA-256 fingerprint'
                            : 'No trusted fingerprint saved',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (fingerprintValid) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          formatCertificateFingerprint(
                            _trustedCertificateSha256,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _inspectingCertificate
                            ? null
                            : _inspectAndTrustCertificate,
                        icon: _inspectingCertificate
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.policy_outlined),
                        label: Text(
                          fingerprintValid
                              ? 'Inspect certificate again'
                              : 'Inspect and trust certificate',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PfSenseAuthMode>(
              key: const Key('profile-auth-mode'),
              initialValue: _authMode,
              decoration: const InputDecoration(
                labelText: 'Authentication',
                prefixIcon: Icon(Icons.admin_panel_settings_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: PfSenseAuthMode.apiKey,
                  child: Text('API key'),
                ),
                DropdownMenuItem(
                  value: PfSenseAuthMode.jwtPassword,
                  child: Text('Username and password (JWT)'),
                ),
              ],
              onChanged: (value) {
                if (value == null || value == _authMode) return;
                setState(() {
                  _authMode = value;
                  _secret.clear();
                  _obscure = true;
                });
              },
            ),
            const SizedBox(height: 12),
            if (!usesApiKey)
              _field(
                _user,
                l?.username ?? 'Username',
                Icons.person_outline,
                validator: _req,
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                key: const Key('profile-auth-secret'),
                controller: _secret,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: secretOptional
                      ? 'Replace ${usesApiKey ? 'API key' : 'password'} (optional)'
                      : (usesApiKey ? 'API key' : 'Password'),
                  helperText: secretOptional
                      ? 'Leave blank to keep the saved ${usesApiKey ? 'API key' : 'password'}.'
                      : usesApiKey
                          ? 'Sent only in the X-API-Key header.'
                          : 'Used only to obtain a JWT token.',
                  prefixIcon: Icon(
                    usesApiKey ? Icons.key_outlined : Icons.password_outlined,
                  ),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: secretOptional ? null : _req,
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
