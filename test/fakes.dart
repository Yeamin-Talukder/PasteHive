import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;
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
  int showCount = 0;

  /// What [show] hands back, as a real window that draws its own glass does.
  BackdropCapture? backdropToReturn;

  @override
  EdgeInsets chromeInsets = EdgeInsets.zero;
  void Function()? _onBlur;

  /// Pretends the user clicked another window.
  void blur() => _onBlur?.call();

  @override
  bool prepare() => prepared = canPrepare;

  @override
  BackdropCapture? show(Rect frame) {
    this.frame = frame;
    visible = true;
    showCount++;
    return backdropToReturn;
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
  bool canPaste = false;

  int pasteCount = 0;

  @override
  Future<bool> pasteIntoPreviousWindow() async {
    if (!canPaste) return false;
    pasteCount++;
    return true;
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
  List<String> files = const [];
  ClipboardImage? image;

  /// What reading the clipboard gives after an image was written to it. A
  /// real clipboard re-encodes pictures, so it need not be the same bytes.
  ClipboardImage? imageWrittenBack;

  final List<String> written = [];
  final List<String> writtenImages = [];
  final List<List<String>> writtenFiles = [];
  final List<void Function()> _watchers = [];

  @override
  final bool canWatch;

  bool get isWatched => _watchers.isNotEmpty;

  /// Pretends another app copied [value].
  void copyFromElsewhere(String value) {
    text = value;
    files = const [];
    image = null;
    _notify();
  }

  /// Pretends another app copied a picture.
  void copyImageFromElsewhere(ClipboardImage value) {
    text = null;
    files = const [];
    image = value;
    _notify();
  }

  /// Pretends files were copied in a file manager.
  void copyFilesFromElsewhere(List<String> paths) {
    text = null;
    image = null;
    files = paths;
    _notify();
  }

  void _notify() {
    for (final watcher in List.of(_watchers)) {
      watcher();
    }
  }

  @override
  void Function() watch(void Function() onChanged) {
    _watchers.add(onChanged);
    return () => _watchers.remove(onChanged);
  }

  /// How many reads are still to be refused, as a real clipboard does while
  /// another program has it open.
  int busyReads = 0;

  void _refuseIfBusy() {
    if (busyReads > 0) {
      busyReads--;
      throw StateError('Clipboard operation failed');
    }
  }

  @override
  Future<String?> readText() async {
    _refuseIfBusy();
    return text;
  }

  @override
  Future<List<String>> readFiles() async {
    _refuseIfBusy();
    return files;
  }

  @override
  Future<ClipboardImage?> readImage() async => image;

  @override
  bool writeImage(String path) {
    writtenImages.add(path);
    text = null;
    files = const [];
    image = imageWrittenBack;
    _notify();
    return true;
  }

  @override
  bool writeFiles(List<String> paths) {
    writtenFiles.add(paths);
    text = null;
    image = null;
    files = paths;
    _notify();
    return true;
  }

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
