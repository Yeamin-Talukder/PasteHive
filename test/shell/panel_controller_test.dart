import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:synchronize_clipboard/src/shell/hot_edge.dart';
import 'package:synchronize_clipboard/src/shell/panel_controller.dart';

import '../fakes.dart';

const topMiddle = Offset(720, 0);
const midScreen = Offset(300, 600);
const insidePanel = Offset(720, 300);

void main() {
  late FakePointer pointer;
  late FakeWindow window;
  late PanelController controller;
  late Duration now;
  late int notifications;

  const config = HotEdgeConfig();

  PanelController build(FakeWindow fakeWindow) {
    return PanelController(
      pointer: pointer,
      window: fakeWindow,
      tracker: HotEdgeTracker(config: config),
      clock: () => now,
      // The tests drive poll() themselves.
      pollInterval: const Duration(days: 1),
    );
  }

  void pollAfter(int milliseconds, [Offset? cursor]) {
    now += Duration(milliseconds: milliseconds);
    if (cursor != null) pointer.cursor = cursor;
    controller.poll();
  }

  setUp(() {
    now = Duration.zero;
    notifications = 0;
    pointer = FakePointer(all: [laptop, external]);
    window = FakeWindow();
    controller = build(window)..addListener(() => notifications++);
    addTearDown(controller.dispose);
  });

  test('start prepares the window and reports whether it worked', () {
    expect(controller.start(), isTrue);
    expect(window.prepared, isTrue);
    expect(controller.hasMaterial, isTrue);

    final broken = build(FakeWindow(canPrepare: false));
    addTearDown(broken.dispose);
    expect(broken.start(), isFalse);
    broken
      ..poll()
      ..toggle();
    expect(broken.isOpen, isFalse);
  });

  test('resting the pointer at the top middle puts the window on screen', () {
    controller.start();
    pollAfter(0, topMiddle);
    expect(controller.isOpen, isFalse);
    expect(window.visible, isFalse);

    pollAfter(200);

    expect(controller.isOpen, isTrue);
    expect(controller.openCount, 1);
    expect(window.visible, isTrue);
    expect(window.frame, config.panelFrame(laptop));
    expect(notifications, 1);
  });

  test('the window follows the animation the UI reports', () {
    controller.start();
    pollAfter(0, topMiddle);
    pollAfter(200);

    controller
      ..setRevealProgress(0.25)
      ..setRevealProgress(1);

    expect(window.progress, [0.25, 1]);
    expect(window.frame, config.panelFrame(laptop));
  });

  test('the window leaves the screen only after the closing animation', () {
    controller.start();
    pollAfter(0, topMiddle);
    pollAfter(200);
    pollAfter(50, insidePanel);

    pollAfter(50, midScreen);
    pollAfter(400);

    expect(controller.isOpen, isFalse);
    expect(window.visible, isTrue, reason: 'still animating out');
    expect(notifications, 2);

    controller
      ..setRevealProgress(0.4)
      ..didFinishDismiss();
    expect(window.visible, isFalse);
    expect(window.hideCount, 1);

    // Nothing more to hide or move.
    controller
      ..didFinishDismiss()
      ..setRevealProgress(0.1);
    expect(window.hideCount, 1);
    expect(window.progress, [0.4]);
  });

  test('reopening before the closing animation ends keeps the window', () {
    controller.start();
    pollAfter(0, topMiddle);
    pollAfter(200);
    controller.dismiss();

    pollAfter(50, midScreen);
    pollAfter(50, topMiddle);
    pollAfter(200);
    controller.didFinishDismiss();

    expect(controller.isOpen, isTrue);
    expect(controller.openCount, 2);
    expect(window.visible, isTrue);
    expect(window.hideCount, 0);
  });

  test(
    'dismiss closes, and the pointer must leave the strip before it reopens',
    () {
      controller.start();
      pollAfter(0, topMiddle);
      pollAfter(200);

      controller.dismiss();
      expect(controller.isOpen, isFalse);

      pollAfter(1000);
      expect(controller.isOpen, isFalse);

      pollAfter(50, midScreen);
      pollAfter(50, topMiddle);
      pollAfter(200);
      expect(controller.isOpen, isTrue);
    },
  );

  test('clicking another window closes the panel', () {
    controller.start();
    pollAfter(0, topMiddle);
    pollAfter(200);

    now += const Duration(milliseconds: 100);
    window.blur();
    expect(
      controller.isOpen,
      isTrue,
      reason: 'focus settling just after opening',
    );

    now += const Duration(milliseconds: 400);
    window.blur();
    expect(controller.isOpen, isFalse);
  });

  group('toggle', () {
    test('opens on the screen the pointer is on', () {
      controller.start();
      pointer.cursor = const Offset(3000, 1060);

      controller.toggle();

      expect(controller.isOpen, isTrue);
      expect(window.frame, config.panelFrame(external));
    });

    test('stays open while the pointer is still away at the tray', () {
      controller.start();
      pointer.cursor = const Offset(1400, 10);
      controller.toggle();

      pollAfter(5000);
      expect(controller.isOpen, isTrue);

      pollAfter(50, insidePanel);
      pollAfter(50, midScreen);
      pollAfter(400);
      expect(controller.isOpen, isFalse);
    });

    test('closes an open panel', () {
      controller.start();
      controller
        ..toggle()
        ..toggle();
      expect(controller.isOpen, isFalse);
    });

    test('does nothing when there are no screens', () {
      controller.start();
      pointer.all = [];
      controller.toggle();
      expect(controller.isOpen, isFalse);
    });
  });

  test('asks for the screens again only now and then', () {
    controller.start();
    for (var i = 0; i < 100; i++) {
      pollAfter(50, midScreen);
    }
    expect(pointer.displayQueries, inInclusiveRange(2, 4));
  });

  test('the window starts its entrance a little above its resting place', () {
    const frame = Rect.fromLTWH(500, 33, 440, 540);
    expect(
      panelOriginAt(frame, 0),
      const Offset(500, 33 - kPanelSlideDistance),
    );
    expect(panelOriginAt(frame, 1), const Offset(500, 33));
    expect(panelOriginAt(frame, 1.1).dy, greaterThan(33));
  });
}
