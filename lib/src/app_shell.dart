import 'dart:async';

import 'history/clipboard_entry.dart';
import 'history/clipboard_history.dart';
import 'platform/ports.dart';
import 'shell/panel_controller.dart';

/// The part of the app that keeps working while no window is on screen: it
/// records what is copied, owns the tray icon, and opens the panel.
class AppShell {
  AppShell({
    required this.history,
    required this.panel,
    required this._clipboard,
    required this._tray,
    required this._onQuit,
  });

  final ClipboardHistory history;
  final PanelController panel;
  final ClipboardPort _clipboard;
  final TrayPort _tray;
  final Future<void> Function() _onQuit;

  void Function()? _stopWatchingClipboard;
  Future<void> _lastCapture = Future.value();

  /// Whether the panel window could be set up.
  bool panelReady = false;

  /// Whether the tray icon went up.
  bool trayReady = false;

  Future<void> start() async {
    panelReady = panel.start();
    trayReady = _tray.install(
      TrayActions(
        onTogglePanel: panel.toggle,
        onPausedChanged: (paused) => history.paused = paused,
        onClearHistory: history.clearUnpinned,
        onQuit: () => unawaited(quit()),
      ),
    );
    // Pausing can come from anywhere; the tray menu's tick follows it.
    history.addListener(_syncTray);
    if (_clipboard.canWatch) {
      _stopWatchingClipboard = _clipboard.watch(_capture);
    }
    // Whatever is on the clipboard at launch belongs in the list too.
    _capture();
    await _lastCapture;
  }

  /// Puts [entry] back on the clipboard and closes the panel.
  void copy(ClipboardEntry entry) {
    _clipboard.writeText(entry.text);
    // The watcher reports this write as well; recording here keeps the entry
    // at the top even where the system cannot report changes.
    history.record(entry.text);
    panel.dismiss();
  }

  void _syncTray() => _tray.setPaused(history.paused);

  Future<void> quit() async {
    history.removeListener(_syncTray);
    _stopWatchingClipboard?.call();
    _stopWatchingClipboard = null;
    panel.stop();
    await history.flush();
    _tray.dispose();
    await _onQuit();
  }

  // Reads are chained so two quick copies are recorded in the order they
  // happened.
  void _capture() {
    _lastCapture = _lastCapture.then((_) async {
      final text = await _clipboard.readText();
      if (text != null) history.record(text);
    });
  }
}
