import 'dart:async';

import 'package:flutter/foundation.dart';

import 'history/clipboard_entry.dart';
import 'history/clipboard_history.dart';
import 'history/image_vault.dart';
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
    this.images,
    this.captureAtLaunch = true,
    this.readRetryDelay = const Duration(milliseconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ClipboardHistory history;
  final PanelController panel;
  final SyncService sync;
  final ClipboardPort _clipboard;
  final TrayPort _tray;
  static const _readAttempts = 5;

  final Future<void> Function() _onQuit;
  final DateTime Function() _clock;

  /// How long to wait before reading the clipboard again after it refused;
  /// each further try waits this much longer.
  final Duration readRetryDelay;

  /// Where copied pictures are kept. Without it pictures are not recorded.
  final ImageVault? images;

  /// Whether whatever is on the clipboard when the app starts goes into the
  /// list. Off for a self-check, which must not show real clipboard content.
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

  /// Until when a picture appearing on the clipboard is this app's own,
  /// just put there, and must not be recorded as a new one. The system
  /// re-encodes pictures, so it could not be recognised by its bytes.
  DateTime _ownImageUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Completes when everything copied so far has been read and recorded.
  /// Recording a picture means writing a file, which takes a moment.
  Future<void> get captured async {
    Future<void> pending;
    do {
      pending = _lastCapture;
      await pending;
    } while (!identical(pending, _lastCapture));
  }

  /// Called with each step of [start] as it begins; for tracing a launch
  /// that stalls.
  void Function(String step)? trace;

  /// What went wrong the last time reading the clipboard failed, for
  /// diagnostics; null when it never has.
  String? lastCaptureError;

  /// Whether the panel window could be set up.
  bool panelReady = false;

  /// Whether the tray icon went up.
  bool trayReady = false;

  Future<void> start() async {
    trace?.call('preparing the panel window');
    panelReady = panel.start();
    trace?.call('installing the tray icon');
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
    trace?.call('watching the clipboard');
    // Pausing can come from anywhere; the tray menu's tick follows it.
    history.addListener(_syncTray);
    if (_clipboard.canWatch) {
      _stopWatchingClipboard = _clipboard.watch(_capture);
    }
    // Whatever is on the clipboard at launch belongs in the list too.
    if (captureAtLaunch) _capture();
    await _lastCapture;

    trace?.call('loading sync');
    _remoteClips = sync.remoteClips.listen(_applyRemote);
    // Another device asking to sync is put in front of the user at once.
    sync.onPairRequest = (_) => openSyncSettings();
    await sync.load();
  }

  /// Puts [entry] back on the clipboard, closes the panel and, where the
  /// system allows it, pastes it into whatever the user was working in.
  void copy(ClipboardEntry entry) {
    // The watcher reports these writes as well; recording here keeps things
    // working where the system cannot report changes.
    switch (entry.kind) {
      case EntryKind.image:
        _ownImageUntil = _clock().add(const Duration(seconds: 2));
        _clipboard.writeImage(entry.imagePath!);
        history.recordImage(
          path: entry.imagePath!,
          width: entry.imageWidth ?? 0,
          height: entry.imageHeight ?? 0,
          source: entry.source,
        );
      case EntryKind.files:
        _clipboard.writeFiles(entry.files);
        history.recordFiles(entry.files);
      case EntryKind.text ||
          EntryKind.link ||
          EntryKind.email ||
          EntryKind.color:
        _clipboard.writeText(entry.text);
        history.record(entry.text);
        _share(entry.text);
    }
    panel.dismiss();
    if (panel.canPaste) unawaited(panel.pasteIntoPreviousWindow());
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
    await removeUnusedImages();
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

  /// Deletes stored pictures that no entry refers to any more.
  Future<void> removeUnusedImages() async {
    await images?.removeAllExcept([
      for (final entry in history.entries)
        if (entry.imagePath != null) entry.imagePath!,
    ]);
  }

  // Reads are chained so two quick copies are recorded in the order they
  // happened.
  void _capture() {
    _lastCapture = _lastCapture.then((_) => _readWithRetries());
  }

  // Only one program can have the clipboard open at a time, and right after
  // a copy the one that made it (or another clipboard tool) often still
  // does, most of all for pictures. A refusal is usually over in a few
  // tens of milliseconds, so it is tried again before giving up.
  Future<void> _readWithRetries() async {
    for (var attempt = 1; ; attempt++) {
      try {
        await _read();
        return;
      } on Object catch (error) {
        if (attempt == _readAttempts) {
          lastCaptureError = '$error';
          debugPrint('Could not read the clipboard: $error');
          return;
        }
        await Future<void>.delayed(readRetryDelay * attempt);
      }
    }
  }

  // A clipboard can hold several forms of one thing at once. Files come
  // first (a copied file also carries its name as text), then text (a copied
  // spreadsheet cell also carries a picture of itself), then pictures.
  Future<void> _read() async {
    final files = await _clipboard.readFiles();
    if (files.isNotEmpty) {
      history.recordFiles(files);
      return;
    }
    final text = await _clipboard.readText();
    if (text != null && text.trim().isNotEmpty) {
      if (history.record(text)) _share(text);
      return;
    }
    final vault = images;
    if (vault == null || history.paused) return;
    if (_clock().isBefore(_ownImageUntil)) return;
    final image = await _clipboard.readImage();
    if (image == null) return;
    history.recordImage(
      path: await vault.store(image.png),
      width: image.width,
      height: image.height,
    );
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
