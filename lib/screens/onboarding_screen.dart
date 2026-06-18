import 'package:flutter/material.dart';

import '../widgets/brand_mark.dart';
import 'profile_form_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _steps = [
    _OnboardingStep(
      icon: Icons.router_outlined,
      title: 'Welcome to pfSense Manager',
      body:
          'Connect directly to your pfSense firewall from your phone. Monitor traffic, manage services, control VPNs — all in one place.',
      hint: null,
    ),
    _OnboardingStep(
      icon: Icons.api_outlined,
      title: 'Enable the REST API',
      body:
          'In your pfSense web interface, go to System → API → Settings and enable the API. This lets pfSense Manager communicate securely with your firewall.',
      hint: 'System → API → Settings → Enable API',
    ),
    _OnboardingStep(
      icon: Icons.key_outlined,
      title: 'Create API credentials',
      body:
          'Create a dedicated API user under System → API → Keys. Give it a strong description so you remember what it is for.',
      hint: 'System → API → Keys → Create key',
    ),
    _OnboardingStep(
      icon: Icons.verified_user_outlined,
      title: 'Set permissions',
      body:
          'Assign the API user read/write access to the endpoints you need (Firewall, Services, System). Limit to read-only if you only want to monitor.',
      hint: 'Assign only the permissions you need',
    ),
    _OnboardingStep(
      icon: Icons.add_link_outlined,
      title: 'Add your firewall profile',
      body:
          "You're all set. Enter your firewall's address and the API credentials you just created. Credentials are stored in the secure platform keystore and never leave your device.",
      hint: null,
    ),
  ];

  void _next() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ProfileFormScreen()),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLast = _currentPage == _steps.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const PfSenseBrandMark(size: 36),
                  const Spacer(),
                  TextButton(
                    onPressed: _finish,
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) =>
                    _StepPage(step: _steps[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _steps.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _currentPage ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _currentPage
                              ? scheme.primary
                              : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _next,
                    icon: Icon(
                      isLast ? Icons.add_link_outlined : Icons.arrow_forward,
                    ),
                    label: Text(isLast ? 'Add profile' : 'Next'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? hint;
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.step});

  final _OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              step.icon,
              size: 36,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            step.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            step.body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
          ),
          if (step.hint != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 16, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.hint!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
