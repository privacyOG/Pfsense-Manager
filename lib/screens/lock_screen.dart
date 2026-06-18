import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/app_settings_provider.dart';
import '../widgets/brand_mark.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlock;

  const LockScreen({super.key, required this.onUnlock});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pinController = TextEditingController();
  final _auth = LocalAuthentication();
  Timer? _retryTimer;
  String? _error;
  bool _checkingPin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<AppSettingsProvider>();
      if (mounted && settings.biometricEnabled) _biometricUnlock();
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _biometricUnlock() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock pfSense Manager',
        options: const AuthenticationOptions(biometricOnly: false),
      );
      if (ok && mounted) widget.onUnlock();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _pinUnlock(AppSettingsProvider settings) async {
    if (_checkingPin) return;

    final currentDelay = settings.pinRetrySeconds;
    if (currentDelay > 0) {
      setState(() => _error = 'Try again in $currentDelay seconds');
      _startRetryTimer(settings);
      return;
    }

    setState(() {
      _checkingPin = true;
      _error = null;
    });

    final matches = await settings.verifyPin(_pinController.text.trim());
    if (!mounted) return;

    if (matches) {
      _checkingPin = false;
      widget.onUnlock();
      return;
    }

    _pinController.clear();
    final delay = settings.pinRetrySeconds;
    setState(() {
      _checkingPin = false;
      _error = delay > 0 ? 'Try again in $delay seconds' : 'Incorrect PIN';
    });
    if (delay > 0) _startRetryTimer(settings);
  }

  void _startRetryTimer(AppSettingsProvider settings) {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final remaining = settings.pinRetrySeconds;
      setState(() {
        _error = remaining > 0 ? 'Try again in $remaining seconds' : null;
      });
      if (remaining == 0) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final settings = context.watch<AppSettingsProvider>();
    final retrying = settings.pinRetrySeconds > 0;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PfSenseBrandMark(size: 76),
                const SizedBox(height: 20),
                Text(
                  strings.t('locked'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                if (settings.pinEnabled) ...[
                  TextField(
                    controller: _pinController,
                    enabled: !_checkingPin && !retrying,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 8,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      prefixIcon: Icon(Icons.pin_outlined),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _pinUnlock(settings),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    if (settings.pinEnabled)
                      FilledButton.icon(
                        onPressed: _checkingPin || retrying
                            ? null
                            : () => _pinUnlock(settings),
                        icon: _checkingPin
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.lock_open),
                        label: Text(strings.t('unlock')),
                      ),
                    if (settings.biometricEnabled)
                      FilledButton.tonalIcon(
                        onPressed: _biometricUnlock,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Biometric'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
