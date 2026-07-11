import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/api_client.dart';
import '../services/connection_check.dart';
import '../services/pfsense_service.dart';
import 'profile_provider.dart';

typedef ConnectionProfileResolver = Future<PfSenseProfile> Function(
  PfSenseProfile profile,
);
typedef PfSenseApiClientFactory = PfSenseApiClient Function(
  PfSenseProfile profile,
);

/// Holds the active pfSense API session.
///
/// Connection attempts are generation-checked so a slower, older request cannot
/// replace a newer profile selection. Superseded API clients are always closed.
class PfSenseSessionProvider extends ChangeNotifier {
  PfSenseSessionProvider({
    ConnectionProfileResolver? profileResolver,
    PfSenseApiClientFactory? apiClientFactory,
  })  : _profileResolver =
            profileResolver ?? ProfileProvider.resolveForConnection,
        _apiClientFactory =
            apiClientFactory ?? ((profile) => PfSenseApiClient(profile));

  final ConnectionProfileResolver _profileResolver;
  final PfSenseApiClientFactory _apiClientFactory;

  PfSenseProfile? _selectedProfile;
  PfSenseService? _service;
  bool _connected = false;
  bool _connecting = false;
  bool _suspendedForLock = false;
  bool _reconnectAfterUnlock = false;
  String? _connectionError;
  ConnectionCheckResult? _connectionCheck;
  int _sessionGeneration = 0;

  PfSenseProfile? get selectedProfile => _selectedProfile;
  PfSenseService? get service => _service;
  bool get connected => _connected;
  bool get connecting => _connecting;
  bool get suspendedForLock => _suspendedForLock;
  String? get connectionError => _connectionError;
  ConnectionCheckResult? get connectionCheck => _connectionCheck;
  String? get connectionNotice =>
      _connected && _connectionCheck?.restricted == true
          ? _connectionCheck!.successMessage
          : null;

  /// Changes whenever the active session becomes invalid or is replaced.
  /// Feature screens capture this value before a request and ignore responses
  /// that complete after the generation changes.
  int get sessionGeneration => _sessionGeneration;

  Future<void> connect(PfSenseProfile profile) async {
    if (_suspendedForLock) return;

    final generation = ++_sessionGeneration;

    _service?.dispose();
    _service = null;
    _selectedProfile = profile.copyWith(apiKey: '', password: '');
    _connected = false;
    _connecting = true;
    _connectionError = null;
    _connectionCheck = null;
    notifyListeners();

    PfSenseApiClient? client;
    PfSenseService? candidate;
    try {
      final connectionProfile = await _profileResolver(profile);
      if (generation != _sessionGeneration || _suspendedForLock) return;

      client = _apiClientFactory(connectionProfile);
      final check = await PfSenseConnectionChecker(client).check();

      if (generation != _sessionGeneration || _suspendedForLock) {
        client.dispose();
        return;
      }

      _connectionCheck = check;
      if (!check.connected) {
        client.dispose();
        client = null;
        _connecting = false;
        _connectionError = check.userMessage;
        notifyListeners();
        return;
      }

      candidate = PfSenseService(client);
      client = null;
      _service = candidate;
      _connected = true;
      _connecting = false;
      _connectionError = null;
      notifyListeners();
    } catch (error) {
      candidate?.dispose();
      client?.dispose();
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
    _connectionCheck = null;
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
    _connectionCheck = null;
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
