import 'dart:ui';

import 'package:synchronize_clipboard/src/history/clipboard_history.dart';
import 'package:synchronize_clipboard/src/history/history_store.dart';
import 'package:synchronize_clipboard/src/platform/ports.dart';

/// A 1440x900 screen with a 25 px menu bar, like a MacBook.
const laptop = DisplayGeometry(
  bounds: Rect.fromLTWH(0, 0, 1440, 900),
  workArea: Rect.fromLTWH(0, 25, 1440, 875),
);

/// A second screen to the right of [laptop], with a taskbar at the bottom.
const external = DisplayGeometry(
  bounds: Rect.fromLTWH(1440, 0, 1920, 1080),
  workArea: Rect.fromLTWH(1440, 0, 1920, 1040),
);

class FakePointer implements PointerPort {
  FakePointer({
    this.cursor = const Offset(700, 500),
    List<DisplayGeometry>? all,
  }) : all = all ?? [laptop];

  Offset cursor;
  List<DisplayGeometry> all;
  int displayQueries = 0;

  @override
  Offset cursorPosition() => cursor;

  @override
  List<DisplayGeometry> displays() {
    displayQueries++;
    return all;
  }
}

class FakeWindow implements PanelWindowPort {
  FakeWindow({this.canPrepare = true, this.hasMaterial = true});

  final bool canPrepare;

  @override
  final bool hasMaterial;

  bool prepared = false;
  bool visible = false;
  Rect? frame;
  final List<double> progress = [];
  int hideCount = 0;
  void Function()? _onBlur;

  /// Pretends the user clicked another window.
  void blur() => _onBlur?.call();

  @override
  bool prepare() => prepared = canPrepare;

  @override
  void show(Rect frame) {
    this.frame = frame;
    visible = true;
  }

  @override
  void applyRevealProgress(Rect frame, double progress) {
    this.frame = frame;
    this.progress.add(progress);
  }

  @override
  void hide() {
    visible = false;
    hideCount++;
  }

  @override
  void Function() watchBlur(void Function() onBlur) {
    _onBlur = onBlur;
    return () => _onBlur = null;
  }
}

class FakeClipboard implements ClipboardPort {
  FakeClipboard({this.text, this.canWatch = true});

  String? text;
  final List<String> written = [];
  final List<void Function()> _watchers = [];

  @override
  final bool canWatch;

  bool get isWatched => _watchers.isNotEmpty;

  /// Pretends another app copied [value].
  void copyFromElsewhere(String value) {
    text = value;
    for (final watcher in List.of(_watchers)) {
      watcher();
    }
  }

  @override
  void Function() watch(void Function() onChanged) {
    _watchers.add(onChanged);
    return () => _watchers.remove(onChanged);
  }

  @override
  Future<String?> readText() async => text;

  @override
  bool writeText(String text) {
    written.add(text);
    copyFromElsewhere(text);
    return true;
  }
}

class FakeTray implements TrayPort {
  FakeTray({this.supported = true});

  final bool supported;
  TrayActions? actions;
  bool? paused;
  bool disposed = false;

  @override
  bool install(TrayActions actions) {
    if (!supported) return false;
    this.actions = actions;
    return true;
  }

  @override
  void setPaused(bool paused) => this.paused = paused;

  @override
  void dispose() => disposed = true;
}

/// A clock that moves forward one minute every time it is read, so entries
/// recorded one after another have distinct, ordered times.
DateTime Function() tickingClock([DateTime? start]) {
  var now = start ?? DateTime.utc(2026, 11, 26, 9);
  return () {
    now = now.add(const Duration(minutes: 1));
    return now;
  };
}

/// A history that saves immediately and keeps its entries in memory.
ClipboardHistory historyWith(
  List<String> texts, {
  MemoryHistoryStore? store,
  DateTime Function()? clock,
}) {
  final history = ClipboardHistory(
    store: store ?? MemoryHistoryStore(),
    clock: clock ?? tickingClock(),
    saveDelay: Duration.zero,
  );
  texts.forEach(history.record);
  return history;
}
