import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pastehive/src/history/clipboard_entry.dart';
import 'package:pastehive/src/history/clipboard_history.dart';
import 'package:pastehive/src/shell/panel_controller.dart';
import 'package:pastehive/src/ui/panel_scene.dart';

import '../fakes.dart';

void main() {
  late FakeWindow window;
  late PanelController controller;
  late ClipboardHistory history;
  late List<ClipboardEntry> copied;

  Future<void> pumpScene(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(440, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: PanelScene(
              controller: controller,
              history: history,
              onCopy: copied.add,
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    window = FakeWindow();
    controller = PanelController(
      pointer: FakePointer(),
      window: window,
      pollInterval: const Duration(days: 1),
    )..start();
    history = historyWith(['one', 'two']);
    copied = [];
    addTearDown(controller.dispose);
  });

  testWidgets('opening slides the window to rest, with a slight overshoot', (
    tester,
  ) async {
    await pumpScene(tester);

    controller.toggle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(window.progress.last, lessThan(0.5));

    await tester.pumpAndSettle();

    expect(window.progress.last, closeTo(1, 1e-9));
    expect(window.progress.reduce((a, b) => a > b ? a : b), greaterThan(1));
    expect(window.visible, isTrue);
  });

  testWidgets('closing animates out before the window is hidden', (
    tester,
  ) async {
    await pumpScene(tester);
    controller.toggle();
    await tester.pumpAndSettle();

    controller.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(window.visible, isTrue);
    expect(window.progress.last, inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(window.visible, isFalse);
    expect(window.hideCount, 1);
  });

  testWidgets('reopening mid-exit turns the animation around', (tester) async {
    await pumpScene(tester);
    controller.toggle();
    await tester.pumpAndSettle();

    controller.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    controller.toggle();
    await tester.pumpAndSettle();

    expect(window.visible, isTrue);
    expect(window.hideCount, 0);
    expect(window.progress.last, closeTo(1, 1e-9));
  });

  testWidgets('with reduced motion the panel appears and disappears in place', (
    tester,
  ) async {
    await pumpScene(tester, reduceMotion: true);

    controller.toggle();
    await tester.pump();
    expect(window.progress, [1]);

    controller.dismiss();
    await tester.pump();
    expect(window.visible, isFalse);
    expect(window.progress.where((value) => value > 0 && value < 1), isEmpty);
  });

  testWidgets('each visit starts fresh, and picking an entry reports it', (
    tester,
  ) async {
    await pumpScene(tester);
    controller.toggle();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'two');
    await tester.pump();
    expect(find.text('one'), findsNothing);

    controller.dismiss();
    await tester.pumpAndSettle();
    controller.toggle();
    await tester.pumpAndSettle();

    expect(find.text('one'), findsOneWidget);
    await tester.tap(find.text('one'));
    expect(copied.single.text, 'one');
  });
}
