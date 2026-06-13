import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePalette { emerald, pfsenseNavy }

/// Theme provider for dark/light mode switching.
class ThemeProvider extends ChangeNotifier {
  static const _darkModeKey = 'darkMode';
  static const _paletteKey = 'themePalette';
  bool _isDarkMode = true; // Default to dark mode
  AppThemePalette _palette = AppThemePalette.pfsenseNavy;

  bool get isDarkMode => _isDarkMode;
  AppThemePalette get palette => _palette;

  ThemeData get themeData {
    return _buildTheme(_isDarkMode, _palette);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_darkModeKey) ?? true;
    _palette = AppThemePalette.values.firstWhere(
      (item) => item.name == prefs.getString(_paletteKey),
      orElse: () => AppThemePalette.pfsenseNavy,
    );
    notifyListeners();
  }

  static ThemeData _buildTheme(bool dark, AppThemePalette palette) {
    final navy = palette == AppThemePalette.pfsenseNavy;
    final seed = navy
        ? const Color(0xFF1B75BB)
        : dark
            ? const Color(0xFF00A878)
            : const Color(0xFF007D68);
    final scaffold = dark
        ? (navy ? const Color(0xFF081526) : const Color(0xFF0D1217))
        : (navy ? const Color(0xFFF2F6FA) : const Color(0xFFF4F7F8));
    final surface = dark
        ? (navy ? const Color(0xFF0E2138) : const Color(0xFF151E26))
        : Colors.white;
    final appBar = dark
        ? (navy ? const Color(0xFF09213A) : const Color(0xFF131B22))
        : (navy ? const Color(0xFFFAFCFF) : Colors.white);
    final nav = dark
        ? (navy ? const Color(0xFF091B2E) : const Color(0xFF111920))
        : Colors.white;

    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorSchemeSeed: seed,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: appBar,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        color: surface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: nav,
        indicatorColor: seed.withValues(alpha: dark ? .32 : .18),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(backgroundColor: nav),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? (navy ? const Color(0xFF132B45) : const Color(0xFF18222B))
            : const Color(0xFFF0F3F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// Material Design 3 Dark Theme
  static final darkTheme = _buildTheme(true, AppThemePalette.emerald);

  /// Material Design 3 Light Theme
  static final lightTheme = _buildTheme(false, AppThemePalette.emerald);

  static final pfsenseNavyDarkTheme = _buildTheme(true, AppThemePalette.pfsenseNavy);
  static final pfsenseNavyLightTheme = _buildTheme(false, AppThemePalette.pfsenseNavy);

  void toggleTheme() {
    setDarkMode(!_isDarkMode);
  }

  Future<void> setDarkMode(bool isDark) async {
    _isDarkMode = isDark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, isDark);
  }

  Future<void> setPalette(AppThemePalette palette) async {
    _palette = palette;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paletteKey, palette.name);
  }
}
