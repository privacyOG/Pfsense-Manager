import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/providers/theme_provider.dart';

void main() {
  test('navigation theme keeps only the selected destination prominent', () {
    final theme = ThemeProvider.pfsenseNavyDarkTheme;
    final navigation = theme.navigationBarTheme;

    expect(navigation.height, appBottomNavigationHeight);

    final selectedIcon = navigation.iconTheme!.resolve({WidgetState.selected});
    final unselectedIcon = navigation.iconTheme!.resolve({});
    final selectedLabel =
        navigation.labelTextStyle!.resolve({WidgetState.selected});
    final unselectedLabel = navigation.labelTextStyle!.resolve({});

    expect(selectedIcon!.size, greaterThan(unselectedIcon!.size!));
    expect(selectedLabel!.fontWeight, FontWeight.w700);
    expect(unselectedLabel!.fontWeight, FontWeight.w500);
    expect(selectedLabel.color, isNot(unselectedLabel.color));
  });

  test('tab theme uses a selected pill and quieter unselected labels', () {
    final theme = ThemeProvider.pfsenseNavyDarkTheme;
    final tabTheme = theme.tabBarTheme;

    expect(tabTheme.indicator, isA<BoxDecoration>());
    expect(tabTheme.indicatorSize, TabBarIndicatorSize.tab);
    expect(tabTheme.labelStyle?.fontWeight, FontWeight.w700);
    expect(tabTheme.unselectedLabelStyle?.fontWeight, FontWeight.w500);
    expect(tabTheme.labelColor, isNot(tabTheme.unselectedLabelColor));
  });

  testWidgets('bottom navigation uses the compact themed height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeProvider.pfsenseNavyDarkTheme,
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 2,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.monitor_heart_outlined),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.shield_outlined),
                label: 'Firewall',
              ),
              NavigationDestination(
                icon: Icon(Icons.hub_outlined),
                label: 'Network',
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(NavigationBar)).height,
        appBottomNavigationHeight);
    expect(find.text('Network'), findsOneWidget);
  });
}
