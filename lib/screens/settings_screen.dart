import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_settings_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _pinController = TextEditingController();
  final _auth = LocalAuthentication();
  int _autoLockMinutes = 5;
  String _language = 'en';
  PackageInfo? _packageInfo;
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
    _auth.canCheckBiometrics.then((value) {
      if (mounted) setState(() => _canUseBiometrics = value);
    }).catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<AppSettingsProvider>();
      setState(() {
        _autoLockMinutes = settings.lockTimeoutMinutes;
        _language = settings.locale.languageCode;
      });
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _savePin(AppSettingsProvider settings) async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use at least 4 digits for the PIN.')),
      );
      return;
    }
    await settings.setPin(pin);
    _pinController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('PIN updated.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = context.watch<ThemeProvider>();
    final settings = context.watch<AppSettingsProvider>();
    final info = _packageInfo;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _SettingsHero(
          version: info == null ? 'Loading...' : '${info.version}+${info.buildNumber}',
        ),
        const SizedBox(height: 14),
        const _SectionTitle(icon: Icons.palette_outlined, title: 'Appearance'),
        Card(
          child: SwitchListTile(
            value: theme.isDarkMode,
            onChanged: context.read<ThemeProvider>().setDarkMode,
            title: Text(l10n?.darkMode ?? 'Dark mode'),
            subtitle: const Text('Theme Control'),
            secondary: Icon(
              theme.isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.format_paint_outlined),
            title: const Text('Theme colour'),
            subtitle: const Text('Choose the app accent and pfSense-style shell'),
            trailing: DropdownButton<AppThemePalette>(
              value: theme.palette,
              items: const [
                DropdownMenuItem(
                  value: AppThemePalette.pfsenseNavy,
                  child: Text('pfSense navy'),
                ),
                DropdownMenuItem(
                  value: AppThemePalette.emerald,
                  child: Text('Emerald'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  context.read<ThemeProvider>().setPalette(value);
                }
              },
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.language_outlined),
            title: Text(l10n?.language ?? 'Language'),
            trailing: DropdownButton<String>(
              value: _language,
              items: const [
                DropdownMenuItem(value: 'en', child: Text('EN')),
                DropdownMenuItem(value: 'ar', child: Text('AR')),
                DropdownMenuItem(value: 'es', child: Text('ES')),
                DropdownMenuItem(value: 'fr', child: Text('FR')),
                DropdownMenuItem(value: 'de', child: Text('DE')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _language = value);
                settings.setLocale(Locale(value));
              },
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle(icon: Icons.lock_outline, title: 'Security'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: Text(l10n?.autoLock ?? 'Auto-lock'),
            subtitle: Text('Lock after $_autoLockMinutes min idle'),
            trailing: DropdownButton<int>(
              value: _autoLockMinutes,
              items: [
                for (final value in [1, 5, 10, 15, 30, 45, 60])
                  DropdownMenuItem(value: value, child: Text('$value min')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _autoLockMinutes = value);
                settings.setLockTimeout(value);
              },
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardLabel(icon: Icons.pin_outlined, title: 'PIN Lock Configuration'),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'New PIN',
                    prefixIcon: Icon(Icons.password),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _savePin(settings),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Set PIN'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: settings.hasPin ? settings.clearPin : null,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Clear PIN'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Card(
          child: SwitchListTile(
            value: settings.pinEnabled,
            onChanged: settings.hasPin ? settings.setPinEnabled : null,
            title: const Text('Require PIN on lock'),
            subtitle: Text(settings.hasPin ? 'PIN is configured' : 'Set a PIN first'),
            secondary: const Icon(Icons.pin),
          ),
        ),
        Card(
          child: SwitchListTile(
            value: settings.biometricEnabled,
            onChanged: _canUseBiometrics && settings.pinEnabled
                ? settings.setBiometricEnabled
                : null,
            title: const Text('Biometric Setup'),
            subtitle: Text(_canUseBiometrics
                ? 'Enable fingerprint or device unlock on the lock screen'
                : 'No enrolled biometric method reported by Android'),
            secondary: const Icon(Icons.fingerprint),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle(icon: Icons.info_outline, title: 'About'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.security),
            title: Text(l10n?.about ?? 'About pfSense Manager App'),
            subtitle: Text(
              info == null
                  ? 'Loading...'
                  : '${info.appName} ${info.version}+${info.buildNumber}\nUpdated on 2026-06-12\nReleased on 2026-06-12\nRequired OS: Android 7.0 or newer',
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF00C2A8).withValues(alpha: .16),
            ),
            child: const Icon(Icons.tune, color: Color(0xFF00C2A8)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: Theme.of(context).textTheme.titleLarge),
                Text('Version $version', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
