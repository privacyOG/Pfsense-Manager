import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsProvider extends ChangeNotifier {
  static const _localeKey = 'localeCode';
  static const _lockTimeoutKey = 'lockTimeoutMinutes';
  static const _pinKey = 'pinCode';
  static const _pinEnabledKey = 'pinEnabled';
  static const _biometricEnabledKey = 'biometricEnabled';

  Locale _locale = const Locale('en');
  int _lockTimeoutMinutes = 5;
  String? _pinCode;
  bool _pinEnabled = false;
  bool _biometricEnabled = false;

  Locale get locale => _locale;
  int get lockTimeoutMinutes => _lockTimeoutMinutes;
  bool get pinEnabled => _pinEnabled && (_pinCode?.isNotEmpty ?? false);
  bool get biometricEnabled => _biometricEnabled;
  bool get hasPin => _pinCode?.isNotEmpty ?? false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final localeCode = prefs.getString(_localeKey);
    if (localeCode != null && localeCode.isNotEmpty) {
      _locale = Locale(localeCode);
    }
    _lockTimeoutMinutes = prefs.getInt(_lockTimeoutKey) ?? 5;
    _pinCode = prefs.getString(_pinKey);
    _pinEnabled = prefs.getBool(_pinEnabledKey) ?? false;
    _biometricEnabled = prefs.getBool(_biometricEnabledKey) ?? false;
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
  }

  Future<void> setLockTimeout(int minutes) async {
    _lockTimeoutMinutes = minutes.clamp(1, 60);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lockTimeoutKey, _lockTimeoutMinutes);
  }

  Future<void> setPin(String pin) async {
    _pinCode = pin;
    _pinEnabled = pin.isNotEmpty;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, pin);
    await prefs.setBool(_pinEnabledKey, _pinEnabled);
  }

  Future<void> clearPin() async {
    _pinCode = null;
    _pinEnabled = false;
    _biometricEnabled = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey);
    await prefs.setBool(_pinEnabledKey, false);
    await prefs.setBool(_biometricEnabledKey, false);
  }

  Future<void> setPinEnabled(bool enabled) async {
    _pinEnabled = enabled && hasPin;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pinEnabledKey, _pinEnabled);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    _biometricEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, enabled);
  }

  bool verifyPin(String pin) => hasPin && _pinCode == pin;
}
