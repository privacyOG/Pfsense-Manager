import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/pin_verifier.dart';

class AppSettingsProvider extends ChangeNotifier {
  static const _localeKey = 'localeCode';
  static const _lockTimeoutKey = 'lockTimeoutMinutes';
  static const _legacyPinKey = 'pinCode';
  static const _pinEnabledKey = 'pinEnabled';
  static const _biometricEnabledKey = 'biometricEnabled';

  AppSettingsProvider({
    PinVerifierStore? pinStore,
    DateTime Function()? now,
  })  : _pinStore = pinStore ?? SecurePinVerifierStore(),
        _now = now ?? DateTime.now;

  final PinVerifierStore _pinStore;
  final DateTime Function() _now;

  Locale _locale = const Locale('en');
  int _lockTimeoutMinutes = 5;
  String? _pinVerifier;
  bool _pinEnabled = false;
  bool _biometricEnabled = false;
  bool _hasLoaded = false;
  int _failedPinAttempts = 0;
  DateTime? _pinRetryAfter;

  Locale get locale => _locale;
  int get lockTimeoutMinutes => _lockTimeoutMinutes;
  bool get pinEnabled => _pinEnabled && hasPin;
  bool get biometricEnabled => _biometricEnabled;
  bool get hasPin => _pinVerifier?.isNotEmpty ?? false;
  bool get hasLoaded => _hasLoaded;
  bool get lockEnabled => pinEnabled || biometricEnabled;

  int get pinRetrySeconds {
    final retryAfter = _pinRetryAfter;
    if (retryAfter == null) return 0;
    final remaining = retryAfter.difference(_now()).inMilliseconds;
    if (remaining <= 0) return 0;
    return (remaining / Duration.millisecondsPerSecond).ceil();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final localeCode = prefs.getString(_localeKey);
      if (localeCode != null && localeCode.isNotEmpty) {
        _locale = Locale(localeCode);
      }
      _lockTimeoutMinutes = prefs.getInt(_lockTimeoutKey) ?? 5;
      _pinEnabled = prefs.getBool(_pinEnabledKey) ?? false;
      _biometricEnabled = prefs.getBool(_biometricEnabledKey) ?? false;

      _pinVerifier = await _pinStore.read();
      final legacyPin = prefs.getString(_legacyPinKey);
      if ((_pinVerifier?.isEmpty ?? true) &&
          legacyPin != null &&
          legacyPin.isNotEmpty) {
        final migratedVerifier = await createPinVerifier(legacyPin);
        await _pinStore.write(migratedVerifier);
        _pinVerifier = migratedVerifier;
        await prefs.remove(_legacyPinKey);
      } else if (legacyPin != null && _pinVerifier != null) {
        await prefs.remove(_legacyPinKey);
      }
    } finally {
      _hasLoaded = true;
      notifyListeners();
    }
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
    final normalizedPin = pin.trim();
    if (normalizedPin.isEmpty) {
      await clearPin();
      return;
    }

    final verifier = await createPinVerifier(normalizedPin);
    await _pinStore.write(verifier);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyPinKey);
    await prefs.setBool(_pinEnabledKey, true);

    _pinVerifier = verifier;
    _pinEnabled = true;
    _failedPinAttempts = 0;
    _pinRetryAfter = null;
    notifyListeners();
  }

  Future<void> clearPin() async {
    await _pinStore.delete();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyPinKey);
    await prefs.setBool(_pinEnabledKey, false);
    await prefs.setBool(_biometricEnabledKey, false);

    _pinVerifier = null;
    _pinEnabled = false;
    _biometricEnabled = false;
    _failedPinAttempts = 0;
    _pinRetryAfter = null;
    notifyListeners();
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

  Future<bool> verifyPin(String pin) async {
    final verifier = _pinVerifier;
    if (verifier == null || verifier.isEmpty || pinRetrySeconds > 0) {
      return false;
    }

    final matches = await verifyPinVerifier(pin.trim(), verifier);
    if (matches) {
      _failedPinAttempts = 0;
      _pinRetryAfter = null;
      notifyListeners();
      return true;
    }

    _failedPinAttempts++;
    if (_failedPinAttempts >= 3) {
      final exponent = math.min(5, _failedPinAttempts - 3);
      final delaySeconds = math.min(30, 1 << exponent);
      _pinRetryAfter = _now().add(Duration(seconds: delaySeconds));
    }
    notifyListeners();
    return false;
  }
}
