class DashboardLayoutSection {
  const DashboardLayoutSection._();

  static const health = 'health';
  static const system = 'system';
  static const gateways = 'gateways';
  static const interfaces = 'interfaces';

  static const defaults = <String>[
    health,
    system,
    gateways,
    interfaces,
  ];
}

class DashboardLayout {
  const DashboardLayout._();

  static List<String> normalize(Iterable<String>? savedOrder) {
    final result = <String>[];
    final allowed = DashboardLayoutSection.defaults.toSet();

    for (final item in savedOrder ?? const <String>[]) {
      if (allowed.contains(item) && !result.contains(item)) {
        result.add(item);
      }
    }

    for (final item in DashboardLayoutSection.defaults) {
      if (!result.contains(item)) result.add(item);
    }

    return result;
  }
}
