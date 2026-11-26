import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:nativeapi/nativeapi.dart' as na;

import '../app_shell.dart';
import '../history/clipboard_entry.dart';
import '../history/clipboard_history.dart';
import '../history/image_vault.dart';
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
/// filled with made-up entries (see [demoHistory]) and nothing is saved. It
/// never picks an entry, so it never pastes anything into another app.
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

  /// The list a check run shows instead of the real one. Its one picture is
  /// drawn here and kept in [vault].
  static Future<ClipboardHistory> demoHistory(ImageVault vault) async {
    final history = ClipboardHistory(store: MemoryHistoryStore());
    for (final text in const [
      'Remember to call the dentist',
      'https://flutter.dev/docs',
      'final window = WindowManager.instance.getCurrent();',
      'hello@example.com',
      '#FF6B9D',
    ]) {
      history.record(text);
    }
    history
      ..recordFiles(const [r'C:\Projects\report\summary.pdf'])
      ..recordImage(
        path: await vault.store(await _demoPicture()),
        width: _demoWidth,
        height: _demoHeight,
      )
      ..record('Copied on the other computer', source: 'MacBook')
      ..togglePin(history.entries[4].id);
    return history;
  }

  static const _demoWidth = 480;
  static const _demoHeight = 300;

  static Future<Uint8List> _demoPicture() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(480, 300);
    canvas
      ..drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            size.bottomRight(Offset.zero),
            const [Color(0xFF7F5AF0), Color(0xFF2CB67D)],
          ),
      )
      ..drawCircle(
        const Offset(150, 150),
        80,
        Paint()..color = const Color(0xFFFFD166),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(260, 90, 160, 120),
          const Radius.circular(18),
        ),
        Paint()..color = const Color(0xFFEF476F),
      );
    final picture = recorder.endRecording();
    final image = await picture.toImage(_demoWidth, _demoHeight);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    return data!.buffer.asUint8List();
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
        // The same for a picture: put the made-up one on the clipboard and
        // see it arrive as a new entry at the top.
        final demo = shell.history.entries.firstWhere(
          (entry) => entry.kind == EntryKind.image,
        );
        report['imageWrite'] = const NativeClipboard().writeImage(
          demo.imagePath!,
        );
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        // Captured means either a second picture entry (the clipboard gave
        // the picture back encoded differently) or the first one moved up
        // (it gave back the very same bytes).
        final pictures = [
          for (final entry in shell.history.entries)
            if (entry.kind == EntryKind.image) entry,
        ];
        final newest = pictures.reduce(
          (a, b) => a.copiedAt.isAfter(b.copiedAt) ? a : b,
        );
        report['imageCaptured'] = newest.copiedAt.isAfter(demo.copiedAt);
        report['imageRecognisedAsSame'] = pictures.length == 1;
        report['imageCapturedSize'] =
            '${newest.imageWidth}x${newest.imageHeight}';
        report['captureError'] = shell.lastCaptureError;
        // What the clipboard itself says it holds right now, step by step.
        final rawText = await na.Clipboard.instance.readTextAsync();
        final rawFiles = await na.Clipboard.instance.readFilePathsAsync();
        final rawImage = await na.Clipboard.instance.readImageAsync();
        final rawEncoded = rawImage?.toBase64();
        report['clipboardNow'] = {
          'textLength': rawText?.length,
          'fileCount': rawFiles.length,
          'hasImage': rawImage != null,
          'imageSize': rawImage == null
              ? null
              : '${rawImage.size.width}x${rawImage.size.height}',
          'imageFormat': rawImage?.format,
          'encodedLength': rawEncoded?.length,
          'encodedStart': rawEncoded?.substring(
            0,
            rawEncoded.length.clamp(0, 30),
          ),
        };
        rawImage?.dispose();
        // The same read the app itself makes, including the decoding.
        try {
          final read = await const NativeClipboard().readImage();
          report['appReadsImage'] = read == null
              ? 'nothing'
              : '${read.width}x${read.height}, ${read.png.length} bytes';
        } on Object catch (error) {
          report['appReadsImage'] = 'failed: $error';
        }
        if (rawEncoded != null) {
          // Exactly why decoding fails, if it does.
          report['encodedTailCodes'] = rawEncoded.codeUnits
              .skip((rawEncoded.length - 6).clamp(0, rawEncoded.length))
              .toList();
          try {
            report['decodes'] = '${decodeDataUri(rawEncoded).length} bytes';
          } on Object catch (error) {
            report['decodes'] = 'failed: $error';
          }
        }
        report['imageCountAfter'] = shell.history.entries
            .where((entry) => entry.kind == EntryKind.image)
            .length;

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
