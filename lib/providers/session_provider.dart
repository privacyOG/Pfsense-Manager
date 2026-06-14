import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/api_client.dart';
import '../services/pfsense_service.dart';

/// Holds the active pfSense API session.
///
/// Connection attempts are generation-checked so a slower, older request cannot
/// replace a newer profile selection. Superseded API clients are always closed.
class PfSenseSessionProvider extends ChangeNotifier {
  PfSenseProfile? _selectedProfile;
  PfSenseService? _service;
  bool _connected = false;
  bool _connecting = false;
  String? _connectionError;
  int _connectionGeneration = 0;

  PfSenseProfile? get selectedProfile => _selectedProfile;
  PfSenseService? get service => _service;
  bool get connected => _connected;
  bool get connecting => _connecting;
  String? get connectionError => _connectionError;

  Future<void> connect(PfSenseProfile profile) async {
    final generation = ++_connectionGeneration;

    _service?.dispose();
    _service = null;
    _selectedProfile = profile;
    _connected = false;
    _connecting = true;
    _connectionError = null;
    notifyListeners();

    PfSenseService? candidate;
    try {
      candidate = PfSenseService(PfSenseApiClient(profile));
      final healthy = await candidate.healthCheck();

      if (generation != _connectionGeneration) {
        candidate.dispose();
        return;
      }

      if (!healthy) {
        candidate.dispose();
        _connecting = false;
        _connectionError =
            'Connection failed. Check credentials, API permissions and network.';
        notifyListeners();
        return;
      }

      _service = candidate;
      _connected = true;
      _connecting = false;
      _connectionError = null;
      notifyListeners();
    } catch (error) {
      candidate?.dispose();
      if (generation != _connectionGeneration) return;

      _connected = false;
      _connecting = false;
      _connectionError = error.toString();
      notifyListeners();
    }
  }

  Future<void> reconnect(PfSenseProfile profile) async {
    if (_connecting) return;
    await connect(profile);
  }

  Future<void> disconnect({bool keepProfile = true}) async {
    _connectionGeneration++;
    _service?.dispose();
    _service = null;
    if (!keepProfile) _selectedProfile = null;
    _connected = false;
    _connecting = false;
    _connectionError = null;
    notifyListeners();
  }

  void clearError() {
    _connectionError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectionGeneration++;
    _service?.dispose();
    super.dispose();
  }
}
