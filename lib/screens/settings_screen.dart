import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_settings_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/theme_provider.dart';
import '../services/dashboard_warning_preferences.dart';
import 'home_shell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _destinationKey = 'home.selectedDestination';
  final _pin = TextEditingController();
  final _auth = LocalAuthentication();
  int _lockMinutes = 5;
  String _language = 'en';
  PackageInfo? _packageInfo;
  bool _biometricsAvailable = false;
  DashboardWarningPreferences? _warningPreferences;
  String? _warningProfileId;
  int _warningLoadGeneration = 0;
  int _ignoredWarningCount = 0;
  int _snoozedWarningCount = 0;
  bool _warningPreferencesLoading = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((value) {
      if (mounted) setState(() => _packageInfo = value);
    });
    _auth.canCheckBiometrics.then((value) {
      if (mounted) setState(() => _biometricsAvailable = value);
    }).catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<AppSettingsProvider>();
      setState(() {
        _lockMinutes = settings.lockTimeoutMinutes;
        _language = settings.locale.languageCode;
      });
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _savePin(AppSettingsProvider settings) async {
    final value = _pin.text.trim();
    if (value.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use at least 4 digits for the PIN.')),
      );
      return;
    }
    await settings.setPin(value);
    _pin.clear();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('PIN updated.')));
    }
  }

  Future<void> _openDestination(int index) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_destinationKey, index);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeShell()),
      (_) => false,
    );
  }


  void _scheduleWarningPreferences(String? profileId) {
    if (_warningProfileId == profileId) return;
    _warningProfileId = profileId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadWarningPreferences(profileId);
    });
  }

  Future<void> _loadWarningPreferences(String? profileId) async {
    final generation = ++_warningLoadGeneration;
    if (profileId == null) {
      if (!mounted) return;
      setState(() {
        _warningPreferences = null;
        _ignoredWarningCount = 0;
        _snoozedWarningCount = 0;
        _warningPreferencesLoading = false;
      });
      return;
    }

    setState(() => _warningPreferencesLoading = true);
    final preferences = await DashboardWarningPreferences.open();
    final ignored = preferences.ignoredForProfile(profileId).length;
    final snoozed = preferences.activeSnoozedCount(profileId);
    if (!mounted || generation != _warningLoadGeneration) return;

    setState(() {
      _warningPreferences = preferences;
      _ignoredWarningCount = ignored;
      _snoozedWarningCount = snoozed;
      _warningPreferencesLoading = false;
    });
  }

  Future<void> _restoreIgnoredWarnings() async {
    final profileId = _warningProfileId;
    if (profileId == null) return;
    final preferences =
        _warningPreferences ?? await DashboardWarningPreferences.open();
    await preferences.restoreIgnored(profileId);
    if (!mounted || profileId != _warningProfileId) return;

    setState(() {
      _warningPreferences = preferences;
      _ignoredWarningCount = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ignored warnings restored.')),
    );
  }

  String _warningSummary(String? profileName) {
    if (profileName == null) {
      return 'Select a firewall profile to manage warning visibility.';
    }
    if (_warningPreferencesLoading) return 'Loading warning preferences...';
    if (_ignoredWarningCount == 0 && _snoozedWarningCount == 0) {
      return 'No warnings are ignored or snoozed for $profileName.';
    }
    return '$_ignoredWarningCount ignored • $_snoozedWarningCount snoozed for $profileName';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = context.watch<ThemeProvider>();
    final settings = context.watch<AppSettingsProvider>();
    final selectedProfile = context.watch<ProfileProvider>().selectedProfile;
    _scheduleWarningPreferences(selectedProfile?.id);
    final packageInfo = _packageInfo;
    final version = packageInfo == null
        ? 'Loading...'
        : '${packageInfo.version}+${packageInfo.buildNumber}';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _hero(context, version),
          const SizedBox(height: 14),
          const _Heading(Icons.palette_outlined, 'Appearance'),
          Card(
            child: SwitchListTile(
              value: theme.isDarkMode,
              onChanged: context.read<ThemeProvider>().setDarkMode,
              title: Text(l10n?.darkMode ?? 'Dark mode'),
              subtitle: const Text('Theme control'),
              secondary: Icon(theme.isDarkMode
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.format_paint_outlined),
              title: const Text('Theme colour'),
              subtitle: const Text('Choose the app accent'),
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
          const _Heading(Icons.lock_outline, 'Security'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_clock_outlined),
              title: Text(l10n?.autoLock ?? 'Auto-lock'),
              subtitle: Text('Lock after $_lockMinutes min idle'),
              trailing: DropdownButton<int>(
                value: _lockMinutes,
                items: [
                  for (final value in [1, 5, 10, 15, 30, 45, 60])
                    DropdownMenuItem(value: value, child: Text('$value min')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _lockMinutes = value);
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
                  const Text('PIN lock configuration'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 8,
                    decoration: const InputDecoration(
                      labelText: 'New PIN',
                      prefixIcon: Icon(Icons.password),
                      counterText: '',
                    ),
                  ),
                  Wrap(
                    spacing: 10,
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
              subtitle: Text(settings.hasPin
                  ? 'PIN is configured'
                  : 'Set a PIN first'),
              secondary: const Icon(Icons.pin),
            ),
          ),
          Card(
            child: SwitchListTile(
              value: settings.biometricEnabled,
              onChanged: _biometricsAvailable && settings.pinEnabled
                  ? settings.setBiometricEnabled
                  : null,
              title: const Text('Biometric setup'),
              subtitle: Text(_biometricsAvailable
                  ? 'Enable fingerprint or device unlock'
                  : 'No biometric method reported by Android'),
              secondary: const Icon(Icons.fingerprint),
            ),
          ),
          const SizedBox(height: 18),
          const _Heading(Icons.warning_amber_outlined, 'Warnings'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Ignored dashboard warnings'),
              subtitle: Text(_warningSummary(selectedProfile?.name)),
              trailing: TextButton(
                onPressed: selectedProfile != null &&
                        !_warningPreferencesLoading &&
                        _ignoredWarningCount > 0
                    ? _restoreIgnoredWarnings
                    : null,
                child: const Text('Restore'),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _Heading(Icons.info_outline, 'About'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.security),
              title: Text(l10n?.about ?? 'About pfSense Manager App'),
              subtitle: Text(packageInfo == null
                  ? 'Loading...'
                  : '${packageInfo.appName} $version\nRequired OS: Android 7.0 or newer'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 4,
        onDestinationSelected: _openDestination,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Firewall',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: 'Network',
          ),
          NavigationDestination(
            icon: Icon(Icons.miscellaneous_services_outlined),
            selectedIcon: Icon(Icons.miscellaneous_services),
            label: 'Services',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more),
            label: 'More',
          ),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context, String version) {
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
          const Icon(Icons.tune, size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: Theme.of(context).textTheme.titleLarge),
                Text('Version $version'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.icon, this.title);
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
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
