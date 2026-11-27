import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pastehive/src/platform/ports.dart';
import 'package:pastehive/src/shell/hot_edge.dart';

import '../fakes.dart';

const config = HotEdgeConfig(
  panelSize: Size(440, 540),
  zoneWidth: 320,
  zoneDepth: 2,
  panelTopGap: 8,
  keepOpenMargin: 16,
  dwell: Duration(milliseconds: 140),
  leaveGrace: Duration(milliseconds: 320),
);

Duration ms(int value) => Duration(milliseconds: value);

const topMiddle = Offset(720, 0);
const midScreen = Offset(300, 600);
const insidePanel = Offset(720, 300);

void main() {
  group('layout', () {
    test('the strip is centred on the very top of the screen', () {
      expect(config.hotZone(laptop), const Rect.fromLTWH(560, 0, 320, 2));
      expect(config.hotZone(external), const Rect.fromLTWH(2240, 0, 320, 2));
    });

    test('the panel is centred just under the top of the work area', () {
      expect(config.panelFrame(laptop), const Rect.fromLTWH(500, 33, 440, 540));
      expect(
        config.panelFrame(external),
        const Rect.fromLTWH(2180, 8, 440, 540),
      );
    });

    test('the panel shrinks to fit a small screen', () {
      const small = DisplayGeometry(
        bounds: Rect.fromLTWH(0, 0, 400, 300),
        workArea: Rect.fromLTWH(0, 0, 400, 260),
      );
      expect(config.panelFrame(small), const Rect.fromLTWH(0, 8, 400, 244));
    });

    test('the keep-open area reaches from the panel up to the screen top', () {
      expect(
        config.keepOpenRegion(laptop),
        const Rect.fromLTRB(484, 0, 956, 589),
      );
    });
  });

  group('opening', () {
    late HotEdgeTracker tracker;

    HotEdgeAction at(Offset cursor, int time) => tracker.update(
      cursor: cursor,
      displays: [laptop, external],
      now: ms(time),
    );

    setUp(() => tracker = HotEdgeTracker(config: config));

    test('needs the pointer to rest in the strip', () {
      expect(at(topMiddle, 0), HotEdgeAction.none);
      expect(at(topMiddle, 100), HotEdgeAction.none);
      expect(at(topMiddle, 140), HotEdgeAction.reveal);
      expect(tracker.isOpen, isTrue);
      expect(tracker.panelFrame, config.panelFrame(laptop));
    });

    test('does not open for a pointer passing along the top edge', () {
      expect(at(const Offset(400, 0), 0), HotEdgeAction.none);
      expect(at(topMiddle, 50), HotEdgeAction.none);
      expect(at(const Offset(1000, 0), 100), HotEdgeAction.none);
      expect(at(const Offset(1000, 0), 500), HotEdgeAction.none);
      expect(tracker.isOpen, isFalse);
    });

    test('leaving the strip restarts the wait', () {
      at(topMiddle, 0);
      at(midScreen, 100);
      expect(at(topMiddle, 130), HotEdgeAction.none);
      expect(at(topMiddle, 260), HotEdgeAction.none);
      expect(at(topMiddle, 270), HotEdgeAction.reveal);
    });

    test('does not open below the strip or beside it', () {
      for (final cursor in const [
        Offset(720, 3),
        Offset(559, 0),
        Offset(881, 0),
      ]) {
        at(cursor, 0);
        expect(at(cursor, 1000), HotEdgeAction.none, reason: '$cursor');
      }
    });

    test('opens on whichever screen the pointer is on', () {
      const externalTopMiddle = Offset(2400, 0);
      at(externalTopMiddle, 0);
      expect(at(externalTopMiddle, 200), HotEdgeAction.reveal);
      expect(tracker.display, external);
      expect(tracker.panelFrame, config.panelFrame(external));
    });

    test('moving to another screen while waiting restarts the wait', () {
      at(topMiddle, 0);
      expect(at(const Offset(2400, 0), 139), HotEdgeAction.none);
      expect(at(const Offset(2400, 0), 200), HotEdgeAction.none);
      expect(at(const Offset(2400, 0), 280), HotEdgeAction.reveal);
      expect(tracker.display, external);
    });
  });

  group('closing', () {
    late HotEdgeTracker tracker;

    HotEdgeAction at(Offset cursor, int time) =>
        tracker.update(cursor: cursor, displays: [laptop], now: ms(time));

    setUp(() {
      tracker = HotEdgeTracker(config: config);
      at(topMiddle, 0);
      at(topMiddle, 200);
    });

    test(
      'stays open while the pointer travels from the strip to the panel',
      () {
        // Across the menu bar and the gap above the panel.
        for (final (index, y) in const [
          0.0,
          12.0,
          25.0,
          30.0,
          33.0,
          300.0,
        ].indexed) {
          expect(at(Offset(720, y), 300 + index * 400), HotEdgeAction.none);
        }
        expect(tracker.isOpen, isTrue);
      },
    );

    test('closes once the pointer has been away for the grace period', () {
      expect(at(insidePanel, 300), HotEdgeAction.none);
      expect(at(midScreen, 400), HotEdgeAction.none);
      expect(at(midScreen, 700), HotEdgeAction.none);
      expect(at(midScreen, 720), HotEdgeAction.dismiss);
      expect(tracker.isOpen, isFalse);
    });

    test('coming back within the grace period keeps it open', () {
      at(midScreen, 400);
      expect(at(insidePanel, 600), HotEdgeAction.none);
      expect(at(midScreen, 700), HotEdgeAction.none);
      expect(at(midScreen, 1000), HotEdgeAction.none);
      expect(at(midScreen, 1020), HotEdgeAction.dismiss);
    });

    test('the margin around the panel still counts as inside', () {
      expect(at(const Offset(950, 580), 400), HotEdgeAction.none);
      expect(at(const Offset(950, 580), 5000), HotEdgeAction.none);
      expect(at(const Offset(960, 580), 5100), HotEdgeAction.none);
      expect(at(const Offset(960, 580), 5420), HotEdgeAction.dismiss);
    });

    test('can open again after closing', () {
      at(midScreen, 400);
      at(midScreen, 800);
      expect(tracker.isOpen, isFalse);

      at(topMiddle, 1000);
      expect(at(topMiddle, 1200), HotEdgeAction.reveal);
    });

    test('closed with the pointer still in the strip, it waits for the pointer to leave', () {
      tracker.close();
      expect(at(topMiddle, 300), HotEdgeAction.none);
      expect(at(topMiddle, 2000), HotEdgeAction.none);

      at(midScreen, 2100);
      at(topMiddle, 2200);
      expect(at(topMiddle, 2400), HotEdgeAction.reveal);
    });
  });

  group('opened from the tray', () {
    late HotEdgeTracker tracker;

    HotEdgeAction at(Offset cursor, int time) =>
        tracker.update(cursor: cursor, displays: [laptop], now: ms(time));

    setUp(() => tracker = HotEdgeTracker(config: config)..open(laptop));

    test('stays open while the pointer has not reached the panel yet', () {
      const tray = Offset(1400, 10);
      expect(at(tray, 0), HotEdgeAction.none);
      expect(at(tray, 10000), HotEdgeAction.none);
      expect(tracker.isOpen, isTrue);
    });

    test('closes normally once the pointer has been inside', () {
      at(insidePanel, 0);
      at(midScreen, 100);
      expect(at(midScreen, 420), HotEdgeAction.dismiss);
    });
  });
}
