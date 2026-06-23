import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';

class ProfileProvider extends ChangeNotifier {
  static const _profilesKey = 'profiles';
  static const _selectedProfileKey = 'selectedProfileId';
  static const _securePrefix = 'profile_api_key_';
  static const _defaultSecureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final FlutterSecureStorage _secureStorage;
  List<PfSenseProfile> _profiles = [];
  String? _selectedProfileId;
  bool _isLoading = false;
  bool _hasLoaded = false;

  ProfileProvider({
    FlutterSecureStorage secureStorage = _defaultSecureStorage,
  }) : _secureStorage = secureStorage;

  List<PfSenseProfile> get profiles => List.unmodifiable(_profiles);
  String? get selectedProfileId => _selectedProfileId;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;

  PfSenseProfile? get selectedProfile {
    if (_selectedProfileId == null) return null;
    for (final profile in _profiles) {
      if (profile.id == _selectedProfileId) return profile;
    }
    return null;
  }

  static Future<PfSenseProfile> resolveForConnection(
    PfSenseProfile profile,
  ) async {
    if (profile.apiKey.isNotEmpty) return profile;
    final apiKey = await _defaultSecureStorage.read(
      key: '$_securePrefix${profile.id}',
    );
    return profile.copyWith(apiKey: apiKey ?? '');
  }

  Future<void> addProfile(PfSenseProfile profile) async {
    _profiles.add(profile.copyWith(apiKey: ''));
    _selectedProfileId ??= profile.id;
    notifyListeners();
    await _persistProfile(profile);
    await _saveProfiles();
    await _saveSelection();
  }

  Future<void> updateProfile(PfSenseProfile updated) async {
    final index = _profiles.indexWhere((p) => p.id == updated.id);
    if (index == -1) return;

    _profiles[index] = updated.copyWith(apiKey: '');
    notifyListeners();

    if (updated.apiKey.isNotEmpty) {
      await _persistProfile(updated);
    }
    await _saveProfiles();
  }

  Future<void> removeProfile(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    await _secureStorage.delete(key: '$_securePrefix$id');
    if (_selectedProfileId == id) {
      _selectedProfileId = _profiles.isNotEmpty ? _profiles.first.id : null;
    }
    notifyListeners();
    await _saveProfiles();
    await _saveSelection();
  }

  Future<void> selectProfile(String id) async {
    if (!_profiles.any((p) => p.id == id)) return;
    _selectedProfileId = id;
    notifyListeners();
    await _saveSelection();
  }

  String exportProfiles() {
    final data = _profiles.map((p) => p.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<int> importProfiles(String jsonStr) async {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! List) {
      throw const FormatException('Profile export must be a JSON array.');
    }

    var count = 0;
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        final profile = PfSenseProfile.fromJson(item).copyWith(apiKey: '');
        if (!_profiles.any((p) => p.id == profile.id)) {
          _profiles.add(profile);
          count++;
        }
      }
    }
    if (_selectedProfileId == null && _profiles.isNotEmpty) {
      _selectedProfileId = _profiles.first.id;
    }
    notifyListeners();
    await _saveProfiles();
    await _saveSelection();
    return count;
  }

  Future<void> loadProfiles() async {
    _isLoading = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final rawProfiles = prefs.getString(_profilesKey);
    _selectedProfileId = prefs.getString(_selectedProfileKey);

    if (rawProfiles != null && rawProfiles.isNotEmpty) {
      final decoded = jsonDecode(rawProfiles);
      if (decoded is List) {
        _profiles = [
          for (final item in decoded)
            if (item is Map<String, dynamic>)
              PfSenseProfile.fromJson(item).copyWith(apiKey: ''),
        ];
      }
    }

    if (_selectedProfileId != null &&
        !_profiles.any((p) => p.id == _selectedProfileId)) {
      _selectedProfileId = _profiles.isNotEmpty ? _profiles.first.id : null;
    }

    _isLoading = false;
    _hasLoaded = true;
    notifyListeners();
  }

  Future<void> _persistProfile(PfSenseProfile profile) async {
    await _secureStorage.write(
      key: '$_securePrefix${profile.id}',
      value: profile.apiKey,
    );
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    await prefs.setString(_profilesKey, raw);
  }

  Future<void> _saveSelection() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedProfileId == null) {
      await prefs.remove(_selectedProfileKey);
    } else {
      await prefs.setString(_selectedProfileKey, _selectedProfileId!);
    }
  }
}
