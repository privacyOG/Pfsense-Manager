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
  bool _suspendedForLock = false;
  bool _reconnectAfterUnlock = false;
  String? _connectionError;
  int _sessionGeneration = 0;

  PfSenseProfile? get selectedProfile => _selectedProfile;
  PfSenseService? get service => _service;
  bool get connected => _connected;
  bool get connecting => _connecting;
  bool get suspendedForLock => _suspendedForLock;
  String? get connectionError => _connectionError;

  /// Changes whenever the active session becomes invalid or is replaced.
  /// Feature screens capture this value before a request and ignore responses
  /// that complete after the generation changes.
  int get sessionGeneration => _sessionGeneration;

  Future<void> connect(PfSenseProfile profile) async {
    if (_suspendedForLock) return;

    final generation = ++_sessionGeneration;

    _service?.dispose();
    _service = null;
    _selectedProfile = profile.copyWith(apiKey: '');
    _connected = false;
    _connecting = true;
    _connectionError = null;
    notifyListeners();

    PfSenseService? candidate;
    try {
      candidate = PfSenseService(PfSenseApiClient(profile));
      final healthy = await candidate.healthCheck();

      if (generation != _sessionGeneration || _suspendedForLock) {
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
      if (generation != _sessionGeneration || _suspendedForLock) return;

      _connected = false;
      _connecting = false;
      _connectionError = error.toString();
      notifyListeners();
    }
  }

  Future<void> reconnect(PfSenseProfile profile) async {
    if (_suspendedForLock || _connecting) return;
    await connect(profile);
  }

  /// Closes the active API client while the application is locked.
  ///
  /// Any automatic reconnect attempt is blocked until [resumeAfterUnlock] is
  /// called after successful PIN or device authentication.
  void suspendForLock() {
    if (_suspendedForLock) return;

    _reconnectAfterUnlock = _connected || _connecting;
    _suspendedForLock = true;
    _sessionGeneration++;
    _service?.dispose();
    _service = null;
    _connected = false;
    _connecting = false;
    _connectionError = null;
    notifyListeners();
  }

  Future<void> resumeAfterUnlock(PfSenseProfile? profile) async {
    final shouldReconnect = _reconnectAfterUnlock;
    _suspendedForLock = false;
    _reconnectAfterUnlock = false;

    if (shouldReconnect && profile != null) {
      await connect(profile);
    } else {
      notifyListeners();
    }
  }

  Future<void> disconnect({bool keepProfile = true}) async {
    _sessionGeneration++;
    _service?.dispose();
    _service = null;
    if (!keepProfile) _selectedProfile = null;
    _connected = false;
    _connecting = false;
    _suspendedForLock = false;
    _reconnectAfterUnlock = false;
    _connectionError = null;
    notifyListeners();
  }

  void clearError() {
    _connectionError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionGeneration++;
    _service?.dispose();
    super.dispose();
  }
}
