import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

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
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Future<void> _lastCapture = Future.value();
  Future<void> _lastShare = Future.value();
  int _lastOpenCount = 0;
  bool _openingSyncSettings = false;

  /// The text this device and the others last agreed is on the clipboard.
  /// Text equal to it is not sent again, which is what stops a copy bouncing
  /// back and forth between two devices for ever.
  String? _sharedText;

  /// The same for pictures: the file name of the one last sent or received.
  /// Pictures are named after their contents, so it is the same everywhere.
  String? _sharedImage;

  /// Until when a picture appearing on the clipboard is this app's own,
  /// just put there, and must not be recorded as a new one. The system
  /// re-encodes pictures, so it could not be recognised by its bytes.
  DateTime _ownImageUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Completes when everything copied so far has been read and recorded.
  /// Recording a picture means writing a file, which takes a moment.
  Future<void> get captured async {
    Future<void> capture;
    Future<void> share;
    do {
      capture = _lastCapture;
      share = _lastShare;
      await capture;
      await share;
    } while (!identical(capture, _lastCapture) ||
        !identical(share, _lastShare));
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
    _subscriptions
      ..add(sync.remoteDeletes.listen(history.removeRemote))
      ..add(sync.remoteImages.listen(_applyRemoteImage))
      ..add(
        sync.remoteImageDeletes.listen((name) {
          _forgetSharedImage(name);
          history.removeRemoteImage(name);
        }),
      )
      ..add(sync.remoteClears.listen((_) => history.clearRemote()))
      ..add(
        sync.remoteHistory.listen(
          (entry) => history.mergeRemote(
            entry.text,
            entry.copiedAt,
            source: entry.fromName,
          ),
        ),
      );
    // What the user removes or brings back here happens on the other
    // devices too. Only text travels, so only text entries are passed on.
    history
      ..onRemoved = (entry) {
        if (_isText(entry)) {
          sync.sendDelete(entry.text);
        } else if (entry.imagePath != null) {
          final name = path.basename(entry.imagePath!);
          _forgetSharedImage(name);
          sync.sendImageDelete(name);
        }
      }
      ..onRestored = (entry) {
        if (_isText(entry)) {
          sync.sendHistory([_item(entry)]);
        } else if (entry.imagePath != null) {
          // Forget that the others had it, or it would not be sent again.
          _sharedImage = null;
          _queueImageShare(entry);
        }
      }
      ..onCleared = sync.sendClear;
    // A device joining for the first time can be given what is already
    // here, if the user has asked for that.
    sync.onNewDevice = (peer) {
      if (sync.shareHistory) shareHistory(to: peer.id);
    };
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
        _queueImageShare(entry);
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

  /// Sends this device's text history to the device [to], or to every
  /// connected device when [to] is null.
  void shareHistory({String? to}) {
    sync.sendHistory([
      for (final entry in history.entries)
        if (_isText(entry)) _item(entry),
    ], to: to);
  }

  static bool _isText(ClipboardEntry entry) =>
      entry.kind != EntryKind.image && entry.kind != EntryKind.files;

  static HistoryItem _item(ClipboardEntry entry) =>
      (text: entry.text, copiedAt: entry.copiedAt);

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
    await captured;
    await _remoteClips?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    history
      ..onRemoved = null
      ..onRestored = null
      ..onCleared = null;
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
    final stored = await vault.store(image.png);
    final recorded = history.recordImage(
      path: stored,
      width: image.width,
      height: image.height,
    );
    if (recorded) {
      _sendImage(
        path.basename(stored),
        image.png,
        width: image.width,
        height: image.height,
      );
    }
  }

  // Once a picture is deleted it is no longer "the one the devices share":
  // if it comes back, it has to be accepted and sent like a new one.
  void _forgetSharedImage(String name) {
    if (_sharedImage == name) _sharedImage = null;
  }

  // Reading a picture back from disk takes a moment; the reads are chained
  // so they finish in order and [captured] can wait for them.
  void _queueImageShare(ClipboardEntry entry) {
    _lastShare = _lastShare.then((_) => _shareImage(entry));
  }

  // Sends the stored picture of [entry] to the other devices.
  Future<void> _shareImage(ClipboardEntry entry) async {
    final file = File(entry.imagePath!);
    try {
      _sendImage(
        path.basename(file.path),
        await file.readAsBytes(),
        width: entry.imageWidth ?? 0,
        height: entry.imageHeight ?? 0,
      );
    } on FileSystemException catch (error) {
      debugPrint('Could not read a picture to send it: $error');
    }
  }

  void _sendImage(
    String name,
    Uint8List png, {
    required int width,
    required int height,
  }) {
    // The same picture twice in a row is not sent twice, which is also what
    // keeps one from bouncing between two devices.
    if (history.paused || name == _sharedImage) return;
    _sharedImage = name;
    _sharedText = null;
    if (!sync.sendImage(png, width: width, height: height)) {
      debugPrint('A picture was too large to send to the other devices.');
    }
  }

  Future<void> _applyRemoteImage(RemoteImage image) async {
    final vault = images;
    // Paused means paused in both directions.
    if (vault == null || history.paused) return;
    final stored = await vault.store(image.png);
    final name = path.basename(stored);
    if (name == _sharedImage) return;
    _sharedImage = name;
    _sharedText = null;
    // The clipboard will report this write; it is not a new copy.
    _ownImageUntil = _clock().add(const Duration(seconds: 2));
    _clipboard.writeImage(stored);
    history.recordImage(
      path: stored,
      width: image.width,
      height: image.height,
      source: image.fromName,
    );
  }

  void _share(String text) {
    if (history.paused || text == _sharedText) return;
    _sharedText = text;
    _sharedImage = null;
    sync.sendClip(text);
  }

  void _applyRemote(RemoteClip clip) {
    // Paused means paused in both directions.
    if (history.paused || clip.text == _sharedText) return;
    _sharedText = clip.text;
    _sharedImage = null;
    _clipboard.writeText(clip.text);
    history.record(clip.text, source: clip.fromName);
  }
}
