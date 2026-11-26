import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../platform/ports.dart';
import 'hot_edge.dart';

/// Opens and closes the clipboard panel.
///
/// It watches the pointer for the top-middle gesture, puts the window on
/// screen, and tells the UI (through [isOpen]) which way to animate. The UI
/// reports back with [setRevealProgress] while it animates and
/// [didFinishDismiss] when the closing animation is over, which is when the
/// window actually leaves the screen.
class PanelController extends ChangeNotifier {
  PanelController({
    required this._pointer,
    required this._window,
    HotEdgeTracker? tracker,
    Duration Function()? clock,
    this.pollInterval = const Duration(milliseconds: 50),
    this.blurGuard = const Duration(milliseconds: 250),
  }) : _tracker = tracker ?? HotEdgeTracker(),
       _clock = clock ?? _stopwatchClock();

  /// Screens rarely change; asking for them on every poll would be wasteful.
  static const _displayRefreshTicks = 40;

  final PointerPort _pointer;
  final PanelWindowPort _window;
  final HotEdgeTracker _tracker;
  final Duration Function() _clock;

  /// How often the pointer position is sampled.
  final Duration pollInterval;

  /// Losing focus this soon after opening is the system settling, not the
  /// user clicking elsewhere, and does not close the panel.
  final Duration blurGuard;

  Timer? _timer;
  void Function()? _stopWatchingBlur;
  List<DisplayGeometry> _displays = const [];
  int _ticksUntilDisplayRefresh = 0;
  bool _prepared = false;
  bool _isOpen = false;
  bool _windowOnScreen = false;
  bool _holdOpen = false;
  int _openCount = 0;
  Duration _openedAt = Duration.zero;

  /// Whether the panel should be showing. The UI animates towards this.
  bool get isOpen => _isOpen;

  /// Goes up by one every time the panel opens, so the UI can start each
  /// visit fresh (empty search, first row selected).
  int get openCount => _openCount;

  /// Whether the system paints a translucent material behind the panel.
  bool get hasMaterial => _window.hasMaterial;

  /// While true, the panel stays open when the pointer leaves it or another
  /// window is clicked; only [dismiss] closes it. For views the user types
  /// in, where closing by accident would throw the typing away.
  bool get holdOpen => _holdOpen;

  set holdOpen(bool value) {
    if (_holdOpen == value) return;
    _holdOpen = value;
    final display = _tracker.display;
    if (!value && _isOpen && display != null) {
      // Back to closing when the pointer leaves, counted from the next time
      // it is inside: it may be anywhere right now.
      _tracker.open(display);
    }
  }

  /// Prepares the window and starts watching the pointer. Returns false when
  /// there is no window to use, in which case nothing is watched.
  bool start() {
    if (_timer != null) return _prepared;
    _prepared = _window.prepare();
    if (!_prepared) return false;
    _stopWatchingBlur = _window.watchBlur(_onBlur);
    _timer = Timer.periodic(pollInterval, (_) => poll());
    return true;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopWatchingBlur?.call();
    _stopWatchingBlur = null;
  }

  /// Samples the pointer once. Called by the timer; public for tests.
  void poll() {
    if (!_prepared || (_holdOpen && _isOpen)) return;
    if (_displays.isEmpty || _ticksUntilDisplayRefresh-- <= 0) {
      _refreshDisplays();
    }
    final action = _tracker.update(
      cursor: _pointer.cursorPosition(),
      displays: _displays,
      now: _clock(),
    );
    switch (action) {
      case HotEdgeAction.reveal:
        _reveal();
      case HotEdgeAction.dismiss:
        _markClosed();
      case HotEdgeAction.none:
        break;
    }
  }

  /// Opens the panel if it is closed and closes it if it is open, as a click
  /// on the tray icon does.
  void toggle() {
    if (_isOpen) {
      dismiss();
    } else {
      open();
    }
  }

  /// Opens the panel without the gesture. Does nothing if it is open.
  void open() {
    if (!_prepared || _isOpen) return;
    _refreshDisplays();
    if (_displays.isEmpty) return;
    final cursor = _pointer.cursorPosition();
    final display = _displays.firstWhere(
      (display) => display.bounds.contains(cursor),
      orElse: () => _displays.first,
    );
    _tracker.open(display);
    _reveal();
  }

  /// Closes the panel, as Escape, a click elsewhere or picking an entry does.
  void dismiss() {
    if (!_isOpen) return;
    _tracker.close();
    _markClosed();
  }

  /// Called by the UI on every frame of the opening and closing animation.
  void setRevealProgress(double progress) {
    final frame = _tracker.panelFrame;
    if (frame == null || !_windowOnScreen) return;
    _window.applyRevealProgress(frame, progress);
  }

  /// Called by the UI when the closing animation has finished.
  void didFinishDismiss() {
    if (_isOpen || !_windowOnScreen) return;
    _windowOnScreen = false;
    _window.hide();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  void _reveal() {
    final frame = _tracker.panelFrame;
    if (frame == null) return;
    _isOpen = true;
    _openCount++;
    _openedAt = _clock();
    _windowOnScreen = true;
    _window.show(frame);
    notifyListeners();
  }

  void _markClosed() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }

  void _onBlur() {
    if (!_isOpen || _holdOpen) return;
    if (_clock() - _openedAt < blurGuard) return;
    dismiss();
  }

  void _refreshDisplays() {
    _displays = _pointer.displays();
    _ticksUntilDisplayRefresh = _displayRefreshTicks;
  }

  static Duration Function() _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}

/// How far above its resting place the panel starts its entrance.
const double kPanelSlideDistance = 22;

/// The window origin for [progress] along the entrance to [frame].
Offset panelOriginAt(Rect frame, double progress) {
  return Offset(frame.left, frame.top - (1 - progress) * kPanelSlideDistance);
}
