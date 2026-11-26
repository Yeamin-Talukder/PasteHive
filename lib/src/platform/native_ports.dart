/// The real desktop, through nativeapi.
///
/// None of this can run in a unit test (there is no native library in the
/// test VM), which is why everything above this file talks to the interfaces
/// in `ports.dart` instead.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:nativeapi/nativeapi.dart' as na;
import 'package:nativeapi_flutter/nativeapi_flutter.dart' show ImageAsset;

import '../shell/panel_controller.dart';
import 'ports.dart';
import 'win32.dart';

class NativeClipboard implements ClipboardPort {
  const NativeClipboard();

  @override
  bool get canWatch =>
      na.Clipboard.instance.isSupported() &&
      na.Clipboard.instance.isChangeMonitoringSupported();

  @override
  void Function() watch(void Function() onChanged) {
    final listenerId = na.Clipboard.instance.addListener((event) {
      if (event is na.ClipboardChangedEvent) onChanged();
    });
    return () => na.Clipboard.instance.removeListener(listenerId);
  }

  @override
  Future<String?> readText() => na.Clipboard.instance.readTextAsync();

  @override
  Future<List<String>> readFiles() =>
      na.Clipboard.instance.readFilePathsAsync();

  @override
  Future<ClipboardImage?> readImage() async {
    final image = await na.Clipboard.instance.readImageAsync();
    if (image == null) return null;
    try {
      final size = image.size;
      // The library hands the picture over as a PNG in a data URI.
      final encoded = image.toBase64();
      if (encoded == null || size.width < 1 || size.height < 1) return null;
      return ClipboardImage(
        png: decodeDataUri(encoded),
        width: size.width.round(),
        height: size.height.round(),
      );
    } on FormatException {
      return null;
    } finally {
      image.dispose();
    }
  }

  @override
  bool writeText(String text) => na.Clipboard.instance.writeText(text);

  @override
  bool writeImage(String path) {
    final image = na.Image.fromFile(path);
    if (image == null) return false;
    try {
      return na.Clipboard.instance.writeImage(image);
    } finally {
      image.dispose();
    }
  }

  @override
  bool writeFiles(List<String> paths) =>
      na.Clipboard.instance.writeFilePaths(paths);
}

/// The bytes of a base64 `data:` URI, or of bare base64.
///
/// Encoders differ in the details: some wrap the text into lines, some leave
/// the padding off or get it wrong, some end the text with a stray
/// character. Everything that is not a base64 digit is dropped and the
/// padding is worked out afresh. Throws a [FormatException] when what is
/// left cannot be base64 (a length no encoding produces).
Uint8List decodeDataUri(String encoded) {
  final digits = encoded
      .substring(encoded.indexOf(',') + 1)
      .replaceAll(RegExp('[^A-Za-z0-9+/_-]'), '');
  return base64Decode(base64.normalize(digits));
}

class NativePointer implements PointerPort {
  const NativePointer();

  @override
  Offset cursorPosition() {
    final point = na.DisplayManager.instance.getCursorPosition();
    return Offset(point.x, point.y);
  }

  @override
  List<DisplayGeometry> displays() {
    final displays = na.DisplayManager.instance.getAll();
    try {
      return [
        for (final display in displays)
          DisplayGeometry(
            bounds: _boundsOf(display),
            workArea: _rect(display.workArea),
          ),
      ];
    } finally {
      for (final display in displays) {
        display.dispose();
      }
    }
  }

  static Rect _boundsOf(na.Display display) {
    final position = display.position;
    final size = display.size;
    return Rect.fromLTWH(position.x, position.y, size.width, size.height);
  }
}

class NativePanelWindow implements PanelWindowPort {
  /// Room around the panel for the shadow the app draws on Windows. The top
  /// is only the gap between the screen edge and the panel, so the window
  /// starts at the very top of the screen.
  static const _windowsInsets = EdgeInsets.fromLTRB(48, 8, 48, 72);

  na.Window? _window;
  bool _hasMaterial = false;
  BackdropCapture? _backdrop;
  int _previousWindow = 0;

  /// Whether the last paste's key events were accepted, for diagnostics.
  bool? lastPasteSent;

  /// The material that ended up behind the panel, for diagnostics.
  na.VisualEffect appliedEffect = na.VisualEffect.none;

  /// Whether the last [show] managed to take the keyboard, for diagnostics.
  bool? tookForeground;

  /// Whether the last [show] got a picture of the screen, for diagnostics.
  bool? capturedBackdrop;

  na.Window? get window => _window;

  @override
  bool get hasMaterial => _hasMaterial;

  @override
  EdgeInsets get chromeInsets =>
      Platform.isWindows ? _windowsInsets : EdgeInsets.zero;

  @override
  bool prepare() {
    final window =
        na.WindowManager.instance.getCurrent() ??
        na.Application.instance.getPrimaryWindow() ??
        na.WindowManager.instance.getAll().firstOrNull;
    if (window == null) return false;
    _window = window;

    window
      ..setFrameless(true)
      ..isResizable = false
      ..isMovable = false
      ..isMinimizable = false
      ..isMaximizable = false
      ..isFullScreenable = false
      ..isAlwaysOnTop = true
      ..isVisibleInTaskbar = false
      ..isVisibleOnAllWorkspaces = true;
    if (na.Window.isVisibleOnFullScreenSupported()) {
      window.setVisibleOnFullScreen(true);
    }

    if (Platform.isWindows) {
      _prepareTransparentSheet(window);
    } else {
      _prepareMaterialPanel(window);
    }
    return true;
  }

  // Windows only blurs behind the active window, and a panel that opens on
  // hover often is not. So the window is made a see-through sheet with
  // nothing of the system's on it, and the app draws the glass itself.
  void _prepareTransparentSheet(na.Window window) {
    window
      ..setVisualEffect(na.VisualEffect.none)
      ..backgroundColor = const na.Color(r: 0, g: 0, b: 0, a: 0)
      ..hasShadow = false;
    leaveWindowUndecorated(window.nativeObject.address);
  }

  void _prepareMaterialPanel(na.Window window) {
    window.hasShadow = true;
    if (na.Window.isCornerPreferenceSupported()) {
      window.setCornerPreference(na.WindowCornerPreference.round);
    }
    if (Platform.isMacOS) {
      // A non-activating panel takes keys without pulling the app the user
      // is working in out of the foreground.
      window.isNonActivating = true;
    }
    for (final effect in const [
      na.VisualEffect.popover,
      na.VisualEffect.hud,
      na.VisualEffect.menu,
      na.VisualEffect.blur,
    ]) {
      if (na.Window.isVisualEffectSupported(effect) &&
          window.setVisualEffect(effect)) {
        appliedEffect = effect;
        _hasMaterial = true;
        break;
      }
    }
  }

  @override
  BackdropCapture? show(Rect frame) {
    final window = _window;
    if (window == null) return null;

    if (Platform.isWindows) {
      final sheet = chromeInsets.inflateRect(frame);
      window.bounds = na.Rectangle(
        x: sheet.left,
        y: sheet.top,
        width: sheet.width,
        height: sheet.height,
      );
      final hwnd = window.nativeObject.address;
      // Who had the keyboard, so a picked entry can be pasted back there.
      final front = foregroundWindow();
      if (front != hwnd) _previousWindow = front;
      // Reopened before it had finished closing: the window is still up, so
      // a new picture would have the panel itself in it. Keep the last one.
      if (!window.isVisible || _backdrop == null) {
        // Taken while the window is hidden, so it shows what is behind.
        final pixels = captureBehindWindow(hwnd);
        _backdrop = pixels == null
            ? null
            : BackdropCapture(
                bgra: pixels.bgra,
                width: pixels.width,
                height: pixels.height,
              );
      }
      capturedBackdrop = _backdrop != null;
      window.show();
      tookForeground = takeForeground(hwnd);
      return _backdrop;
    }

    final origin = panelOriginAt(frame, 0);
    window
      ..bounds = na.Rectangle(
        x: origin.dx,
        y: origin.dy,
        width: frame.width,
        height: frame.height,
      )
      ..opacity = 0
      ..show()
      ..focus();
    return null;
  }

  @override
  void applyRevealProgress(Rect frame, double progress) {
    final window = _window;
    // On Windows the sheet stays put and the panel moves inside it.
    if (window == null || Platform.isWindows) return;
    final origin = panelOriginAt(frame, progress);
    window
      ..position = na.Point(x: origin.dx, y: origin.dy)
      ..opacity = progress.clamp(0.0, 1.0);
  }

  @override
  void hide() => _window?.hide();

  // Pasting into another app on macOS means sending it key events, which
  // needs the Accessibility permission and native code; not done yet.
  @override
  bool get canPaste => Platform.isWindows;

  @override
  Future<bool> pasteIntoPreviousWindow() async {
    if (!Platform.isWindows) return false;
    if (!restoreForeground(_previousWindow)) return false;
    // The other window needs a moment to become active and put the
    // keyboard back in the field that had it.
    await Future<void>.delayed(const Duration(milliseconds: 90));
    lastPasteSent = sendPasteKeys();
    return lastPasteSent!;
  }

  @override
  void Function() watchBlur(void Function() onBlur) {
    final window = _window;
    if (window == null) return () {};
    final listenerId = window.addListener((event) {
      if (event is na.WindowBlurredEvent) onBlur();
    });
    return () => window.removeListener(listenerId);
  }
}

class NativeTray implements TrayPort {
  static const _tooltip = 'Synchronize Clipboard';

  // Native objects are released when their Dart wrappers are collected, so
  // everything the tray needs is held here for as long as the icon is up.
  na.TrayIcon? _icon;
  na.Image? _image;
  na.Menu? _menu;
  na.MenuItem? _pauseItem;
  na.MenuItem? _loginItem;
  na.LaunchAtLogin? _launchAtLogin;
  final List<na.MenuItem> _items = [];
  bool _paused = false;

  @override
  bool install(TrayActions actions) {
    if (!na.TrayManager.instance.isSupported()) return false;
    final icon = na.TrayIcon.create();
    final menu = na.Menu.create();
    if (icon == null || menu == null) return false;
    _icon = icon;
    _menu = menu;

    _image = ImageAsset.fromAsset(
      Platform.isMacOS
          ? 'assets/tray/tray_macos.png'
          : 'assets/tray/tray_windows.png',
    );
    if (_image == null) {
      debugPrint('Tray icon image could not be loaded.');
    }
    icon
      ..icon = _image
      ..setTooltip(_tooltip);
    if (Platform.isMacOS) {
      // A template image is tinted by the menu bar to match light and dark.
      icon
        ..isIconTemplate = true
        ..iconSize = const na.Size(width: 18, height: 18);
    }

    _addItem('Show Clipboard', actions.onTogglePanel);
    _addItem('Sync Settings…', actions.onOpenSyncSettings);
    menu.addSeparator();
    _pauseItem = _addItem('Pause Capturing', () {
      _paused = !_paused;
      actions.onPausedChanged(_paused);
      _syncChecks();
    }, checkbox: true);
    _addLoginItem();
    _addItem('Clear History', actions.onClearHistory);
    menu.addSeparator();
    _addItem('Quit Synchronize Clipboard', actions.onQuit);

    icon.setContextMenu(menu);
    if (Platform.isMacOS) {
      // Menu bar extras open their menu on a plain click.
      icon.setContextMenuTrigger(na.ContextMenuTrigger.clicked);
    } else {
      icon.setContextMenuTrigger(na.ContextMenuTrigger.rightClicked);
      icon.addListener((event) {
        if (event is na.TrayIconClickedEvent) actions.onTogglePanel();
      });
    }
    return icon.setVisible(true);
  }

  @override
  void setPaused(bool paused) {
    _paused = paused;
    _syncChecks();
  }

  @override
  void dispose() {
    _icon?.setVisible(false);
    _icon?.dispose();
    _icon = null;
  }

  na.MenuItem? _addItem(
    String label,
    void Function() onClick, {
    bool checkbox = false,
  }) {
    final item = na.MenuItem.createWithLabelAndType(
      label,
      checkbox ? na.MenuItemType.checkbox : na.MenuItemType.normal,
    );
    if (item == null) return null;
    item.addListener((event) {
      if (event is na.MenuItemClickedEvent) onClick();
    });
    _items.add(item);
    _menu!.addItem(item);
    return item;
  }

  void _addLoginItem() {
    if (!na.LaunchAtLogin.isSupported()) return;
    final launchAtLogin = na.LaunchAtLogin.create();
    if (launchAtLogin == null) return;
    _launchAtLogin = launchAtLogin;
    _loginItem = _addItem(
      Platform.isMacOS ? 'Open at Login' : 'Start with Windows',
      () {
        final enabled = launchAtLogin.isEnabled;
        if (enabled) {
          launchAtLogin.disable();
        } else {
          launchAtLogin.enable();
        }
        _syncChecks();
      },
      checkbox: true,
    );
    _syncChecks();
  }

  // Some systems tick a check item themselves when it is clicked and some do
  // not, so the state is always set from what is actually true.
  void _syncChecks() {
    _pauseItem?.state = _paused
        ? na.MenuItemState.checked
        : na.MenuItemState.unchecked;
    final launchAtLogin = _launchAtLogin;
    if (launchAtLogin != null) {
      _loginItem?.state = launchAtLogin.isEnabled
          ? na.MenuItemState.checked
          : na.MenuItemState.unchecked;
    }
  }
}

Rect _rect(na.Rectangle rectangle) =>
    Rect.fromLTWH(rectangle.x, rectangle.y, rectangle.width, rectangle.height);
