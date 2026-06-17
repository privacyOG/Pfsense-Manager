import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/session_provider.dart';
import '../screens/lock_screen.dart';

/// Keeps the application lock above the app Navigator so route changes cannot
/// remove or bypass it.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  Timer? _idleTimer;
  bool _initialized = false;
  bool _locked = true;
  bool _hasPresentedChild = false;
  bool _settingsSyncScheduled = false;
  bool? _lastLockEnabled;
  int? _lastTimeoutMinutes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _lock();
        break;
      case AppLifecycleState.resumed:
        break;
    }
  }

  void _scheduleSettingsSync(AppSettingsProvider settings) {
    if (!settings.hasLoaded || _settingsSyncScheduled) return;

    final changed = !_initialized ||
        _lastLockEnabled != settings.lockEnabled ||
        _lastTimeoutMinutes != settings.lockTimeoutMinutes;
    if (!changed) return;

    _settingsSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settingsSyncScheduled = false;
      if (!mounted) return;
      _applySettings(context.read<AppSettingsProvider>());
    });
  }

  void _applySettings(AppSettingsProvider settings) {
    if (!settings.hasLoaded) return;

    final firstLoad = !_initialized;
    final lockEnabled = settings.lockEnabled;

    setState(() {
      _initialized = true;
      _lastLockEnabled = lockEnabled;
      _lastTimeoutMinutes = settings.lockTimeoutMinutes;

      if (firstLoad) {
        _locked = lockEnabled;
        _hasPresentedChild = !lockEnabled;
      } else if (!lockEnabled) {
        _locked = false;
        _hasPresentedChild = true;
      }
    });

    if (!lockEnabled) {
      _idleTimer?.cancel();
      final session = context.read<PfSenseSessionProvider>();
      if (session.suspendedForLock) {
        unawaited(
          session.resumeAfterUnlock(
            context.read<ProfileProvider>().selectedProfile,
          ),
        );
      }
      return;
    }

    if (!_locked) _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (!mounted || _locked || !_initialized) return;

    final settings = context.read<AppSettingsProvider>();
    if (!settings.lockEnabled) return;

    _idleTimer = Timer(
      Duration(minutes: settings.lockTimeoutMinutes),
      _lock,
    );
  }

  void _onActivity([PointerEvent? _]) {
    if (!_locked) _resetIdleTimer();
  }

  void _lock() {
    if (!mounted || _locked || !_initialized) return;
    if (!context.read<AppSettingsProvider>().lockEnabled) return;

    _idleTimer?.cancel();
    setState(() => _locked = true);
    context.read<PfSenseSessionProvider>().suspendForLock();
  }

  Future<void> _unlock() async {
    if (!_locked) return;

    setState(() {
      _locked = false;
      _hasPresentedChild = true;
    });
    _resetIdleTimer();

    final session = context.read<PfSenseSessionProvider>();
    if (session.suspendedForLock) {
      await session.resumeAfterUnlock(
        context.read<ProfileProvider>().selectedProfile,
      );
    }
  }

  Widget _buildLockSurface() {
    return HeroControllerScope.none(
      child: Navigator(
        key: const ValueKey<String>('app-lock-navigator'),
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/locked'),
          builder: (_) => LockScreen(onUnlock: () => unawaited(_unlock())),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    _scheduleSettingsSync(settings);

    if (!settings.hasLoaded || !_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_locked && !_hasPresentedChild) {
      return _buildLockSurface();
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onActivity,
      onPointerMove: _onActivity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_locked) Positioned.fill(child: _buildLockSurface()),
        ],
      ),
    );
  }
}
