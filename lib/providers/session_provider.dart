import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/api_client.dart';
import '../services/pfsense_service.dart';

/// Provider that holds the currently selected pfSense profile and API service.
class PfSenseSessionProvider extends ChangeNotifier {
  PfSenseProfile? _selectedProfile;
  PfSenseService? _service;
  bool _connected = false;
  String? _connectionError;

  PfSenseProfile? get selectedProfile => _selectedProfile;
  PfSenseService? get service => _service;
  bool get connected => _connected;
  String? get connectionError => _connectionError;

  Future<void> connect(PfSenseProfile profile) async {
    _connected = false;
    _connectionError = null;
    notifyListeners();

    try {
      _selectedProfile = profile;
      final client = PfSenseApiClient(profile);
      _service = PfSenseService(client);

      final healthy = await _service!.healthCheck();
      if (healthy) {
        _connected = true;
        _connectionError = null;
      } else {
        _connected = false;
        _connectionError = 'Connection failed. Check credentials and network.';
      }
    } catch (e) {
      _connected = false;
      _connectionError = e.toString();
    }

    notifyListeners();
  }

  Future<void> disconnect() async {
    _service?.dispose();
    _selectedProfile = null;
    _service = null;
    _connected = false;
    _connectionError = null;
    notifyListeners();
  }

  void clearError() {
    _connectionError = null;
    notifyListeners();
  }
}
