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
  String? _error;

  @override
  void dispose() {
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
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _pinUnlock(AppSettingsProvider settings) {
    if (settings.verifyPin(_pinController.text.trim())) {
      widget.onUnlock();
    } else {
      setState(() => _error = 'Incorrect PIN');
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final settings = context.watch<AppSettingsProvider>();
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
                        onPressed: () => _pinUnlock(settings),
                        icon: const Icon(Icons.lock_open),
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
