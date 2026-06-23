import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/brand_mark.dart';
import 'home_shell.dart';
import 'onboarding_screen.dart';
import 'profiles_screen.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, profiles, _) {
        if (!profiles.hasLoaded || profiles.isLoading) {
          return const _BrandSplashScreen();
        }

        if (profiles.profiles.isEmpty) {
          return const OnboardingScreen();
        }

        return const SecureApiLoginScreen();
      },
    );
  }
}

class _BrandSplashScreen extends StatelessWidget {
  const _BrandSplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PfSenseBrandMark(size: 92),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class SecureApiLoginScreen extends StatefulWidget {
  const SecureApiLoginScreen({super.key});

  @override
  State<SecureApiLoginScreen> createState() => _SecureApiLoginScreenState();
}

class _SecureApiLoginScreenState extends State<SecureApiLoginScreen> {
  bool _connecting = false;

  Future<void> _connect(PfSenseProfile profile) async {
    setState(() => _connecting = true);
    final session = context.read<PfSenseSessionProvider>();
    await session.connect(profile);
    if (!mounted) return;
    setState(() => _connecting = false);

    if (session.connected) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer2<ProfileProvider, PfSenseSessionProvider>(
      builder: (context, profiles, session, _) {
        final selected = profiles.selectedProfile ?? profiles.profiles.first;
        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              children: [
                Row(
                  children: [
                    const PfSenseBrandMark(size: 64),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Secure API Login',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'pfSense Manager',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                DropdownButtonFormField<String>(
                  initialValue: selected.id,
                  decoration: const InputDecoration(
                    labelText: 'Profile',
                    prefixIcon: Icon(Icons.router_outlined),
                  ),
                  items: [
                    for (final profile in profiles.profiles)
                      DropdownMenuItem(
                        value: profile.id,
                        child: Text(profile.name),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) profiles.selectProfile(id);
                  },
                ),
                const SizedBox(height: 16),
                _EndpointPreview(profile: selected),
                const SizedBox(height: 18),
                if (session.connectionError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _StatusNotice(
                      icon: Icons.error_outline,
                      text: session.connectionError!,
                      color: scheme.error,
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _connecting ? null : () => _connect(selected),
                  icon: _connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_outlined),
                  label:
                      Text(_connecting ? 'Connecting...' : 'Connect securely'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _connecting
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProfilesScreen(),
                            ),
                          ),
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Manage profiles'),
                ),
                const SizedBox(height: 26),
                _SecurityPanel(
                  title: 'Active security controls',
                  items: [
                    'Credentials are read from secure storage only at connection time.',
                    'This profile uses HTTPS on port ${selected.port}.',
                    selected.allowSelfSignedCert
                        ? 'Self-signed certificates are allowed for this profile.'
                        : 'Self-signed certificates are blocked for this profile.',
                    'Headers and API secrets are not printed to app logs.',
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EndpointPreview extends StatelessWidget {
  const _EndpointPreview({required this.profile});

  final PfSenseProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.enhanced_encryption_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  'API user: ${profile.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security_outlined, color: scheme.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusNotice extends StatelessWidget {
  const _StatusNotice({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
