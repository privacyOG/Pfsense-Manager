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
  final _connectionKey = GlobalKey<FormState>();
  final _authenticationKey = GlobalKey<FormState>();
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
  int _currentStep = 0;
  bool _obscure = true;
  bool _saving = false;
  bool _inspectingCertificate = false;

  bool get _editing => widget.profile != null;
  bool get _usesApiKey => _authMode == PfSenseAuthMode.apiKey;
  bool get _modeChanged =>
      _editing && widget.profile!.authMode != _authMode;
  bool get _secretOptional => _editing && !_modeChanged;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_saving) return;
    switch (_currentStep) {
      case 0:
        if (!(_connectionKey.currentState?.validate() ?? false)) return;
        if (_readEndpoint() == null) return;
        if (!_certificateTrustIsReady(showMessage: true)) return;
        setState(() => _currentStep = 1);
      case 1:
        if (!(_authenticationKey.currentState?.validate() ?? false)) return;
        setState(() => _currentStep = 2);
      case 2:
        await _save();
    }
  }

  void _back() {
    if (_saving || _currentStep == 0) return;
    setState(() => _currentStep--);
  }

  Future<void> _save() async {
    final connectionValid =
        _connectionKey.currentState?.validate() ?? false;
    final authenticationValid =
        _authenticationKey.currentState?.validate() ?? false;
    if (_saving || !connectionValid || !authenticationValid) return;

    final endpoint = _readEndpoint();
    if (endpoint == null || !_certificateTrustIsReady(showMessage: true)) {
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

  bool _certificateTrustIsReady({required bool showMessage}) {
    final valid = !_pinCertificate ||
        isValidCertificateFingerprint(_trustedCertificateSha256);
    if (!valid && showMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Inspect and trust the firewall certificate before continuing.',
          ),
        ),
      );
    }
    return valid;
  }

  Future<void> _inspectAndTrustCertificate() async {
    if (_inspectingCertificate) return;
    if (!(_connectionKey.currentState?.validate() ?? false)) return;
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing
              ? (l?.editProfile ?? 'Edit firewall')
              : (l?.addProfile ?? 'Add firewall'),
        ),
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _continue,
        onStepCancel: _back,
        onStepTapped: (step) {
          if (step <= _currentStep) setState(() => _currentStep = step);
        },
        controlsBuilder: (context, details) {
          final last = _currentStep == 2;
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              children: [
                FilledButton.icon(
                  key: const Key('profile-step-continue'),
                  onPressed: _saving ? null : details.onStepContinue,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(last ? Icons.save_outlined : Icons.arrow_forward),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : last
                            ? (l?.save ?? 'Save firewall')
                            : 'Continue',
                  ),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: _saving ? null : details.onStepCancel,
                    child: const Text('Back'),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('Firewall'),
            subtitle: const Text('Name, address and certificate trust'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0
                ? StepState.complete
                : StepState.indexed,
            content: Form(
              key: _connectionKey,
              child: Column(
                children: [
                  _field(
                    _name,
                    l?.name ?? 'Firewall name',
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
                    l?.port ?? 'HTTPS port',
                    Icons.numbers,
                    number: true,
                    validator: _portVal,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _https,
                    onChanged: null,
                    title: Text(l?.https ?? 'HTTPS required'),
                    subtitle: const Text(
                      'Unencrypted firewall management connections are blocked.',
                    ),
                    secondary:
                        const Icon(Icons.enhanced_encryption_outlined),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _pinCertificate,
                    onChanged: (value) {
                      setState(() {
                        _pinCertificate = value;
                        if (!value) _trustedCertificateSha256 = '';
                      });
                    },
                    title: const Text('Trust a private certificate'),
                    subtitle: const Text(
                      'Enable this for a self-signed or private-CA certificate.',
                    ),
                    secondary: const Icon(Icons.verified_user_outlined),
                  ),
                  if (_pinCertificate) _certificateTrustCard(context),
                ],
              ),
            ),
          ),
          Step(
            title: const Text('Authentication'),
            subtitle: Text(
              _usesApiKey
                  ? 'API key — recommended'
                  : 'Username and password — JWT',
            ),
            isActive: _currentStep >= 1,
            state: _currentStep > 1
                ? StepState.complete
                : StepState.indexed,
            content: Form(
              key: _authenticationKey,
              child: Column(
                children: [
                  DropdownButtonFormField<PfSenseAuthMode>(
                    key: const Key('profile-auth-mode'),
                    initialValue: _authMode,
                    decoration: const InputDecoration(
                      labelText: 'Authentication method',
                      prefixIcon:
                          Icon(Icons.admin_panel_settings_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PfSenseAuthMode.apiKey,
                        child: Text('API key — recommended'),
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
                  if (!_usesApiKey)
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
                        labelText: _secretOptional
                            ? 'Replace ${_usesApiKey ? 'API key' : 'password'} (optional)'
                            : (_usesApiKey ? 'API key' : 'Password'),
                        helperText: _secretOptional
                            ? 'Leave blank to keep the saved ${_usesApiKey ? 'API key' : 'password'}.'
                            : _usesApiKey
                                ? 'Use a dedicated least-privilege pfREST API key.'
                                : 'Used only to obtain a JWT token.',
                        prefixIcon: Icon(
                          _usesApiKey
                              ? Icons.key_outlined
                              : Icons.password_outlined,
                        ),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: _secretOptional ? null : _req,
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Least-privilege access'),
                      subtitle: const Text(
                        'Start with read-only permissions, then enable only the management endpoints this device needs.',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Step(
            title: const Text('Review'),
            subtitle: const Text('Confirm the connection before saving'),
            isActive: _currentStep >= 2,
            content: _reviewCard(context),
          ),
        ],
      ),
    );
  }

  Widget _certificateTrustCard(BuildContext context) {
    final valid = isValidCertificateFingerprint(_trustedCertificateSha256);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  valid ? Icons.verified_outlined : Icons.warning_amber_rounded,
                  color: valid
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    valid
                        ? 'Firewall certificate trusted'
                        : 'Certificate trust required',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (valid) ...[
              const SizedBox(height: 10),
              SelectableText(
                formatCertificateFingerprint(_trustedCertificateSha256),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  _inspectingCertificate ? null : _inspectAndTrustCertificate,
              icon: _inspectingCertificate
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.policy_outlined),
              label: Text(
                valid
                    ? 'Inspect certificate again'
                    : 'Inspect and trust certificate',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard(BuildContext context) {
    final host = _host.text.trim();
    final port = _port.text.trim();
    final endpoint = host.isEmpty ? 'Not configured' : 'https://$host:$port';
    final certificate = _pinCertificate
        ? isValidCertificateFingerprint(_trustedCertificateSha256)
            ? 'Pinned SHA-256 fingerprint'
            : 'Certificate trust incomplete'
        : 'Android system trust';
    final authentication = _usesApiKey ? 'API key' : 'JWT password';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _name.text.trim().isEmpty ? 'New firewall' : _name.text.trim(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _reviewRow(Icons.router_outlined, 'Endpoint', endpoint),
            _reviewRow(Icons.security_outlined, 'Certificate', certificate),
            _reviewRow(
              Icons.admin_panel_settings_outlined,
              'Authentication',
              authentication,
            ),
            if (!_usesApiKey)
              _reviewRow(
                Icons.person_outline,
                'User',
                _user.text.trim().isEmpty ? 'Not configured' : _user.text.trim(),
              ),
            const SizedBox(height: 8),
            Text(
              'The connection can be tested from the Profiles screen after saving.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
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
