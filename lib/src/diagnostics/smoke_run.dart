import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:nativeapi/nativeapi.dart' as na;

import '../app_shell.dart';
import '../history/clipboard_history.dart';
import '../history/history_store.dart';
import '../platform/native_ports.dart';

/// A self-check for developers, off unless asked for.
///
/// Start the app with the environment variable `SYNC_CLIPBOARD_SMOKE` set to
/// a file path and it opens the panel by itself, writes what the system
/// reported (was a window found, did it take the keyboard, did the tray icon
/// go up, where the window landed) to that file as JSON, saves a picture of
/// the panel as it was drawn next to it (same name, `.png`), closes the
/// panel, and quits.
///
/// A check run does not read or show the real clipboard history: the list is
/// filled with made-up entries (see [demoHistory]) and nothing is saved.
class SmokeRun {
  SmokeRun({
    required this.outputPath,
    required this.shell,
    required this.window,
    required this.captureKey,
  });

  static const environmentVariable = 'SYNC_CLIPBOARD_SMOKE';

  /// The path asked for, or null when this is a normal launch.
  static String? get requestedPath {
    final path = Platform.environment[environmentVariable];
    return (path == null || path.isEmpty) ? null : path;
  }

  /// The list a check run shows instead of the real one.
  static ClipboardHistory demoHistory() {
    final history = ClipboardHistory(store: MemoryHistoryStore());
    for (final text in const [
      'Remember to call the dentist',
      'https://flutter.dev/docs',
      'final window = WindowManager.instance.getCurrent();',
      'hello@example.com',
      '#FF6B9D',
      'Notes from the design review\n- tighten the header',
    ]) {
      history.record(text);
    }
    history
      ..record('Copied on the other computer', source: 'MacBook')
      ..togglePin(history.entries[2].id);
    return history;
  }

  final String outputPath;
  final AppShell shell;
  final NativePanelWindow window;

  /// The key of a [RepaintBoundary] around the whole app, to take its
  /// picture.
  final GlobalKey captureKey;

  Future<void> run() async {
    final report = <String, Object?>{
      'platform': Platform.operatingSystem,
      'panelReady': shell.panelReady,
      'trayReady': shell.trayReady,
      'hasMaterial': window.hasMaterial,
      'appliedEffect': window.appliedEffect.name,
      'chromeInsets': window.chromeInsets.toString(),
      'clipboardSupported': na.Clipboard.instance.isSupported(),
      'clipboardCanWatch': const NativeClipboard().canWatch,
      'displays': [
        for (final display in const NativePointer().displays())
          {
            'bounds': display.bounds.toString(),
            'workArea': display.workArea.toString(),
          },
      ],
      'cursor': const NativePointer().cursorPosition().toString(),
      // Reported, never changed: the check does not switch sync on.
      'sync': {
        'hasKey': shell.sync.hasKey,
        'enabled': shell.sync.enabled,
        'running': shell.sync.running,
        'error': shell.sync.error,
        'peers': shell.sync.peers.length,
      },
      'visibleBeforeOpen': window.window?.isVisible,
    };

    try {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final opened = Stopwatch()..start();
      shell.panel.toggle();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final native = window.window;
      report['open'] = {
        'controllerIsOpen': shell.panel.isOpen,
        'visible': native?.isVisible,
        'focused': native?.isFocused,
        'tookForeground': window.tookForeground,
        'capturedBackdrop': window.capturedBackdrop,
        'backdropSize': shell.panel.backdrop == null
            ? null
            : '${shell.panel.backdrop!.width}x${shell.panel.backdrop!.height}',
        'bounds': native?.bounds.toString(),
        'frameless': native?.isFrameless,
        'alwaysOnTop': native?.isAlwaysOnTop,
        'inTaskbar': native?.isVisibleInTaskbar,
        'effectInForce': native?.visualEffect.name,
      };
      report['picture'] = await _savePicture();
      opened.stop();

      // Copy through the system clipboard and see it come back as an entry.
      // Only when the clipboard holds text, which can be put back afterwards;
      // an image or a file on the clipboard would be lost, so it is left alone.
      final previous = await na.Clipboard.instance.readTextAsync();
      if (previous == null) {
        report['clipboardRoundTrip'] = 'skipped: clipboard holds no text';
      } else {
        final marker = 'smoke ${DateTime.now().microsecondsSinceEpoch}';
        report['clipboardWrite'] = na.Clipboard.instance.writeText(marker);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        report['clipboardCaptured'] = shell.history.entries.any(
          (entry) => entry.text == marker,
        );
        na.Clipboard.instance.writeText(previous);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      shell.panel.dismiss();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      report['visibleAfterDismiss'] = native?.isVisible;
    } on Object catch (error, stackTrace) {
      report['error'] = '$error';
      report['stackTrace'] = '$stackTrace';
    }

    await File(outputPath)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    await shell.quit();
  }

  /// Saves what the app has drawn in its window, as a PNG. The glass in it is
  /// over a blurred picture of this screen; nothing behind it is readable.
  Future<String> _savePicture() async {
    final boundary = captureKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return 'no boundary to capture';
    final pixelRatio =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return 'could not encode';
    final path = outputPath.replaceFirst(RegExp(r'\.[^.\\/]*$'), '.png');
    await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
    return path;
  }
}
