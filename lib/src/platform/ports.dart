/// The desktop services this app depends on.
///
/// Everything that touches the operating system goes through one of these, so
/// the logic and the UI can be tested without a desktop. The real ones are in
/// `native_ports.dart`.
library;

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;

/// The system clipboard. Plain text only for now.
abstract interface class ClipboardPort {
  /// Whether the system can tell us when the clipboard changes.
  bool get canWatch;

  /// Calls [onChanged] every time the clipboard's content changes, including
  /// changes made by this app. Returns a function that stops watching.
  void Function() watch(void Function() onChanged);

  /// The text on the clipboard, or null when it holds none.
  Future<String?> readText();

  /// Puts [text] on the clipboard. Returns false when the system refused.
  bool writeText(String text);
}

/// One screen, in logical desktop coordinates (origin at the top left of the
/// primary display, y growing downwards).
class DisplayGeometry {
  const DisplayGeometry({required this.bounds, required this.workArea});

  /// The whole screen.
  final Rect bounds;

  /// The screen minus the menu bar, Dock or taskbar.
  final Rect workArea;

  @override
  bool operator ==(Object other) =>
      other is DisplayGeometry &&
      other.bounds == bounds &&
      other.workArea == workArea;

  @override
  int get hashCode => Object.hash(bounds, workArea);

  @override
  String toString() => 'DisplayGeometry($bounds, workArea: $workArea)';
}

/// Where the pointer and the screens are.
abstract interface class PointerPort {
  /// The pointer, in the same coordinates as [DisplayGeometry].
  Offset cursorPosition();

  List<DisplayGeometry> displays();
}

/// A picture of the screen where the panel's window is about to appear:
/// four bytes per pixel in BGRA order, top row first.
class BackdropCapture {
  const BackdropCapture({
    required this.bgra,
    required this.width,
    required this.height,
  });

  final Uint8List bgra;
  final int width;
  final int height;
}

/// The app's one window, used as the clipboard panel.
///
/// There are two ways the panel gets its looks. Where the system can draw a
/// translucent material behind a window that is not the active one (macOS),
/// the window is the panel: [chromeInsets] is zero and [hasMaterial] is
/// true. Elsewhere (Windows) the window is a transparent sheet somewhat
/// larger than the panel, and the app draws the panel on it, glass, corners
/// and shadow included, over the picture [show] returns.
abstract interface class PanelWindowPort {
  /// Makes the window a floating, frameless panel that stays out of the
  /// taskbar. Call once before anything else. Returns false when there is no
  /// window to work with.
  bool prepare();

  /// Whether the system draws a translucent material behind the content.
  bool get hasMaterial;

  /// How much larger than the panel the window is on each side, to leave
  /// room for the shadow the app draws. Zero when the system draws the
  /// panel's shape and shadow.
  EdgeInsets get chromeInsets;

  /// Puts the window on screen for a panel resting at [frame], at the start
  /// of its entrance. Returns a picture of what was on screen there just
  /// before, where the app draws its own glass and could take one.
  BackdropCapture? show(Rect frame);

  /// Moves the window along its entrance: [progress] 0 is just off its
  /// resting place and 1 is at [frame]. Values past 1 overshoot. Does
  /// nothing where the app animates the panel inside a still window.
  void applyRevealProgress(Rect frame, double progress);

  void hide();

  /// Calls [onBlur] when the window stops being the one receiving keys.
  /// Returns a function that stops listening.
  void Function() watchBlur(void Function() onBlur);
}

/// What the tray icon and its menu can ask for.
class TrayActions {
  const TrayActions({
    required this.onTogglePanel,
    required this.onOpenSyncSettings,
    required this.onPausedChanged,
    required this.onClearHistory,
    required this.onQuit,
  });

  final void Function() onTogglePanel;
  final void Function() onOpenSyncSettings;
  final void Function(bool paused) onPausedChanged;
  final void Function() onClearHistory;
  final void Function() onQuit;
}

/// The icon in the Windows notification area or the macOS menu bar.
abstract interface class TrayPort {
  /// Puts the icon up. Returns false when the system has no tray.
  bool install(TrayActions actions);

  /// Reflects whether capturing is paused in the menu.
  void setPaused(bool paused);

  void dispose();
}
