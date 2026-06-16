import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/services/dashboard_warning_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('ignored warnings are persisted per profile', () async {
    final preferences = DashboardWarningPreferences(
      await SharedPreferences.getInstance(),
    );

    await preferences.ignore('profile-a', DashboardWarningKind.cpuHigh);

    expect(
      preferences.ignoredForProfile('profile-a'),
      {DashboardWarningKind.cpuHigh},
    );
    expect(preferences.ignoredForProfile('profile-b'), isEmpty);
  });

  test('snoozed warnings remain active until their expiry', () async {
    final now = DateTime(2026, 6, 16, 10);
    final preferences = DashboardWarningPreferences(
      await SharedPreferences.getInstance(),
    );

    await preferences.snooze(
      'profile-a',
      DashboardWarningKind.thermalHigh,
      duration: const Duration(hours: 24),
      now: now,
    );

    expect(
      preferences.isSuppressed(
        'profile-a',
        DashboardWarningKind.thermalHigh,
        now: now.add(const Duration(hours: 23)),
      ),
      isTrue,
    );
    expect(
      preferences.isSuppressed(
        'profile-a',
        DashboardWarningKind.thermalHigh,
        now: now.add(const Duration(hours: 25)),
      ),
      isFalse,
    );
  });

  test('ignoring a warning removes its snooze entry', () async {
    final preferences = DashboardWarningPreferences(
      await SharedPreferences.getInstance(),
    );

    await preferences.snooze(
      'profile-a',
      DashboardWarningKind.gatewayLoss,
    );
    await preferences.ignore(
      'profile-a',
      DashboardWarningKind.gatewayLoss,
    );

    expect(
      preferences.ignoredForProfile('profile-a'),
      contains(DashboardWarningKind.gatewayLoss),
    );
    expect(preferences.snoozedForProfile('profile-a'), isEmpty);
  });

  test('restoring ignored warnings does not affect another profile', () async {
    final preferences = DashboardWarningPreferences(
      await SharedPreferences.getInstance(),
    );

    await preferences.ignore('profile-a', DashboardWarningKind.diskHigh);
    await preferences.ignore('profile-b', DashboardWarningKind.memoryHigh);
    await preferences.restoreIgnored('profile-a');

    expect(preferences.ignoredForProfile('profile-a'), isEmpty);
    expect(
      preferences.ignoredForProfile('profile-b'),
      {DashboardWarningKind.memoryHigh},
    );
  });

  test('malformed snooze data is safely ignored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dashboard.warningPreferences.profile-a.snoozed': '{not-json',
    });
    final preferences = DashboardWarningPreferences(
      await SharedPreferences.getInstance(),
    );

    expect(preferences.snoozedForProfile('profile-a'), isEmpty);
  });
}
