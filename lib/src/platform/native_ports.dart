/// The real desktop, through nativeapi.
///
/// None of this can run in a unit test (there is no native library in the
/// test VM), which is why everything above this file talks to the interfaces
/// in `ports.dart` instead.
library;

import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:nativeapi/nativeapi.dart' as na;
import 'package:nativeapi_flutter/nativeapi_flutter.dart' show ImageAsset;

import '../shell/panel_controller.dart';
import 'ports.dart';

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
  bool writeText(String text) => na.Clipboard.instance.writeText(text);
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
  na.Window? _window;
  bool _hasMaterial = false;

  /// The material that ended up behind the panel, for diagnostics.
  na.VisualEffect appliedEffect = na.VisualEffect.none;

  na.Window? get window => _window;

  @override
  bool get hasMaterial => _hasMaterial;

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
      ..isVisibleOnAllWorkspaces = true
      ..hasShadow = true;
    if (na.Window.isVisibleOnFullScreenSupported()) {
      window.setVisibleOnFullScreen(true);
    }
    if (na.Window.isCornerPreferenceSupported()) {
      window.setCornerPreference(na.WindowCornerPreference.round);
    }
    if (Platform.isMacOS) {
      // A non-activating panel takes keys without pulling the app the user is
      // working in out of the foreground. On Windows the same flag would also
      // refuse the keyboard, so there the panel is activated like any window.
      window.isNonActivating = true;
    }

    for (final effect in _preferredEffects) {
      if (na.Window.isVisualEffectSupported(effect) &&
          window.setVisualEffect(effect)) {
        appliedEffect = effect;
        _hasMaterial = true;
        break;
      }
    }
    return true;
  }

  @override
  void show(Rect frame) {
    final window = _window;
    if (window == null) return;
    final origin = panelOriginAt(frame, 0);
    window.bounds = na.Rectangle(
      x: origin.dx,
      y: origin.dy,
      width: frame.width,
      height: frame.height,
    );
    if (_fadesWindow) window.opacity = 0;
    window
      ..show()
      ..focus();
  }

  @override
  void applyRevealProgress(Rect frame, double progress) {
    final window = _window;
    if (window == null) return;
    final origin = panelOriginAt(frame, progress);
    window.position = na.Point(x: origin.dx, y: origin.dy);
    if (_fadesWindow) window.opacity = progress.clamp(0.0, 1.0);
  }

  @override
  void hide() => _window?.hide();

  @override
  void Function() watchBlur(void Function() onBlur) {
    final window = _window;
    if (window == null) return () {};
    final listenerId = window.addListener((event) {
      if (event is na.WindowBlurredEvent) onBlur();
    });
    return () => window.removeListener(listenerId);
  }

  /// macOS shows a window with no transition of its own, so the panel fades
  /// its window in. Windows already fades windows as it shows and hides them.
  static bool get _fadesWindow => Platform.isMacOS;

  static List<na.VisualEffect> get _preferredEffects => Platform.isMacOS
      ? const [
          na.VisualEffect.popover,
          na.VisualEffect.hud,
          na.VisualEffect.menu,
          na.VisualEffect.blur,
        ]
      : const [na.VisualEffect.acrylic, na.VisualEffect.blur];
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
