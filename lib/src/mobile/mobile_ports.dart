/// The phone's versions of the services the app depends on.
///
/// A phone differs from a computer in three ways that matter here. An app
/// cannot watch the clipboard: it may only read it while it is on screen.
/// There is no tray icon and no floating panel: the app is a screen like any
/// other. And the system stops an app in the background unless it holds a
/// visible notification saying what it is doing.
library;

import 'dart:async';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/services.dart';

import '../platform/ports.dart';

/// The app's own bit of Android code, reached over a method channel: the
/// phone's name, the notification that keeps sync alive, and text handed
/// over from other apps with Share.
class PhoneBridge {
  PhoneBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') {
        final text = call.arguments;
        if (text is String) onSharedText?.call(text);
      }
    });
  }

  static const _channel = MethodChannel('pastehive/phone');

  /// Called with text another app shared to this one while it was running.
  void Function(String text)? onSharedText;

  /// The phone's model name, for other devices to show.
  Future<String> deviceName() async {
    try {
      final name = await _channel.invokeMethod<String>('deviceName');
      if (name != null && name.trim().isNotEmpty) return name.trim();
    } on PlatformException {
      // Fall through to the generic name.
    } on MissingPluginException {
      // Running somewhere without the Android side, such as a test.
    }
    return 'Phone';
  }

  /// Tells the Android side the app is ready for text, and takes whatever
  /// was copied or shared before it was: when a copy starts the app, the
  /// text is here. Each is handed over once.
  Future<List<String>> takeSharedTexts() async {
    final texts = await _invoke<List<Object?>>('takeSharedTexts');
    return [...?texts?.whereType<String>()];
  }

  /// Whether the user has switched on, in Android's accessibility settings,
  /// the service that notices a tap on Copy and sends the clipboard by
  /// itself.
  Future<bool> autoCopyOn() async => await _invoke<bool>('autoCopyOn') ?? false;

  /// Opens Android's accessibility settings, where that service is switched
  /// on or off.
  Future<void> openAutoCopySettings() => _invoke<void>('openAutoCopySettings');

  /// Opens Android's page for this app, where a setting Android has
  /// restricted is allowed.
  Future<void> openAppInfo() => _invoke<void>('openAppInfo');

  /// The text on the phone's clipboard; null when the system will not show
  /// it, as when the app is not in front.
  Future<String?> readClipboard() => _invoke<String>('readClipboard');

  /// Puts [text] on the phone's clipboard.
  Future<void> writeClipboard(String text) =>
      _invoke<void>('writeClipboard', text);

  /// Shows the notification that lets sync keep running while the app is
  /// not on screen, or takes it down.
  Future<void> setKeepAlive(bool on) =>
      _invoke<void>(on ? 'startKeepAlive' : 'stopKeepAlive');

  Future<T?> _invoke<T>(String method, [Object? argument]) async {
    try {
      return await _channel.invokeMethod<T>(method, argument);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// The phone's clipboard: text only, and readable only while the app is on
/// screen.
///
/// It goes through the app's own Android code. Flutter's clipboard calls
/// answer only while the app has a screen, and this app also runs without
/// one: a call made then would never return.
class PhoneClipboard implements ClipboardPort {
  const PhoneClipboard(this.bridge);

  final PhoneBridge bridge;

  // The system does not report clipboard changes to apps; the app looks
  // each time it comes to the front instead.
  @override
  bool get canWatch => false;

  @override
  void Function() watch(void Function() onChanged) => () {};

  @override
  Future<String?> readText() => bridge.readClipboard();

  @override
  Future<List<String>> readFiles() async => const [];

  @override
  Future<ClipboardImage?> readImage() async => null;

  @override
  bool writeText(String text) {
    unawaited(bridge.writeClipboard(text));
    return true;
  }

  // Pictures and files are shown in the list but cannot be put on the
  // phone's clipboard from here yet.
  @override
  bool writeImage(String path) => false;

  @override
  bool writeFiles(List<String> paths) => false;
}

/// There is no pointer to follow on a phone.
class NoPointer implements PointerPort {
  const NoPointer();

  @override
  Offset cursorPosition() => Offset.zero;

  @override
  List<DisplayGeometry> displays() => const [];
}

/// The phone app is an ordinary full screen; there is no panel window to
/// show, hide or move.
class NoPanelWindow implements PanelWindowPort {
  const NoPanelWindow();

  @override
  bool prepare() => true;

  @override
  bool get hasMaterial => false;

  @override
  EdgeInsets get chromeInsets => EdgeInsets.zero;

  @override
  BackdropCapture? show(Rect frame) => null;

  @override
  void applyRevealProgress(Rect frame, double progress) {}

  @override
  void hide() {}

  @override
  bool get canPaste => false;

  @override
  Future<bool> pasteIntoPreviousWindow() async => false;

  @override
  void Function() watchBlur(void Function() onBlur) => () {};
}

/// A phone has no tray.
class NoTray implements TrayPort {
  const NoTray();

  @override
  bool install(TrayActions actions) => false;

  @override
  void setPaused(bool paused) {}

  @override
  void dispose() {}
}
