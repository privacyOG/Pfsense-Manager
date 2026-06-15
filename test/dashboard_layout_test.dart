import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/models/dashboard_layout.dart';

void main() {
  group('DashboardLayout.normalize', () {
    test('keeps a valid saved order', () {
      final order = DashboardLayout.normalize(const [
        DashboardLayoutSection.interfaces,
        DashboardLayoutSection.health,
        DashboardLayoutSection.gateways,
        DashboardLayoutSection.system,
      ]);

      expect(order, const [
        DashboardLayoutSection.interfaces,
        DashboardLayoutSection.health,
        DashboardLayoutSection.gateways,
        DashboardLayoutSection.system,
      ]);
    });

    test('removes unknown and duplicate entries and appends missing sections', () {
      final order = DashboardLayout.normalize(const [
        'unknown',
        DashboardLayoutSection.gateways,
        DashboardLayoutSection.gateways,
      ]);

      expect(order, const [
        DashboardLayoutSection.gateways,
        DashboardLayoutSection.health,
        DashboardLayoutSection.system,
        DashboardLayoutSection.interfaces,
      ]);
    });

    test('uses defaults when no order is saved', () {
      expect(
        DashboardLayout.normalize(null),
        DashboardLayoutSection.defaults,
      );
    });
  });
}
