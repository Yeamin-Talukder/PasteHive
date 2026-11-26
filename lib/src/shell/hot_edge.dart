import 'dart:ui';

import '../platform/ports.dart';

/// Sizes and timings of the "push the pointer to the top middle" gesture.
class HotEdgeConfig {
  const HotEdgeConfig({
    this.panelSize = const Size(440, 540),
    this.zoneWidth = 320,
    this.zoneDepth = 2,
    this.panelTopGap = 8,
    this.keepOpenMargin = 16,
    this.dwell = const Duration(milliseconds: 140),
    this.leaveGrace = const Duration(milliseconds: 320),
  });

  final Size panelSize;

  /// Width of the strip at the top middle of a screen that opens the panel.
  final double zoneWidth;

  /// How far below the very top of the screen the strip reaches.
  final double zoneDepth;

  /// Space between the top of the work area and the panel.
  final double panelTopGap;

  /// How far outside the panel the pointer may wander before it counts as
  /// having left.
  final double keepOpenMargin;

  /// How long the pointer must rest in the strip. Stops a pointer that is only
  /// passing along the top edge from opening the panel.
  final Duration dwell;

  /// How long the pointer must stay away before the panel closes.
  final Duration leaveGrace;

  /// The strip that opens the panel on [display].
  Rect hotZone(DisplayGeometry display) {
    final width = zoneWidth.clamp(0.0, display.bounds.width);
    return Rect.fromLTWH(
      display.bounds.center.dx - width / 2,
      display.bounds.top,
      width,
      zoneDepth,
    );
  }

  /// Where the panel rests on [display]: centred, just under the top of the
  /// work area, and shortened if the screen is small.
  Rect panelFrame(DisplayGeometry display) {
    final work = display.workArea;
    final width = panelSize.width.clamp(0.0, work.width);
    final height = panelSize.height.clamp(
      0.0,
      (work.height - panelTopGap * 2).clamp(0.0, double.infinity),
    );
    return Rect.fromLTWH(
      display.bounds.center.dx - width / 2,
      work.top + panelTopGap,
      width,
      height,
    );
  }

  /// The area the pointer can be in without the panel closing: the panel with
  /// a margin, stretched up to the top of the screen so the trip from the
  /// strip down to the panel (across a menu bar, say) does not close it.
  Rect keepOpenRegion(DisplayGeometry display) {
    final frame = panelFrame(display).inflate(keepOpenMargin);
    return Rect.fromLTRB(
      frame.left,
      display.bounds.top,
      frame.right,
      frame.bottom,
    );
  }
}

/// What the tracker wants done after an [HotEdgeTracker.update].
enum HotEdgeAction { none, reveal, dismiss }

/// Decides when the panel opens and closes from where the pointer is.
///
/// It only decides; showing and hiding the window is the caller's job. Time
/// is passed in so the rules can be tested without waiting.
class HotEdgeTracker {
  HotEdgeTracker({this.config = const HotEdgeConfig()});

  final HotEdgeConfig config;

  DisplayGeometry? _display;
  Duration? _armedAt;
  Duration? _leftAt;
  bool _open = false;

  /// Opened from the tray: the pointer is nowhere near the panel yet, so
  /// leaving does not count until it has been inside once.
  bool _awaitingFirstEntry = false;

  /// Set when the panel closes with the pointer still in the strip, so it
  /// does not pop straight back open.
  bool _mustLeaveZone = false;

  bool get isOpen => _open;

  /// The screen the panel is on, or is about to open on.
  DisplayGeometry? get display => _display;

  /// Where the panel rests while open.
  Rect? get panelFrame {
    final display = _display;
    return display == null ? null : config.panelFrame(display);
  }

  /// Feeds the tracker the pointer position at time [now].
  HotEdgeAction update({
    required Offset cursor,
    required List<DisplayGeometry> displays,
    required Duration now,
  }) {
    return _open
        ? _updateOpen(cursor, now)
        : _updateClosed(cursor, displays, now);
  }

  /// Opens the panel on [display] without the gesture, as the tray icon does.
  void open(DisplayGeometry display) {
    _display = display;
    _open = true;
    _awaitingFirstEntry = true;
    _armedAt = null;
    _leftAt = null;
  }

  /// Marks the panel closed, as Escape or a click elsewhere does.
  void close() {
    _open = false;
    _awaitingFirstEntry = false;
    _armedAt = null;
    _leftAt = null;
    _mustLeaveZone = true;
  }

  HotEdgeAction _updateClosed(
    Offset cursor,
    List<DisplayGeometry> displays,
    Duration now,
  ) {
    final display = _displayUnder(cursor, displays);
    final inZone =
        display != null && _contains(config.hotZone(display), cursor);

    if (!inZone) {
      _armedAt = null;
      _mustLeaveZone = false;
      return HotEdgeAction.none;
    }
    if (_mustLeaveZone) return HotEdgeAction.none;

    if (_armedAt == null || _display != display) {
      _armedAt = now;
      _display = display;
    }
    if (now - _armedAt! < config.dwell) return HotEdgeAction.none;

    _open = true;
    _awaitingFirstEntry = false;
    _armedAt = null;
    _leftAt = null;
    return HotEdgeAction.reveal;
  }

  HotEdgeAction _updateOpen(Offset cursor, Duration now) {
    final inside = _contains(config.keepOpenRegion(_display!), cursor);
    if (inside) {
      _awaitingFirstEntry = false;
      _leftAt = null;
      return HotEdgeAction.none;
    }
    if (_awaitingFirstEntry) return HotEdgeAction.none;

    _leftAt ??= now;
    if (now - _leftAt! < config.leaveGrace) return HotEdgeAction.none;

    close();
    // The pointer is outside the panel and so outside the strip as well.
    _mustLeaveZone = false;
    return HotEdgeAction.dismiss;
  }

  static DisplayGeometry? _displayUnder(
    Offset cursor,
    List<DisplayGeometry> displays,
  ) {
    for (final display in displays) {
      if (_contains(display.bounds, cursor)) return display;
    }
    return null;
  }

  /// Like [Rect.contains], but counting the right and bottom edges too: a
  /// pointer pinned against a screen edge reports the edge coordinate itself.
  static bool _contains(Rect rect, Offset point) {
    return point.dx >= rect.left &&
        point.dx <= rect.right &&
        point.dy >= rect.top &&
        point.dy <= rect.bottom;
  }
}
