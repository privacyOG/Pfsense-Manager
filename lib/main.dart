import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'providers/app_settings_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/session_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/startup_screen.dart';
import 'services/alert_service.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/release_notice.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AlertService.initialize();
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
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          return Consumer2<ThemeProvider, AppSettingsProvider>(
            builder: (context, themeProvider, settings, _) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                title: 'pfSense Manager',
                theme: themeProvider.buildThemeData(
                  lightDynamic: lightDynamic,
                  darkDynamic: darkDynamic,
                ),
                locale: settings.locale,
                supportedLocales: AppStrings.supportedLocales,
                localizationsDelegates: const [
                  AppStrings.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (context, child) => AppLockGate(
                  child: child ?? const SizedBox.shrink(),
                ),
                home: const ReleaseNotice(child: StartupScreen()),
              );
            },
          );
        },
      ),
    );
  }
}
