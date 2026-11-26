import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nativeapi/nativeapi.dart' as na;

import '../app_shell.dart';
import '../platform/native_ports.dart';

/// A self-check for developers, off unless asked for.
///
/// Start the app with the environment variable `SYNC_CLIPBOARD_SMOKE` set to
/// a file path and it opens the panel by itself, writes what the system
/// reported (was a window found, which material was applied, did the tray
/// icon go up, where the window landed) to that file as JSON, closes the
/// panel, and quits. It checks that the native calls are accepted; it cannot
/// tell whether the result looks right.
class SmokeRun {
  SmokeRun({
    required this.outputPath,
    required this.shell,
    required this.window,
  });

  static const environmentVariable = 'SYNC_CLIPBOARD_SMOKE';

  /// The path asked for, or null when this is a normal launch.
  static String? get requestedPath {
    final path = Platform.environment[environmentVariable];
    return (path == null || path.isEmpty) ? null : path;
  }

  final String outputPath;
  final AppShell shell;
  final NativePanelWindow window;

  Future<void> run() async {
    final report = <String, Object?>{
      'platform': Platform.operatingSystem,
      'panelReady': shell.panelReady,
      'trayReady': shell.trayReady,
      'hasMaterial': window.hasMaterial,
      'appliedEffect': window.appliedEffect.name,
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
      'historyCountAtStart': shell.history.entries.length,
      'visibleBeforeOpen': window.window?.isVisible,
    };

    try {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      shell.panel.toggle();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final native = window.window;
      report['open'] = {
        'controllerIsOpen': shell.panel.isOpen,
        'visible': native?.isVisible,
        'focused': native?.isFocused,
        'bounds': native?.bounds.toString(),
        'frameless': native?.isFrameless,
        'alwaysOnTop': native?.isAlwaysOnTop,
        'inTaskbar': native?.isVisibleInTaskbar,
        'effectInForce': native?.visualEffect.name,
      };

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
        for (final entry in shell.history.entries.toList()) {
          if (entry.text == marker) shell.history.remove(entry.id);
        }
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
}
