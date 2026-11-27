import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pastehive/src/history/clipboard_entry.dart';
import 'package:pastehive/src/history/clipboard_history.dart';
import 'package:pastehive/src/ui/clipboard_panel.dart';

import '../fakes.dart';

void main() {
  late ClipboardHistory history;
  late List<ClipboardEntry> copied;
  late int dismissals;

  DateTime now() => DateTime.utc(2026, 11, 26, 9, 30);

  Future<void> pumpPanel(WidgetTester tester, {int visit = 1}) async {
    tester.view.physicalSize = const Size(440, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ClipboardPanel(
          history: history,
          reveal: const AlwaysStoppedAnimation(1),
          visit: visit,
          hasMaterial: true,
          onCopy: copied.add,
          onDismiss: () => dismissals++,
          clock: now,
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets animations finish and timers (delayed saves, the undo toast) run
  /// out.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 6));

  List<String> shownTitles(WidgetTester tester) => [
    for (final entry in history.entries)
      if (find.text(entry.preview).evaluate().isNotEmpty) entry.preview,
  ];

  // Made here rather than in the tests, so the history's delayed-save timers
  // are real ones and not left-overs of a test's pretend clock.
  setUp(() {
    history = historyWith([
      'Plain note',
      'https://flutter.dev/docs',
      'Second note\nwith another line',
      'https://example.com/page',
    ]);
    copied = [];
    dismissals = 0;
  });

  group('filters', () {
    testWidgets('offers the basic filters, and others only when they apply', (
      tester,
    ) async {
      await pumpPanel(tester);
      for (final label in ['All', 'Pinned', 'Text', 'Links']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in ['Emails', 'Colors', 'Synced']) {
        expect(find.text(label), findsNothing, reason: label);
      }

      history
        ..record('someone@example.com')
        ..record('#1E90FF')
        ..record('from elsewhere', source: 'Mac');
      await tester.pump();

      // The row of filters scrolls sideways; some are past its edge.
      for (final label in ['Emails', 'Colors', 'Synced']) {
        expect(
          find.text(label, skipOffstage: false),
          findsOneWidget,
          reason: label,
        );
      }
      await settle(tester);
    });

    testWidgets('a filter narrows the list and the count', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('Links'));
      await tester.pump();

      expect(shownTitles(tester), [
        'https://example.com/page',
        'https://flutter.dev/docs',
      ]);
      expect(find.text('2 items'), findsOneWidget);

      // Choosing a filter scrolls the row to it; bring the next one back.
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Text', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Text'));
      await tester.pump();
      expect(shownTitles(tester), ['Second note', 'Plain note']);
      await settle(tester);
    });

    testWidgets('a filter and a search work together', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.text('Links'));
      await tester.enterText(find.byType(TextField), 'flutter');
      await tester.pump();

      expect(shownTitles(tester), ['https://flutter.dev/docs']);
      await settle(tester);
    });

    testWidgets('Tab moves to the next filter and Shift+Tab back', (
      tester,
    ) async {
      await pumpPanel(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.text('2 items'), findsOneWidget, reason: 'on Links');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(shownTitles(tester), ['Second note', 'Plain note']);

      // Past the last one (Links, then Images) it comes round to All again.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.text('4 items'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('an empty filter says so, and Escape leaves it', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.text('Pinned'));
      await tester.pump();
      expect(find.text('Nothing Here'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('4 items'), findsOneWidget);
      expect(dismissals, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(dismissals, 1);
      await settle(tester);
    });

    testWidgets('a new visit goes back to All', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.text('Links'));
      await tester.pump();

      await pumpPanel(tester, visit: 2);
      expect(find.text('4 items'), findsOneWidget);
      await settle(tester);
    });
  });

  group('groups', () {
    testWidgets('entries are listed under when they were copied', (
      tester,
    ) async {
      history.togglePin(history.entries.last.id);
      await pumpPanel(tester);

      expect(find.text('Pinned'), findsNWidgets(2), reason: 'chip and heading');
      expect(find.text('Today'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Plain note')).dy,
        lessThan(tester.getTopLeft(find.text('Today')).dy),
      );
      await settle(tester);
    });

    test('names the period an entry belongs to', () {
      final local = DateTime(2026, 11, 26, 14);
      ClipboardEntry at(DateTime time, {bool pinned = false}) =>
          ClipboardEntry(id: 'a', text: 'x', copiedAt: time, pinned: pinned);

      expect(sectionOf(at(DateTime(2026, 11, 26, 0, 5)), local), 'Today');
      expect(sectionOf(at(DateTime(2026, 11, 25, 23, 55)), local), 'Yesterday');
      expect(sectionOf(at(DateTime(2026, 11, 22)), local), 'This Week');
      expect(sectionOf(at(DateTime(2026, 11, 1)), local), 'Earlier');
      expect(
        sectionOf(at(DateTime(2026, 11, 1), pinned: true), local),
        'Pinned',
      );
    });
  });

  group('preview', () {
    testWidgets('Space shows the whole entry, and Space again closes it', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(find.text('Second note\nwith another line'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Copied 27 min ago'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsNothing);
      await settle(tester);
    });

    testWidgets('Space is still a space once a search has begun', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'note');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsNothing);
      await settle(tester);
    });

    testWidgets('the eye button opens it and Escape closes only it', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.byTooltip('Preview'));
      await tester.pumpAndSettle();
      expect(find.text('Link'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsNothing);
      expect(dismissals, 0);
      await settle(tester);
    });

    testWidgets('its buttons copy, pin and delete the entry', (tester) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();
      expect(history.entries.first.pinned, isTrue);
      expect(find.text('Unpin'), findsOneWidget);

      await tester.tap(find.text('Copy'));
      expect(copied.single.text, 'https://example.com/page');

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(history.entries, hasLength(3));
      expect(find.text('Copy'), findsNothing, reason: 'the preview closed');
      await settle(tester);
    });

    testWidgets('names where a synced entry came from', (tester) async {
      history.record('from the laptop', source: 'Sam’s MacBook');
      await pumpPanel(tester);
      expect(find.textContaining('from Sam’s MacBook'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.textContaining('from Sam’s MacBook'), findsNWidgets(2));
      await settle(tester);
    });
  });

  group('deleting', () {
    testWidgets('can be undone from the toast', (tester) async {
      await pumpPanel(tester);
      final removed = history.entries.first;

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(history.entries, hasLength(3));
      expect(find.text('Entry deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(history.entries.first, removed);
      expect(find.text('Entry deleted'), findsNothing);
      await settle(tester);
    });

    testWidgets('can be undone from the keyboard', (tester) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(history.entries, hasLength(4));
      await settle(tester);
    });

    testWidgets('the chance to undo passes after a few seconds', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Entry deleted'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Entry deleted'), findsNothing);
      expect(history.entries, hasLength(3));
    });

    testWidgets('the Delete key belongs to the search field while typing', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'note');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(history.entries, hasLength(4));
      await settle(tester);
    });
  });

  group('shortcuts', () {
    testWidgets('Ctrl+P pins the selected entry', (tester) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(history.entries.first.preview, 'Second note');
      expect(history.entries.first.pinned, isTrue);
      await settle(tester);
    });
  });

  group('feedback', () {
    testWidgets('the copied row shows a check mark', (tester) async {
      await pumpPanel(tester);
      expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(copied, hasLength(1));
      expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
      await settle(tester);
    });
  });

  group('pictures and files', () {
    testWidgets('are listed with their size or where they live', (
      tester,
    ) async {
      history
        ..recordImage(path: r'C:\gone\abc.png', width: 1920, height: 1080)
        ..recordFiles([r'C:\Docs\report.pdf']);
      await pumpPanel(tester);

      expect(find.text('Image'), findsOneWidget);
      expect(find.textContaining('1920 × 1080'), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.textContaining('in Docs'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('have filters: Images always, Files once there are some', (
      tester,
    ) async {
      await pumpPanel(tester);
      expect(find.text('Images', skipOffstage: false), findsOneWidget);
      expect(find.text('Files', skipOffstage: false), findsNothing);

      history
        ..recordImage(path: r'C:\gone\abc.png', width: 10, height: 10)
        ..recordFiles([r'C:\Docs\a.txt', r'C:\Docs\b.txt']);
      await tester.pump();
      expect(find.text('Files', skipOffstage: false), findsOneWidget);

      await tester.ensureVisible(find.text('Images', skipOffstage: false));
      await tester.tap(find.text('Images'));
      await tester.pump();
      expect(find.text('1 item'), findsOneWidget);
      expect(find.text('Image'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('choosing one reports it like any other entry', (tester) async {
      history.recordImage(path: r'C:\gone\abc.png', width: 10, height: 10);
      await pumpPanel(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(copied.single.kind, EntryKind.image);
      await settle(tester);
    });

    testWidgets('a file entry previews as the list of paths', (tester) async {
      history.recordFiles([r'C:\Docs\a.txt', r'C:\Docs\b.txt']);
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(
        find.text('Files', skipOffstage: false),
        findsNWidgets(2),
        reason: 'chip and title',
      );
      expect(find.text('C:\\Docs\\a.txt\nC:\\Docs\\b.txt'), findsOneWidget);
      await settle(tester);
    });

    test('notes on pictures and files', () {
      ClipboardEntry entry({
        String? imagePath,
        int? width,
        int? height,
        List<String> files = const [],
      }) => ClipboardEntry(
        id: 'a',
        text: files.join('\n'),
        copiedAt: now(),
        imagePath: imagePath,
        imageWidth: width,
        imageHeight: height,
        files: files,
      );

      expect(
        describeEntry(entry(imagePath: 'a.png', width: 640, height: 480)),
        '640 × 480',
      );
      expect(describeEntry(entry(imagePath: 'a.png')), 'Picture');
      expect(describeEntry(entry(files: ['/home/sam/notes.txt'])), 'in sam');
      expect(describeEntry(entry(files: ['/a/b', '/a/c', '/a/d'])), '3 items');
      expect(kindLabel(EntryKind.image), 'Image');
    });
  });

  group('key hint', () {
    Future<void> pumpWith(WidgetTester tester, {required bool pastes}) async {
      tester.view.physicalSize = const Size(440, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ClipboardPanel(
            history: history,
            reveal: const AlwaysStoppedAnimation(1),
            visit: 1,
            hasMaterial: true,
            onCopy: copied.add,
            onDismiss: () {},
            pastesOnSelect: pastes,
            clock: now,
          ),
        ),
      );
    }

    testWidgets('says Paste where picking an entry pastes it', (tester) async {
      await pumpWith(tester, pastes: true);
      expect(find.textContaining('Enter Paste'), findsOneWidget);
    });

    testWidgets('says Copy where it only copies', (tester) async {
      await pumpWith(tester, pastes: false);
      expect(find.textContaining('Enter Copy'), findsOneWidget);
    });
  });

  group('kinds', () {
    testWidgets('a colour is shown as the colour itself', (tester) async {
      history.record('#1E90FF');
      await pumpPanel(tester);

      final swatch = tester.widgetList<Container>(find.byType(Container)).where(
        (container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              decoration.color == const Color(0xFF1E90FF);
        },
      );
      expect(swatch, hasLength(1));
      expect(find.textContaining('· Color'), findsOneWidget);
      await settle(tester);
    });

    test('notes on each kind', () {
      ClipboardEntry entry(String text) =>
          ClipboardEntry(id: 'a', text: text, copiedAt: now());
      expect(describeEntry(entry('a@b.co')), 'Email address');
      expect(describeEntry(entry('#fff')), 'Color');
      expect(kindLabel(EntryKind.email), 'Email Address');
    });
  });
}
