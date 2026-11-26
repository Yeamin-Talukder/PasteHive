import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synchronize_clipboard/src/history/clipboard_entry.dart';
import 'package:synchronize_clipboard/src/history/clipboard_history.dart';
import 'package:synchronize_clipboard/src/platform/ports.dart';
import 'package:synchronize_clipboard/src/shell/panel_controller.dart';
import 'package:synchronize_clipboard/src/ui/clipboard_panel.dart';
import 'package:synchronize_clipboard/src/ui/glass_shell.dart';
import 'package:synchronize_clipboard/src/ui/panel_scene.dart';
import 'package:synchronize_clipboard/src/ui/panel_surface.dart';

import '../fakes.dart';

const insets = EdgeInsets.fromLTRB(48, 8, 48, 72);
const windowSize = Size(536, 620);
const rest = Rect.fromLTWH(48, 8, 440, 540);

void main() {
  group('shape', () {
    test('is nothing while hidden and the whole panel at rest', () {
      expect(GlassShell.shapeAt(rest, 0), RRect.zero);
      expect(
        GlassShell.shapeAt(rest, 1),
        RRect.fromRectAndRadius(
          rest,
          const Radius.circular(GlassShell.cornerRadius),
        ),
      );
    });

    test('starts as a thin pill hanging from the top edge of the screen', () {
      final start = GlassShell.shapeAt(rest, 0.001);
      expect(start.width, closeTo(150, 2));
      expect(start.height, closeTo(10, 2));
      expect(start.center.dx, rest.center.dx);
      expect(start.top, lessThan(rest.top));
    });

    test('only grows on the way open, and stays centred', () {
      RRect? previous;
      for (var step = 1; step <= 100; step++) {
        final shape = GlassShell.shapeAt(rest, step / 100);
        expect(shape.center.dx, closeTo(rest.center.dx, 1e-9));
        if (previous != null) {
          expect(shape.width, greaterThanOrEqualTo(previous.width));
          expect(shape.bottom, greaterThanOrEqualTo(previous.bottom));
          expect(shape.tlRadiusX, greaterThanOrEqualTo(previous.tlRadiusX));
        }
        previous = shape;
      }
    });

    test('widens before it drops', () {
      final half = GlassShell.shapeAt(rest, 0.5);
      expect(half.width / rest.width, greaterThan(0.75));
      expect(half.height / rest.height, lessThan(0.6));
    });

    test('swells slightly past its rest size when the spring overshoots', () {
      final over = GlassShell.shapeAt(rest, 1.03);
      expect(over.width, greaterThan(rest.width));
      expect(over.bottom, greaterThan(rest.bottom));
      expect(over.tlRadiusX, GlassShell.cornerRadius);
    });
  });

  group('shell', () {
    late int outsideTaps;
    late int insideTaps;

    Future<void> pumpShell(WidgetTester tester, {double reveal = 1}) async {
      tester.view.physicalSize = windowSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      outsideTaps = 0;
      insideTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GlassShell(
            reveal: AlwaysStoppedAnimation(reveal),
            insets: insets,
            backdrop: null,
            onTapOutside: () => outsideTaps++,
            child: Center(
              child: TextButton(
                onPressed: () => insideTaps++,
                child: const Text('Inside'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('gives the content exactly the panel area', (tester) async {
      await pumpShell(tester);
      expect(tester.getCenter(find.text('Inside')), rest.center);
    });

    testWidgets(
      'a click on the margin counts as outside, one on the glass does not',
      (tester) async {
        await pumpShell(tester);

        await tester.tapAt(const Offset(10, 300));
        await tester.tapAt(const Offset(268, 600));
        expect(outsideTaps, 2);

        await tester.tap(find.text('Inside'));
        await tester.tapAt(rest.topLeft + const Offset(40, 40));
        expect(insideTaps, 1);
        expect(outsideTaps, 2);
      },
    );

    testWidgets('half-open glass cannot be clicked', (tester) async {
      await pumpShell(tester, reveal: 0.5);
      await tester.tap(find.text('Inside'), warnIfMissed: false);
      expect(insideTaps, 0);
    });

    testWidgets('the content keeps to the width of the glass while it opens', (
      tester,
    ) async {
      await pumpShell(tester, reveal: 0.4);
      final shape = GlassShell.shapeAt(rest, 0.4);
      // Other widgets on the way up use transforms too; ours is the one that
      // scales.
      final scales = tester
          .widgetList<Transform>(
            find.ancestor(
              of: find.text('Inside'),
              matching: find.byType(Transform),
            ),
          )
          // The horizontal scale: the first entry of the matrix.
          .map((transform) => transform.transform.entry(0, 0));
      expect(scales, contains(closeTo(shape.width / rest.width, 1e-9)));
    });

    testWidgets('views inside do not tint the glass a second time', (
      tester,
    ) async {
      tester.view.physicalSize = windowSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late bool inShell;
      await tester.pumpWidget(
        MaterialApp(
          home: GlassShell(
            reveal: const AlwaysStoppedAnimation(1),
            insets: insets,
            backdrop: null,
            onTapOutside: () {},
            child: PanelSurface(
              hasMaterial: true,
              builder: (context, palette) {
                inShell = GlassScope.isAround(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      expect(inShell, isTrue);
      final fills = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(PanelSurface),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => (box.decoration as BoxDecoration).color);
      expect(fills.first, const Color(0x00000000));
    });
  });

  group('a window that leaves the glass to the app', () {
    late FakeWindow window;
    late PanelController controller;
    late ClipboardHistory history;
    late List<BackdropCapture> prepared;

    final capture = BackdropCapture(bgra: Uint8List(4), width: 1, height: 1);

    Future<void> pumpScene(
      WidgetTester tester, {
      Future<ui.Image?> Function(BackdropCapture, double)? prepare,
    }) async {
      tester.view.physicalSize = windowSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PanelScene(
            controller: controller,
            history: history,
            onCopy: (ClipboardEntry _) {},
            prepareBackdrop:
                prepare ??
                (capture, _) async {
                  prepared.add(capture);
                  return null;
                },
          ),
        ),
      );
    }

    setUp(() {
      window = FakeWindow()..chromeInsets = insets;
      controller = PanelController(
        pointer: FakePointer(),
        window: window,
        pollInterval: const Duration(days: 1),
      )..start();
      history = historyWith(['one', 'two']);
      prepared = [];
      addTearDown(controller.dispose);
    });

    testWidgets('is drawn as glass inside the window, panel-sized', (
      tester,
    ) async {
      await pumpScene(tester);
      controller.open();
      await tester.pumpAndSettle();

      expect(find.byType(GlassShell), findsOneWidget);
      expect(tester.getRect(find.byType(ClipboardPanel)), rest);
      expect(controller.chromeInsets, insets);
    });

    testWidgets('opens straight away when no picture of the screen came back', (
      tester,
    ) async {
      await pumpScene(tester);
      controller.open();
      await tester.pumpAndSettle();

      expect(prepared, isEmpty);
      expect(find.text('one'), findsOneWidget);
    });

    testWidgets('waits for the backdrop before starting the entrance', (
      tester,
    ) async {
      window.backdropToReturn = capture;
      await pumpScene(tester);

      controller.open();
      await tester.pump();
      expect(prepared, [capture]);
      expect(controller.backdrop, same(capture));

      await tester.pumpAndSettle();
      expect(window.visible, isTrue);
      expect(find.text('one'), findsOneWidget);
    });

    testWidgets('still opens when the backdrop cannot be prepared', (
      tester,
    ) async {
      window.backdropToReturn = capture;
      await pumpScene(
        tester,
        prepare: (_, _) async => throw StateError('no image'),
      );

      controller.open();
      await tester.pumpAndSettle();

      expect(find.text('one'), findsOneWidget);
    });

    testWidgets('a click beside the panel closes it', (tester) async {
      await pumpScene(tester);
      controller.open();
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 300));
      expect(controller.isOpen, isFalse);

      await tester.pumpAndSettle();
      expect(window.visible, isFalse);
    });

    testWidgets('reopening mid-close turns the glass around', (tester) async {
      window.backdropToReturn = capture;
      await pumpScene(tester);
      controller.open();
      await tester.pumpAndSettle();
      controller.dismiss();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      controller.open();
      await tester.pumpAndSettle();

      expect(window.visible, isTrue);
      expect(window.hideCount, 0);
      expect(find.text('one'), findsOneWidget);
    });
  });
}
