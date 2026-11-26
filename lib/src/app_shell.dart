import 'dart:async';

import 'package:flutter/foundation.dart';

import 'history/clipboard_entry.dart';
import 'history/clipboard_history.dart';
import 'platform/ports.dart';
import 'shell/panel_controller.dart';
import 'sync/sync_service.dart';

/// Which of the panel's views is showing.
enum PanelPage { history, sync }

/// The part of the app that keeps working while no window is on screen: it
/// records what is copied, carries it to and from the other devices, owns the
/// tray icon, and opens the panel.
class AppShell {
  AppShell({
    required this.history,
    required this.panel,
    required this.sync,
    required this._clipboard,
    required this._tray,
    required this._onQuit,
    this.captureAtLaunch = true,
  });

  /// Whether whatever is on the clipboard when the app starts goes into the
  /// list. Off for a self-check, which must not show real clipboard content.

  final ClipboardHistory history;
  final PanelController panel;
  final SyncService sync;
  final ClipboardPort _clipboard;
  final TrayPort _tray;
  final Future<void> Function() _onQuit;
  final bool captureAtLaunch;

  /// The view the panel shows. It goes back to the list each time the panel
  /// is opened by the gesture.
  final ValueNotifier<PanelPage> page = ValueNotifier(PanelPage.history);

  void Function()? _stopWatchingClipboard;
  StreamSubscription<RemoteClip>? _remoteClips;
  Future<void> _lastCapture = Future.value();
  int _lastOpenCount = 0;
  bool _openingSyncSettings = false;

  /// The text this device and the others last agreed is on the clipboard.
  /// Text equal to it is not sent again, which is what stops a copy bouncing
  /// back and forth between two devices for ever.
  String? _sharedText;

  /// Whether the panel window could be set up.
  bool panelReady = false;

  /// Whether the tray icon went up.
  bool trayReady = false;

  Future<void> start() async {
    panelReady = panel.start();
    panel.addListener(_onPanelChanged);
    page.addListener(_onPageChanged);
    trayReady = _tray.install(
      TrayActions(
        onTogglePanel: panel.toggle,
        onOpenSyncSettings: openSyncSettings,
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
    if (captureAtLaunch) _capture();
    await _lastCapture;

    _remoteClips = sync.remoteClips.listen(_applyRemote);
    await sync.load();
  }

  /// Puts [entry] back on the clipboard and closes the panel.
  void copy(ClipboardEntry entry) {
    _clipboard.writeText(entry.text);
    // The watcher reports this write as well; doing it here keeps things
    // working where the system cannot report changes.
    history.record(entry.text);
    _share(entry.text);
    panel.dismiss();
  }

  /// Opens the panel on its sync settings.
  void openSyncSettings() {
    _openingSyncSettings = true;
    page.value = PanelPage.sync;
    panel.open();
    _openingSyncSettings = false;
  }

  Future<void> quit() async {
    history.removeListener(_syncTray);
    panel.removeListener(_onPanelChanged);
    page.removeListener(_onPageChanged);
    _stopWatchingClipboard?.call();
    _stopWatchingClipboard = null;
    await _remoteClips?.cancel();
    await sync.shutdown();
    panel.stop();
    await history.flush();
    _tray.dispose();
    await _onQuit();
  }

  void _syncTray() => _tray.setPaused(history.paused);

  void _onPanelChanged() {
    if (panel.openCount == _lastOpenCount) return;
    _lastOpenCount = panel.openCount;
    // A fresh visit starts on the list, unless it was opened for settings.
    if (!_openingSyncSettings) page.value = PanelPage.history;
  }

  // Typing a key with the panel closing whenever the pointer drifts off
  // would be maddening, so the settings view pins the panel open.
  void _onPageChanged() => panel.holdOpen = page.value == PanelPage.sync;

  // Reads are chained so two quick copies are recorded in the order they
  // happened.
  void _capture() {
    _lastCapture = _lastCapture.then((_) async {
      final text = await _clipboard.readText();
      if (text == null) return;
      if (history.record(text)) _share(text);
    });
  }

  void _share(String text) {
    if (history.paused || text == _sharedText) return;
    _sharedText = text;
    sync.sendClip(text);
  }

  void _applyRemote(RemoteClip clip) {
    // Paused means paused in both directions.
    if (history.paused || clip.text == _sharedText) return;
    _sharedText = clip.text;
    _clipboard.writeText(clip.text);
    history.record(clip.text, source: clip.fromName);
  }
}
