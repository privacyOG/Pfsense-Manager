import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum DashboardWarningKind {
  cpuHigh,
  memoryHigh,
  diskHigh,
  thermalHigh,
  interfaceDown,
  gatewayLoss,
}

extension DashboardWarningKindStorage on DashboardWarningKind {
  String get storageKey => name;

  static DashboardWarningKind? fromStorageKey(String value) {
    for (final kind in DashboardWarningKind.values) {
      if (kind.storageKey == value) return kind;
    }
    return null;
  }
}

class DashboardWarningPreferences {
  DashboardWarningPreferences(this._preferences);

  static const defaultSnoozeDuration = Duration(hours: 24);
  static const _prefix = 'dashboard.warningPreferences';

  final SharedPreferences _preferences;

  static Future<DashboardWarningPreferences> open() async {
    return DashboardWarningPreferences(await SharedPreferences.getInstance());
  }

  Set<DashboardWarningKind> ignoredForProfile(String profileId) {
    return (_preferences.getStringList(_ignoredKey(profileId)) ?? const [])
        .map(DashboardWarningKindStorage.fromStorageKey)
        .whereType<DashboardWarningKind>()
        .toSet();
  }

  Map<DashboardWarningKind, DateTime> snoozedForProfile(
    String profileId, {
    DateTime? now,
  }) {
    final raw = _preferences.getString(_snoozedKey(profileId));
    if (raw == null || raw.isEmpty) return const {};

    final currentTime = now ?? DateTime.now();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};

      final result = <DashboardWarningKind, DateTime>{};
      for (final entry in decoded.entries) {
        final kind = DashboardWarningKindStorage.fromStorageKey(
          entry.key.toString(),
        );
        final milliseconds = entry.value is num
            ? (entry.value as num).toInt()
            : int.tryParse(entry.value.toString());
        if (kind == null || milliseconds == null) continue;

        final until = DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
          isUtc: true,
        ).toLocal();
        if (until.isAfter(currentTime)) result[kind] = until;
      }
      return result;
    } on FormatException {
      return const {};
    }
  }

  bool isSuppressed(
    String profileId,
    DashboardWarningKind kind, {
    DateTime? now,
  }) {
    if (ignoredForProfile(profileId).contains(kind)) return true;
    final until = snoozedForProfile(profileId, now: now)[kind];
    return until != null && until.isAfter(now ?? DateTime.now());
  }

  Future<void> ignore(
    String profileId,
    DashboardWarningKind kind,
  ) async {
    final ignored = ignoredForProfile(profileId)..add(kind);
    await _preferences.setStringList(
      _ignoredKey(profileId),
      ignored.map((item) => item.storageKey).toList()..sort(),
    );

    final snoozed = snoozedForProfile(profileId)..remove(kind);
    await _writeSnoozed(profileId, snoozed);
  }

  Future<void> snooze(
    String profileId,
    DashboardWarningKind kind, {
    Duration duration = defaultSnoozeDuration,
    DateTime? now,
  }) async {
    final snoozed = snoozedForProfile(profileId, now: now);
    snoozed[kind] = (now ?? DateTime.now()).add(duration);
    await _writeSnoozed(profileId, snoozed);
  }

  Future<void> restoreIgnored(String profileId) async {
    await _preferences.remove(_ignoredKey(profileId));
  }

  Future<void> clearSnoozed(String profileId) async {
    await _preferences.remove(_snoozedKey(profileId));
  }

  int activeSnoozedCount(String profileId, {DateTime? now}) {
    return snoozedForProfile(profileId, now: now).length;
  }

  Future<void> _writeSnoozed(
    String profileId,
    Map<DashboardWarningKind, DateTime> snoozed,
  ) async {
    if (snoozed.isEmpty) {
      await _preferences.remove(_snoozedKey(profileId));
      return;
    }

    final encoded = <String, int>{
      for (final entry in snoozed.entries)
        entry.key.storageKey: entry.value.toUtc().millisecondsSinceEpoch,
    };
    await _preferences.setString(_snoozedKey(profileId), jsonEncode(encoded));
  }

  String _ignoredKey(String profileId) => '$_prefix.$profileId.ignored';

  String _snoozedKey(String profileId) => '$_prefix.$profileId.snoozed';
}
