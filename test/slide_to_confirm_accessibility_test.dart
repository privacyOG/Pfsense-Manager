import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/l10n/app_strings.dart';
import 'package:pfsense_manager/widgets/slide_to_confirm.dart';

Widget _buildSlider({
  required VoidCallback onConfirmed,
  TextDirection textDirection = TextDirection.ltr,
  TextScaler textScaler = TextScaler.noScaling,
  bool autofocus = false,
  String label = 'Slide to confirm',
}) {
  return MaterialApp(
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: SlideToConfirm(
                label: label,
                semanticLabel: label,
                autofocus: autofocus,
                onConfirmed: onConfirmed,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _dragThumb(WidgetTester tester, Offset delta) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('slide-to-confirm-thumb'))),
  );
  await gesture.moveBy(delta);
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('LTR confirmation completes by dragging toward the end',
      (tester) async {
    var confirmations = 0;
    await tester.pumpWidget(
      _buildSlider(onConfirmed: () => confirmations += 1),
    );

    await _dragThumb(tester, const Offset(300, 0));

    expect(confirmations, 1);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('RTL confirmation reverses the drag direction', (tester) async {
    var confirmations = 0;
    await tester.pumpWidget(
      _buildSlider(
        textDirection: TextDirection.rtl,
        onConfirmed: () => confirmations += 1,
      ),
    );

    await _dragThumb(tester, const Offset(300, 0));
    expect(confirmations, 0);

    await _dragThumb(tester, const Offset(-300, 0));
    expect(confirmations, 1);
  });

  testWidgets('assistive technology can activate confirmation',
      (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    addTearDown(semanticsHandle.dispose);
    var confirmations = 0;

    await tester.pumpWidget(
      _buildSlider(
        label: 'Confirm firewall reboot',
        onConfirmed: () => confirmations += 1,
      ),
    );

    final node = tester.getSemantics(
      find.byKey(const Key('slide-to-confirm')),
    );
    expect(node.label, 'Confirm firewall reboot');
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasAction(SemanticsAction.tap), isTrue);

    tester.binding.pipelineOwner.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    await tester.pump();

    expect(confirmations, 1);
  });

  testWidgets('keyboard activation confirms the focused control',
      (tester) async {
    var confirmations = 0;
    await tester.pumpWidget(
      _buildSlider(
        autofocus: true,
        onConfirmed: () => confirmations += 1,
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(confirmations, 1);
  });

  testWidgets('large text expands the control and preserves tap targets',
      (tester) async {
    await tester.pumpWidget(
      _buildSlider(
        textScaler: TextScaler.linear(2),
        label: 'Slide to confirm this sensitive firewall operation',
        onConfirmed: () {},
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('slide-to-confirm'))).height,
      greaterThan(60),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('confirmation sheet localizes cancel and survives large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showSlideToConfirmSheet(
                    context: context,
                    title: 'تأكيد العملية الحساسة',
                    body:
                        'راجع التأثير بعناية قبل تطبيق هذا التغيير على جدار الحماية.',
                    slideLabel: 'اسحب للتأكيد',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('إلغاء'), findsOneWidget);
    expect(find.byKey(const Key('slide-to-confirm')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
