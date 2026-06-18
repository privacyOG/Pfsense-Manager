import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePalette { emerald, pfsenseNavy, dynamic }

enum AmoledAccent {
  matrixGreen,
  midnightNeon,
  draculaPurple,
  infernoRed,
}

extension AmoledAccentProps on AmoledAccent {
  String get label {
    switch (this) {
      case AmoledAccent.matrixGreen:
        return 'Matrix Green';
      case AmoledAccent.midnightNeon:
        return 'Midnight Neon';
      case AmoledAccent.draculaPurple:
        return 'Dracula Purple';
      case AmoledAccent.infernoRed:
        return 'Inferno Red';
    }
  }

  Color get color {
    switch (this) {
      case AmoledAccent.matrixGreen:
        return const Color(0xFF00E676);
      case AmoledAccent.midnightNeon:
        return const Color(0xFF00E5FF);
      case AmoledAccent.draculaPurple:
        return const Color(0xFFBB86FC);
      case AmoledAccent.infernoRed:
        return const Color(0xFFFF1744);
    }
  }

  IconData get icon {
    switch (this) {
      case AmoledAccent.matrixGreen:
        return Icons.terminal;
      case AmoledAccent.midnightNeon:
        return Icons.nights_stay_outlined;
      case AmoledAccent.draculaPurple:
        return Icons.auto_awesome;
      case AmoledAccent.infernoRed:
        return Icons.local_fire_department_outlined;
    }
  }
}

/// Theme provider for dark/light mode switching and AMOLED accent selection.
class ThemeProvider extends ChangeNotifier {
  static const _darkModeKey = 'darkMode';
  static const _paletteKey = 'themePalette';
  static const _amoledKey = 'amoledEnabled';
  static const _amoledAccentKey = 'amoledAccent';

  bool _isDarkMode = true;
  AppThemePalette _palette = AppThemePalette.pfsenseNavy;
  bool _isAmoled = false;
  AmoledAccent _amoledAccent = AmoledAccent.matrixGreen;

  bool get isDarkMode => _isDarkMode;
  AppThemePalette get palette => _palette;
  bool get isAmoled => _isAmoled;
  AmoledAccent get amoledAccent => _amoledAccent;

  ThemeData get themeData {
    return _isAmoled
        ? _buildAmoledTheme(_amoledAccent)
        : _buildTheme(_isDarkMode, _palette);
  }

  /// Builds the active theme. When AMOLED is on it always returns the pure-black
  /// AMOLED theme regardless of dynamic colour availability.
  ThemeData buildThemeData({
    ColorScheme? lightDynamic,
    ColorScheme? darkDynamic,
  }) {
    if (_isAmoled) return _buildAmoledTheme(_amoledAccent);
    if (_palette == AppThemePalette.dynamic) {
      final scheme = _isDarkMode ? darkDynamic : lightDynamic;
      if (scheme != null) return _buildThemeFromScheme(_isDarkMode, scheme);
    }
    return _buildTheme(_isDarkMode, _palette);
  }

  static ThemeData _buildThemeFromScheme(bool dark, ColorScheme scheme) {
    final nav = dark ? const Color(0xFF091B2E) : Colors.white;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: scheme.surface,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        color: scheme.surfaceContainerLow,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: nav,
        indicatorColor: scheme.primary.withValues(alpha: dark ? .32 : .18),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(backgroundColor: nav),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// Generates a true AMOLED theme with a pure black (#000000) scaffold,
  /// app bar, canvas and navigation, extremely dark gray (#0A0A0A) for card
  /// and dialog surfaces, and the chosen neon accent mapped to the primary slot.
  static ThemeData _buildAmoledTheme(AmoledAccent accent) {
    const black = Color(0xFF000000);
    const darkSurface = Color(0xFF0A0A0A);
    final primary = accent.color;

    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: Colors.black,
      primaryContainer: primary.withValues(alpha: 0.15),
      onPrimaryContainer: primary,
      secondary: primary,
      onSecondary: Colors.black,
      secondaryContainer: primary.withValues(alpha: 0.12),
      onSecondaryContainer: primary,
      tertiary: primary.withValues(alpha: 0.85),
      onTertiary: Colors.black,
      tertiaryContainer: primary.withValues(alpha: 0.10),
      onTertiaryContainer: primary,
      error: const Color(0xFFCF6679),
      onError: Colors.black,
      errorContainer: const Color(0xFF370B1E),
      onErrorContainer: const Color(0xFFFFB4AB),
      surface: darkSurface,
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFFAAAAAA),
      outline: const Color(0xFF333333),
      outlineVariant: const Color(0xFF1E1E1E),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Colors.white,
      onInverseSurface: Colors.black,
      inversePrimary: primary,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: black,
      canvasColor: black,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: black,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: black,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: primary.withValues(alpha: 0.22),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: black,
        indicatorColor: primary.withValues(alpha: 0.22),
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: darkSurface),
      dialogTheme: const DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF111111),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1E1E1E),
        space: 1,
      ),
    );
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_darkModeKey) ?? true;
    _palette = AppThemePalette.values.firstWhere(
      (item) => item.name == prefs.getString(_paletteKey),
      orElse: () => AppThemePalette.pfsenseNavy,
    );
    _isAmoled = prefs.getBool(_amoledKey) ?? false;
    final savedAccentIndex = prefs.getInt(_amoledAccentKey);
    if (savedAccentIndex != null &&
        savedAccentIndex >= 0 &&
        savedAccentIndex < AmoledAccent.values.length) {
      _amoledAccent = AmoledAccent.values[savedAccentIndex];
    }
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

  Future<void> setAmoledMode(bool enabled) async {
    _isAmoled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_amoledKey, enabled);
  }

  Future<void> setAmoledAccent(AmoledAccent accent) async {
    _amoledAccent = accent;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_amoledAccentKey, accent.index);
  }
}
