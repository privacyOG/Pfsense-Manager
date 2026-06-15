import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'providers/app_settings_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/session_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/lock_screen.dart';
import 'screens/startup_screen.dart';
import 'widgets/release_notice.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PfSenseManagerApp());
}

class PfSenseManagerApp extends StatelessWidget {
  const PfSenseManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
        ChangeNotifierProvider(create: (_) => AppSettingsProvider()..load()),
        ChangeNotifierProvider(
          create: (_) => ProfileProvider()..loadProfiles(),
        ),
        ChangeNotifierProvider(create: (_) => PfSenseSessionProvider()),
      ],
      child: Consumer2<ThemeProvider, AppSettingsProvider>(
        builder: (context, themeProvider, settings, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'pfSense Manager',
            theme: themeProvider.themeData,
            locale: settings.locale,
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const ReleaseNotice(child: _LockingShell()),
          );
        },
      ),
    );
  }
}

class _LockingShell extends StatefulWidget {
  const _LockingShell();

  @override
  State<_LockingShell> createState() => _LockingShellState();
}

class _LockingShellState extends State<_LockingShell> {
  Timer? _timer;
  bool _locked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _timer?.cancel();
    final minutes = context.read<AppSettingsProvider>().lockTimeoutMinutes;
    _timer = Timer(Duration(minutes: minutes), () {
      if (mounted) setState(() => _locked = true);
    });
  }

  void _onActivity([PointerEvent? _]) {
    if (!_locked) _resetTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onActivity,
      onPointerMove: _onActivity,
      child: _locked
          ? LockScreen(
              onUnlock: () {
                setState(() => _locked = false);
                _resetTimer();
              },
            )
          : const StartupScreen(),
    );
  }
}
