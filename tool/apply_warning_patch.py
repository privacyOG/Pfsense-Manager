from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, found {count}')
    return text.replace(old, new, 1)


dashboard_path = Path('lib/screens/dashboard_screen.dart')
dashboard = dashboard_path.read_text()
dashboard = replace_once(
    dashboard,
    "import '../providers/session_provider.dart';\nimport '../widgets/thermal_sensors_panel.dart';",
    "import '../providers/session_provider.dart';\nimport '../widgets/dashboard_alert_strip.dart';\nimport '../widgets/thermal_sensors_panel.dart';",
    'dashboard import',
)
dashboard = replace_once(
    dashboard,
    "            _DashboardBody(\n              data: data,\n              live: _live,",
    "            _DashboardBody(\n              data: data,\n              profileId: session.selectedProfile?.id,\n              live: _live,",
    'dashboard body call',
)
dashboard = replace_once(
    dashboard,
    "  const _DashboardBody({\n    required this.data,\n    required this.live,",
    "  const _DashboardBody({\n    required this.data,\n    required this.profileId,\n    required this.live,",
    'dashboard body constructor',
)
dashboard = replace_once(
    dashboard,
    "  final DashboardData data;\n  final bool live;",
    "  final DashboardData data;\n  final String? profileId;\n  final bool live;",
    'dashboard body fields',
)
dashboard = replace_once(
    dashboard,
    "        _AlertStrip(data: data),",
    "        DashboardAlertStrip(data: data, profileId: profileId),",
    'dashboard alert strip',
)
dashboard_path.write_text(dashboard)

settings_path = Path('lib/screens/settings_screen.dart')
settings = settings_path.read_text()
settings = replace_once(
    settings,
    "import '../providers/app_settings_provider.dart';\nimport '../providers/theme_provider.dart';",
    "import '../providers/app_settings_provider.dart';\nimport '../providers/profile_provider.dart';\nimport '../providers/theme_provider.dart';\nimport '../services/dashboard_warning_preferences.dart';",
    'settings imports',
)
settings = replace_once(
    settings,
    "  bool _biometricsAvailable = false;\n",
    "  bool _biometricsAvailable = false;\n  DashboardWarningPreferences? _warningPreferences;\n  String? _warningProfileId;\n  int _warningLoadGeneration = 0;\n  int _ignoredWarningCount = 0;\n  int _snoozedWarningCount = 0;\n  bool _warningPreferencesLoading = false;\n",
    'settings warning fields',
)
warning_methods = r'''
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

'''
settings = replace_once(
    settings,
    "  @override\n  Widget build(BuildContext context) {",
    warning_methods + "  @override\n  Widget build(BuildContext context) {",
    'settings warning methods',
)
settings = replace_once(
    settings,
    "    final settings = context.watch<AppSettingsProvider>();\n    final packageInfo = _packageInfo;",
    "    final settings = context.watch<AppSettingsProvider>();\n    final selectedProfile = context.watch<ProfileProvider>().selectedProfile;\n    _scheduleWarningPreferences(selectedProfile?.id);\n    final packageInfo = _packageInfo;",
    'settings selected profile',
)
warning_section = r'''          const SizedBox(height: 18),
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
          const _Heading(Icons.info_outline, 'About'),'''
settings = replace_once(
    settings,
    "          const SizedBox(height: 18),\n          const _Heading(Icons.info_outline, 'About'),",
    warning_section,
    'settings warning section',
)
settings_path.write_text(settings)

for raw_path in [
    'docs/tmp2.txt',
    'docs/tmp3.txt',
    'docs/tmp4.txt',
    'docs/tmp5.txt',
    'docs/tmp6.txt',
    'docs/.branch-marker-system-info-copy',
    'docs/.branch-marker-system-info-copy2',
    'docs/.branch-marker-system-info-copy3',
    'docs/.branch-marker-system-info-copy4',
    'docs/.branch-marker-system-info-copy5',
    'docs/thermal.md',
    'docs/thermal-sensors-note.md',
    '.github/workflows/apply-dashboard-warning-patch.yml',
    'tool/apply_warning_patch.py',
]:
    path = Path(raw_path)
    if path.exists():
        path.unlink()
