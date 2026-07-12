part of 'network_monitor_screen.dart';

extension _NetworkMonitorPolling on _NetworkMonitorScreenState {
  Future<void> _load({bool showSpinner = false}) async {
    if (_loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!session.connected || session.service == null) {
      _commitState(() {
        _clearLiveData();
        _error = 'Disconnected';
      });
      return;
    }

    final request = ++_requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    if (showSpinner) {
      _commitState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        session.service!.getInterfaceStatuses(),
        session.service!.getFirewallStates(limit: 500),
      ]);
      if (!_isCurrentRequest(request, sessionGeneration, profileId)) return;

      final interfaces = results[0] as List<InterfaceStatus>;
      final states = results[1] as List<NetworkState>;
      _recordRates(interfaces);
      _commitState(() {
        _interfaces = interfaces;
        _states = states;
        _error = null;
        _lastSuccessfulRefresh = DateTime.now();
      });
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        _commitState(() => _error = error);
      }
    } finally {
      if (mounted && request == _requestGeneration && showSpinner) {
        _commitState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshInterfaces() async {
    if (_interfacesRefreshing || _loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!_canPoll(session)) return;

    _interfacesRefreshing = true;
    final request = _requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    try {
      final interfaces = await session.service!.getInterfaceStatuses();
      if (!_isCurrentRequest(request, sessionGeneration, profileId)) return;
      _recordRates(interfaces);
      _commitState(() {
        _interfaces = interfaces;
        _error = null;
        _lastSuccessfulRefresh = DateTime.now();
      });
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        _commitState(() => _error = error);
      }
    } finally {
      _interfacesRefreshing = false;
    }
  }

  Future<void> _refreshStates() async {
    if (_statesRefreshing || _loading) return;
    final session = context.read<PfSenseSessionProvider>();
    if (!_canPoll(session)) return;

    _statesRefreshing = true;
    final request = _requestGeneration;
    final sessionGeneration = session.sessionGeneration;
    final profileId = session.selectedProfile?.id;
    try {
      final states = await session.service!.getFirewallStates(limit: 500);
      if (!_isCurrentRequest(request, sessionGeneration, profileId)) return;
      _commitState(() {
        _states = states;
        _error = null;
        _lastSuccessfulRefresh = DateTime.now();
      });
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        _commitState(() => _error = error);
      }
    } finally {
      _statesRefreshing = false;
    }
  }

  bool _canPoll(PfSenseSessionProvider session) {
    return _live &&
        _appActive &&
        session.connected &&
        session.service != null;
  }

  bool _isCurrentRequest(
    int request,
    int sessionGeneration,
    String? profileId,
  ) {
    if (!mounted || request != _requestGeneration) return false;
    final session = context.read<PfSenseSessionProvider>();
    return sessionGeneration == session.sessionGeneration &&
        profileId == session.selectedProfile?.id;
  }

  void _recordRates(List<InterfaceStatus> interfaces) {
    final now = DateTime.now();
    final elapsed = _lastSampleAt == null
        ? _refreshSeconds.toDouble()
        : math.max(
            0.5,
            now.difference(_lastSampleAt!).inMilliseconds / 1000,
          );
    final nextCounters = <String, _InterfaceCounters>{};
    final nextRates = <String, _InterfaceRates>{};
    var totalIn = 0.0;
    var totalOut = 0.0;

    for (final interface in interfaces) {
      final key = _interfaceLabel(interface);
      final current = _InterfaceCounters(
        bytesIn: interface.bytesIn,
        bytesOut: interface.bytesOut,
      );
      final previous = _previousCounters[key];
      final inRate = previous == null
          ? 0.0
          : math.max(0, current.bytesIn - previous.bytesIn) / elapsed;
      final outRate = previous == null
          ? 0.0
          : math.max(0, current.bytesOut - previous.bytesOut) / elapsed;

      nextCounters[key] = current;
      nextRates[key] = _InterfaceRates(inBps: inRate, outBps: outRate);
      totalIn += inRate;
      totalOut += outRate;

      final history = _interfaceHistory.putIfAbsent(key, () => []);
      history.add(
        _RateSample(capturedAt: now, inBps: inRate, outBps: outRate),
      );
      _trimHistory(history, now);
    }

    _totalHistory.add(
      _RateSample(capturedAt: now, inBps: totalIn, outBps: totalOut),
    );
    _trimHistory(_totalHistory, now);

    _previousCounters
      ..clear()
      ..addAll(nextCounters);
    _rates
      ..clear()
      ..addAll(nextRates);
    _lastSampleAt = now;
  }

  void _trimHistory(List<_RateSample> history, DateTime now) {
    final cutoff = now.subtract(
      const Duration(seconds: networkMonitorHistoryWindowSeconds),
    );
    history.removeWhere((sample) => sample.capturedAt.isBefore(cutoff));
    final maxSamples = networkMonitorHistorySampleLimit(_refreshSeconds);
    if (history.length > maxSamples) {
      history.removeRange(0, history.length - maxSamples);
    }
  }
}
