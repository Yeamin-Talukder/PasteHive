import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pastehive/src/history/clipboard_entry.dart';
import 'package:pastehive/src/history/clipboard_history.dart';
import 'package:pastehive/src/ui/clipboard_panel.dart';

import '../fakes.dart';

/// Lets timers started during a test run out: the history's delayed save and
/// the tooltip that waits under a resting pointer.
Future<void> settle(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 1));

void main() {
  late ClipboardHistory history;
  late List<ClipboardEntry> copied;
  late int dismissals;

  // Ten minutes after the last entry recorded by historyWith's clock.
  DateTime now() => DateTime.utc(2026, 11, 26, 9, 13);

  Future<void> pumpPanel(
    WidgetTester tester, {
    int visit = 1,
    Animation<double> reveal = const AlwaysStoppedAnimation(1),
    Brightness brightness = Brightness.dark,
    bool hasMaterial = true,
    MediaQueryData? mediaQuery,
  }) async {
    tester.view.physicalSize = const Size(440, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget panel = ClipboardPanel(
      history: history,
      reveal: reveal,
      visit: visit,
      hasMaterial: hasMaterial,
      onCopy: copied.add,
      onDismiss: () => dismissals++,
      clock: now,
    );
    if (mediaQuery != null) {
      panel = MediaQuery(data: mediaQuery, child: panel);
    }
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: brightness),
        home: panel,
      ),
    );
    await tester.pump();
  }

  setUp(() {
    history = historyWith([
      'Meeting notes\nsecond line\nthird line',
      'https://flutter.dev/docs',
      'Flight BA 117',
    ]);
    copied = [];
    dismissals = 0;
  });

  group('list', () {
    testWidgets('shows what was copied, newest first, with a note on each', (
      tester,
    ) async {
      await pumpPanel(tester);

      final rows = [
        for (final text in [
          'Flight BA 117',
          'https://flutter.dev/docs',
          'Meeting notes',
        ])
          tester.getTopLeft(find.text(text)).dy,
      ];
      expect(rows, orderedEquals(List.of(rows)..sort()));

      expect(find.text('10 min ago · 13 characters'), findsOneWidget);
      expect(find.text('11 min ago · flutter.dev'), findsOneWidget);
      expect(find.text('12 min ago · 3 lines'), findsOneWidget);
      expect(find.text('3 items'), findsOneWidget);
    });

    testWidgets('says so when nothing has been copied', (tester) async {
      history = historyWith([]);
      await pumpPanel(tester);

      expect(find.text('Nothing Copied Yet'), findsOneWidget);
      expect(find.text('0 items'), findsOneWidget);
    });

    testWidgets('picks up new copies while open', (tester) async {
      await pumpPanel(tester);
      history.record('Fresh');
      await tester.pump();

      expect(find.text('Fresh'), findsOneWidget);
      expect(find.text('4 items'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('shows that capturing is paused', (tester) async {
      history.paused = true;
      await pumpPanel(tester);
      expect(find.text('Capturing Paused'), findsOneWidget);
    });

    testWidgets('clicking a row copies it', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.text('https://flutter.dev/docs'));
      expect(copied.single.text, 'https://flutter.dev/docs');
    });
  });

  group('search', () {
    testWidgets('typing narrows the list', (tester) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'flight');
      await tester.pump();

      expect(find.text('Flight BA 117'), findsOneWidget);
      expect(find.text('Meeting notes'), findsNothing);
      expect(find.text('1 item'), findsOneWidget);
    });

    testWidgets('says when nothing matches', (tester) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.pump();

      expect(find.text('No Results'), findsOneWidget);
      expect(find.textContaining('“zebra”'), findsOneWidget);
    });

    testWidgets('the clear button empties the field', (tester) async {
      await pumpPanel(tester);
      expect(find.byTooltip('Clear Search'), findsNothing);

      await tester.enterText(find.byType(TextField), 'flight');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear Search'));
      await tester.pump();

      expect(find.text('Meeting notes'), findsOneWidget);
      expect(find.byTooltip('Clear Search'), findsNothing);
    });

    testWidgets('a new visit starts with an empty search', (tester) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'flight');
      await tester.pump();

      await pumpPanel(tester, visit: 2);

      expect(find.text('Meeting notes'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
    });
  });

  group('keyboard', () {
    testWidgets('Return copies the first row', (tester) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(copied.single.text, 'Flight BA 117');
    });

    testWidgets('arrows move the selection and stop at the ends', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(copied.single.text, 'https://flutter.dev/docs');
    });

    testWidgets('Return copies the first match of a search', (tester) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'notes');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(copied.single.preview, 'Meeting notes');
    });

    testWidgets('Return does nothing when the list is empty', (tester) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(copied, isEmpty);
    });

    testWidgets('Escape clears a search first, then closes', (tester) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'flight');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(dismissals, 0);
      expect(find.text('Meeting notes'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(dismissals, 1);
    });

    testWidgets('keeps the selected row in view in a long list', (
      tester,
    ) async {
      history = historyWith([for (var i = 1; i <= 30; i++) 'Entry number $i']);
      await pumpPanel(tester);
      expect(find.text('Entry number 1'), findsNothing);

      for (var i = 0; i < 29; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.pump();

      expect(find.text('Entry number 1'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(copied.single.text, 'Entry number 1');
      await settle(tester);
    });
  });

  group('row actions', () {
    testWidgets('appear on the selected row and follow the pointer', (
      tester,
    ) async {
      await pumpPanel(tester);
      expect(find.byTooltip('Pin'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Meeting notes')));
      await tester.pump();

      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();

      expect(find.text('Meeting notes'), findsNothing);
      expect(history.entries, hasLength(2));
      expect(
        copied,
        isEmpty,
        reason: 'the button, not the row, took the click',
      );
      await settle(tester);
    });

    testWidgets('pin moves a row to the top and marks it', (tester) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      await tester.tap(find.byTooltip('Pin'));
      await tester.pump();

      expect(history.entries.first.preview, 'Meeting notes');
      expect(history.entries.first.pinned, isTrue);
      expect(find.byIcon(CupertinoIcons.pin_fill), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.tap(find.byTooltip('Unpin'));
      await tester.pump();
      expect(history.entries.first.preview, 'Flight BA 117');
      await settle(tester);
    });
  });

  group('entrance', () {
    testWidgets('rows fade in one after another', (tester) async {
      final reveal = AnimationController(
        vsync: tester,
        duration: const Duration(seconds: 1),
      );
      addTearDown(reveal.dispose);
      await pumpPanel(tester, reveal: reveal);

      double opacityOf(String text) => tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text(text), matching: find.byType(Opacity))
                .first,
          )
          .opacity;

      expect(opacityOf('Flight BA 117'), 0);

      reveal.value = 0.3;
      await tester.pump();
      final first = opacityOf('Flight BA 117');
      final third = opacityOf('Meeting notes');
      expect(first, inExclusiveRange(0, 1));
      expect(third, lessThan(first));

      reveal.value = 1;
      await tester.pump();
      expect(
        find.ancestor(
          of: find.text('Flight BA 117'),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });
  });

  group('appearance', () {
    Color surfaceColor(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(ClipboardPanel),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color!;
    }

    testWidgets('is translucent over a system material', (tester) async {
      await pumpPanel(tester);
      expect(surfaceColor(tester).a, lessThan(1));
    });

    testWidgets('is opaque without a material', (tester) async {
      await pumpPanel(tester, hasMaterial: false);
      expect(surfaceColor(tester).a, 1);
    });

    testWidgets('is opaque when more contrast is asked for', (tester) async {
      await pumpPanel(
        tester,
        brightness: Brightness.light,
        mediaQuery: const MediaQueryData(
          size: Size(440, 540),
          highContrast: true,
        ),
      );
      expect(surfaceColor(tester).a, 1);
    });

    testWidgets('fits at the largest text size without overflowing', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        mediaQuery: const MediaQueryData(
          size: Size(440, 540),
          textScaler: TextScaler.linear(2),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Flight BA 117'), findsOneWidget);
    });
  });

  group('wording', () {
    final base = DateTime.utc(2026, 11, 26, 12);
    String ago(Duration elapsed) => relativeTime(base.subtract(elapsed), base);

    test('relative times', () {
      expect(ago(const Duration(seconds: 20)), 'Just now');
      expect(ago(const Duration(seconds: 50)), '1 min ago');
      expect(ago(const Duration(minutes: 59)), '59 min ago');
      expect(ago(const Duration(hours: 5)), '5 hr ago');
      expect(ago(const Duration(hours: 30)), 'Yesterday');
      expect(ago(const Duration(days: 3)), '3 days ago');
      expect(
        relativeTime(DateTime(2026, 3, 9, 12), DateTime(2026, 11, 26)),
        '9 Mar 2026',
      );
    });

    test('entry notes', () {
      ClipboardEntry entry(String text) =>
          ClipboardEntry(id: 'a', text: text, copiedAt: base);
      expect(describeEntry(entry('x')), '1 character');
      expect(describeEntry(entry('  hello ')), '5 characters');
      expect(describeEntry(entry('a\nb')), '2 lines');
      expect(describeEntry(entry('https://example.com/a?b=c')), 'example.com');
    });
  });
}
