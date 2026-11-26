/// The desktop services this app depends on.
///
/// Everything that touches the operating system goes through one of these, so
/// the logic and the UI can be tested without a desktop. The real ones are in
/// `native_ports.dart`.
library;

import 'dart:ui';

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

/// The app's one window, used as the clipboard panel.
abstract interface class PanelWindowPort {
  /// Makes the window a floating, frameless panel that stays out of the
  /// taskbar. Call once before anything else. Returns false when there is no
  /// window to work with.
  bool prepare();

  /// Whether the system draws a translucent material behind the content. When
  /// false the content has to paint its own opaque background.
  bool get hasMaterial;

  /// Puts the window on screen at the start of its entrance, where
  /// [applyRevealProgress] with 0 would leave it.
  void show(Rect frame);

  /// Moves the window along its entrance: [progress] 0 is just off its
  /// resting place and 1 is at [frame]. Values past 1 overshoot.
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
    required this.onPausedChanged,
    required this.onClearHistory,
    required this.onQuit,
  });

  final void Function() onTogglePanel;
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
