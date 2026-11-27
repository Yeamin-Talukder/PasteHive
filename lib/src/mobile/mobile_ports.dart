/// The phone's versions of the services the app depends on.
///
/// A phone differs from a computer in three ways that matter here. An app
/// cannot watch the clipboard: it may only read it while it is on screen.
/// There is no tray icon and no floating panel: the app is a screen like any
/// other. And the system stops an app in the background unless it holds a
/// visible notification saying what it is doing.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/services.dart';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../platform/ports.dart';
import '../update/update_ports.dart';
import '../update/update_service.dart';

/// The app's own bit of Android code, reached over a method channel: the
/// phone's name, the notification that keeps sync alive, and text handed
/// over from other apps with Share.
class PhoneBridge {
  PhoneBridge() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') {
        final text = call.arguments;
        if (text is String) onSharedText?.call(text);
      } else if (call.method == 'sharedFiles') {
        final paths = call.arguments;
        if (paths is List) {
          onSharedFiles?.call(paths.whereType<String>().toList());
        }
      } else if (call.method == 'capture') {
        // Answered only once the clipboard has been read: the Android
        // side is holding a window in front for exactly that long.
        await onCapture?.call();
      }
    });
  }

  static const _channel = MethodChannel('pastehive/phone');

  /// Called with text another app shared to this one while it was running.
  void Function(String text)? onSharedText;

  /// Called with the files another app shared to this one while it was
  /// running, already copied into the app's own folder.
  void Function(List<String> paths)? onSharedFiles;

  /// Called when a copy was noticed, or sending was asked for by hand: the
  /// clipboard can be read right now, and should be.
  Future<void> Function()? onCapture;

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

  /// The sets of files shared to the app before it was ready for them.
  Future<List<List<String>>> takeSharedFiles() async {
    final sets = await _invoke<List<Object?>>('takeSharedFiles');
    return [
      for (final set in sets ?? const <Object?>[])
        if (set is List) set.whereType<String>().toList(),
    ];
  }

  /// Puts the stored files at [paths] on the phone's clipboard.
  Future<bool> writeClipboardFiles(List<String> paths) async =>
      await _invoke<bool>('writeClipboardFiles', paths) ?? false;

  /// Opens the stored file at [paths] in whichever app handles it, or
  /// offers several to be sent or saved together.
  Future<bool> openFiles(List<String> paths) async =>
      await _invoke<bool>('openFiles', paths) ?? false;

  /// The picture on the phone's clipboard, if there is one and the system
  /// will show it.
  Future<ClipboardImage?> readClipboardImage() async {
    final image = await _invoke<Map<Object?, Object?>>('readClipboardImage');
    final png = image?['png'];
    final width = image?['width'];
    final height = image?['height'];
    if (png is! Uint8List || width is! int || height is! int) return null;
    return ClipboardImage(png: png, width: width, height: height);
  }

  /// Puts the stored picture at [path] on the phone's clipboard.
  Future<bool> writeClipboardImage(String path) async =>
      await _invoke<bool>('writeClipboardImage', path) ?? false;

  /// Puts [text] on the phone's clipboard.
  Future<void> writeClipboard(String text) =>
      _invoke<void>('writeClipboard', text);

  /// The kind of processor this phone has, as Android names it (such as
  /// `arm64-v8a`); empty when it cannot be told.
  Future<String> deviceAbi() async => await _invoke<String>('deviceAbi') ?? '';

  /// Opens a web address in the phone's browser.
  Future<void> openUrl(String url) => _invoke<void>('openUrl', url);

  /// Hands a downloaded APK to Android's installer, which asks the user to
  /// confirm. False when Android would not take it.
  Future<bool> installApk(String path) async =>
      await _invoke<bool>('installApk', path) ?? false;

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

/// The phone's clipboard: text and pictures, readable only while the app has
/// a window in front.
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
  Future<ClipboardImage?> readImage() => bridge.readClipboardImage();

  @override
  bool writeText(String text) {
    unawaited(bridge.writeClipboard(text));
    return true;
  }

  @override
  bool writeImage(String path) {
    unawaited(bridge.writeClipboardImage(path));
    return true;
  }

  // Files received from another device are kept in the app's own folder
  // and offered to whichever app pastes them.

  @override
  bool writeFiles(List<String> paths) {
    unawaited(bridge.writeClipboardFiles(paths));
    return true;
  }
}

/// Android: the release is an APK, handed to the system's installer. The
/// user confirms there; the first time, Android also asks them to allow
/// PasteHive to install apps.
///
/// Android only installs an update signed with the same key as the copy it
/// replaces. A build signed with a different key is refused by the system.
///
/// A release has one APK per kind of processor; the phone takes the one for
/// its own.
class AndroidUpdateInstaller implements UpdateInstaller {
  const AndroidUpdateInstaller(this.bridge, {this.abi = 'arm64-v8a'});

  final PhoneBridge bridge;

  /// The kind of processor this phone has, as Android names it.
  final String abi;

  @override
  String get assetName => androidAssetFor(abi);

  @override
  String? get unavailableReason => null;

  @override
  Future<Directory> downloadDirectory() async {
    final folder = Directory(
      path.join((await getTemporaryDirectory()).path, 'updates'),
    );
    await folder.create(recursive: true);
    return folder;
  }

  @override
  Future<bool> install(File file) async {
    if (!await bridge.installApk(file.path)) {
      throw const UpdateException(
        'Android would not open the update. Download it from its page.',
      );
    }
    // The system's installer takes it from here; the app keeps running
    // until Android replaces it.
    return false;
  }
}

/// The release file for a phone whose processor Android calls [abi].
String androidAssetFor(String abi) => switch (abi) {
  'armeabi-v7a' || 'armeabi' => 'PasteHive-android-arm32.apk',
  'x86_64' || 'x86' => 'PasteHive-android-x86_64.apk',
  // 64-bit ARM: nearly every phone. Also the answer for anything unknown.
  _ => 'PasteHive-android.apk',
};

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
