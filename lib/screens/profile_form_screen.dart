import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_localizations.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';

class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, this.profile});
  final PfSenseProfile? profile;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _EndpointParts {
  const _EndpointParts({
    required this.host,
    required this.port,
    required this.useHttps,
  });

  final String host;
  final int port;
  final bool useHttps;
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
  late final _secret = TextEditingController(
    text: widget.profile?.apiKey ?? '',
  );
  late bool _https = true;
  late bool _self = widget.profile?.allowSelfSignedCert ?? false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _save() {
    if (!_key.currentState!.validate()) return;

    final endpoint = _readEndpoint();
    if (endpoint == null) return;

    final p = PfSenseProfile(
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
    widget.profile == null ? provider.addProfile(p) : provider.updateProfile(p);
    Navigator.pop(context, true);
  }

  _EndpointParts? _readEndpoint() {
    final hostText = _host.text.trim();
    final portText = _port.text.trim();
    var useHttps = _https;
    var host = hostText;
    var port = int.tryParse(portText) ?? 443;

    if (hostText.contains('://')) {
      final uri = Uri.tryParse(hostText);
      if (uri == null || uri.host.isEmpty) return null;
      host = uri.host;
      useHttps = uri.scheme.toLowerCase() == 'https';
      if (uri.hasPort) port = uri.port;
    } else if (hostText.contains(':') && !hostText.startsWith('[')) {
      final lastColon = hostText.lastIndexOf(':');
      final maybePort = int.tryParse(hostText.substring(lastColon + 1));
      if (maybePort != null) {
        host = hostText.substring(0, lastColon);
        port = maybePort;
      }
    }

    _host.text = host;
    _port.text = port.toString();
    _https = useHttps;
    return _EndpointParts(host: host, port: port, useHttps: useHttps);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    context.watch<ProfileProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.profile == null
              ? (l?.addProfile ?? 'Add profile')
              : (l?.editProfile ?? 'Edit profile'),
        ),
      ),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_name, l?.name ?? 'Name', Icons.label_outline,
                validator: _req),
            _field(
              _host,
              l?.host ?? 'Host, IP, or URL',
              Icons.router_outlined,
              validator: _hostVal,
            ),
            _field(_port, l?.port ?? 'Port', Icons.numbers,
                number: true, validator: _portVal),
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
            _field(_user, l?.username ?? 'Username', Icons.person_outline,
                validator: _req),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                controller: _secret,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: l?.apiKeyOrPassword ?? 'API key / password',
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
                validator: _req,
              ),
            ),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(l?.save ?? 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    bool number = false,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        validator: validator,
      ),
    );
  }

  String? _req(String? v) => v == null || v.trim().isEmpty
      ? (AppLocalizations.of(context)?.requiredField ?? 'Required')
      : null;

  String? _hostVal(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty)
      return AppLocalizations.of(context)?.requiredField ?? 'Required';
    if (t.contains('://')) {
      final uri = Uri.tryParse(t);
      if (uri == null || uri.host.isEmpty) {
        return AppLocalizations.of(context)?.host ?? 'Host, IP, or URL';
      }
      if (uri.scheme.toLowerCase() != 'https') {
        return 'HTTPS is required for API security';
      }
      return null;
    }
    return t.contains('/')
        ? (AppLocalizations.of(context)?.host ?? 'Host, IP, or URL')
        : null;
  }

  String? _portVal(String? v) {
    final p = int.tryParse(v?.trim() ?? '');
    return p == null || p < 1 || p > 65535
        ? (AppLocalizations.of(context)?.invalidPort ?? 'Invalid port')
        : null;
  }
}
