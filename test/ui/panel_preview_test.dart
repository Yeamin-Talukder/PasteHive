// Renders the panel to PNG files so its design can be looked at without
// launching the app. Skipped in a normal test run.
//
//   $env:PANEL_PREVIEW = "1"; flutter test test/ui/panel_preview_test.dart
//
// The pictures land in build/previews/. They show the glass the way the app
// draws it on Windows: over a blurred picture of the "desktop" behind it,
// which here is a made-up one.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synchronize_clipboard/src/history/clipboard_history.dart';
import 'package:synchronize_clipboard/src/platform/ports.dart';
import 'package:synchronize_clipboard/src/sync/sync_ports.dart';
import 'package:synchronize_clipboard/src/sync/sync_service.dart';
import 'package:synchronize_clipboard/src/ui/clipboard_panel.dart';
import 'package:synchronize_clipboard/src/ui/glass_shell.dart';
import 'package:synchronize_clipboard/src/ui/sync_settings_view.dart';

import '../fakes.dart';
import '../sync/memory_network.dart';
import '../sync/sync_service_test.dart' show eventually;

final _enabled = Platform.environment['PANEL_PREVIEW'] == '1';

/// The window the panel is drawn in: the panel plus room for its shadow.
const _insets = EdgeInsets.fromLTRB(48, 8, 48, 72);
const _panelSize = Size(440, 540);
final _windowSize = _insets.inflateSize(_panelSize);
const _pixelRatio = 2.0;

Future<void> _loadFonts() async {
  final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    );
  await icons.load();

  // Whatever system fonts this machine has; previews are for eyes only.
  Future<void> loadFirst(String family, List<String> candidates) async {
    for (final candidate in candidates) {
      final file = File(candidate);
      if (!file.existsSync()) continue;
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
      return;
    }
  }

  await loadFirst('PreviewText', const [
    r'C:\Windows\Fonts\segoeui.ttf',
    '/System/Library/Fonts/SFNS.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ]);
  // The sync key's font; the view asks for Menlo and falls back from there.
  await loadFirst('Menlo', const [
    '/System/Library/Fonts/Menlo.ttc',
    r'C:\Windows\Fonts\consola.ttf',
  ]);
}

/// A stand-in desktop: a colourful wallpaper with a couple of "windows" of
/// text on it, so the blur has something to work on.
Future<ui.Image> _paintDesktop(Brightness brightness) {
  final width = (_windowSize.width * _pixelRatio).round();
  final height = (_windowSize.height * _pixelRatio).round();
  final size = Size(width.toDouble(), height.toDouble());
  final dark = brightness == Brightness.dark;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        size.bottomRight(Offset.zero),
        dark
            ? const [Color(0xFF2B1B5A), Color(0xFF0F4C6B), Color(0xFF7A2E3B)]
            : const [Color(0xFF8EC5FC), Color(0xFFE0C3FC), Color(0xFFFFD9A0)],
        const [0, 0.55, 1],
      ),
  );
  for (final (center, radius, color) in [
    (const Offset(0.2, 0.25), 0.32, const Color(0xFFFF6B9D)),
    (const Offset(0.85, 0.15), 0.28, const Color(0xFF4FD1C5)),
    (const Offset(0.7, 0.8), 0.36, const Color(0xFFFFC857)),
  ]) {
    canvas.drawCircle(
      Offset(center.dx * size.width, center.dy * size.height),
      radius * size.width,
      Paint()..color = color.withValues(alpha: dark ? 0.55 : 0.7),
    );
  }
  // A window with lines of text, half under where the panel will be.
  final window = Rect.fromLTWH(
    size.width * 0.08,
    size.height * 0.3,
    size.width * 0.7,
    size.height * 0.5,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(window, const Radius.circular(18)),
    Paint()..color = dark ? const Color(0xFF1B1B1F) : const Color(0xFFFFFFFF),
  );
  for (var line = 0; line < 14; line++) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          window.left + 36,
          window.top + 48 + line * 34,
          window.width * (0.35 + (line * 37 % 50) / 100),
          12,
        ),
        const Radius.circular(6),
      ),
      Paint()..color = dark ? const Color(0xFF8A8F98) : const Color(0xFF50545C),
    );
  }
  return recorder.endRecording().toImage(width, height);
}

class _Desktop {
  _Desktop(this.sharp, this.blurred);

  final ui.Image sharp;
  final ui.Image blurred;
}

Future<_Desktop> _makeDesktop(Brightness brightness) async {
  final sharp = await _paintDesktop(brightness);
  final rgba = (await sharp.toByteData())!.buffer.asUint8List();
  // The app's captures are BGRA; swap the red and blue of this RGBA picture.
  final bgra = Uint8List.fromList(rgba);
  for (var i = 0; i < bgra.length; i += 4) {
    bgra[i] = rgba[i + 2];
    bgra[i + 2] = rgba[i];
  }
  final blurred = await blurBackdrop(
    BackdropCapture(bgra: bgra, width: sharp.width, height: sharp.height),
    devicePixelRatio: _pixelRatio,
  );
  return _Desktop(sharp, blurred);
}

const _sampleTexts = [
  'ssh deploy@staging-03.internal',
  'Notes from the design review\n- tighten the header\n- try a wider search field',
  'https://developer.apple.com/design/human-interface-guidelines/materials',
  'The quick brown fox jumps over the lazy dog and keeps going for a while longer',
  'hello@example.com',
  '#FF6B9D',
  'final window = WindowManager.instance.getCurrent();',
  'https://flutter.dev/docs',
  'Remember to call the dentist',
];

void main() {
  final boundaryKey = GlobalKey();

  /// Shows [panel] as glass over a made-up desktop, [reveal] of the way open.
  Future<void> show(
    WidgetTester tester,
    Widget Function(bool hasMaterial) panel, {
    required Brightness brightness,
    double reveal = 1,
    bool withBackdrop = true,
  }) async {
    late final _Desktop desktop;
    await tester.runAsync(() async {
      await _loadFonts();
      desktop = await _makeDesktop(brightness);
    });
    tester.view.physicalSize = _windowSize * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: brightness, fontFamily: 'PreviewText'),
          home: Stack(
            children: [
              Positioned.fill(
                child: RawImage(image: desktop.sharp, fit: BoxFit.fill),
              ),
              Positioned.fill(
                child: GlassShell(
                  reveal: AlwaysStoppedAnimation(reveal),
                  insets: _insets,
                  backdrop: withBackdrop ? desktop.blurred : null,
                  onTapOutside: () {},
                  child: panel(withBackdrop),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: _pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/previews/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    });
    // Let timers started along the way (delayed saves, the undo toast) run
    // out before the test ends.
    await tester.pump(const Duration(seconds: 6));
  }

  ClipboardHistory sampleHistory(List<String> texts) {
    final history = historyWith(texts);
    if (history.entries.length > 3) {
      history.togglePin(history.entries[3].id);
      history.record('Copied on the other computer', source: 'Sam’s MacBook');
    }
    return history;
  }

  Future<void> list(
    WidgetTester tester,
    String name, {
    required Brightness brightness,
    bool withBackdrop = true,
    List<String> texts = _sampleTexts,
    String query = '',
    double reveal = 1,
    SyncSummary? sync,
    Future<void> Function()? then,
  }) async {
    final history = sampleHistory(texts);
    await show(
      tester,
      (hasMaterial) => ClipboardPanel(
        history: history,
        reveal: AlwaysStoppedAnimation(reveal),
        visit: 1,
        hasMaterial: hasMaterial,
        onCopy: (_) {},
        onDismiss: () {},
        sync: sync,
        onOpenSync: sync == null ? null : () {},
        // A little after the sample entries were "copied".
        clock: () => DateTime.utc(2026, 11, 26, 9, 40),
      ),
      brightness: brightness,
      reveal: reveal,
      withBackdrop: withBackdrop,
    );
    if (query.isNotEmpty) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump();
    }
    await then?.call();
    await capture(tester, name);
  }

  const connected = SyncSummary(label: 'Sam’s MacBook', connected: true);

  group(
    'previews',
    skip: _enabled ? false : 'set PANEL_PREVIEW=1 to render',
    () {
      testWidgets(
        'dark',
        (tester) =>
            list(tester, 'dark', brightness: Brightness.dark, sync: connected),
      );
      testWidgets(
        'light',
        (tester) => list(
          tester,
          'light',
          brightness: Brightness.light,
          sync: const SyncSummary(label: 'Sync Off'),
        ),
      );
      testWidgets(
        'opening, a third of the way',
        (tester) => list(
          tester,
          'opening_1',
          brightness: Brightness.dark,
          reveal: 0.3,
          sync: connected,
        ),
      );
      testWidgets(
        'opening, two thirds of the way',
        (tester) => list(
          tester,
          'opening_2',
          brightness: Brightness.dark,
          reveal: 0.65,
          sync: connected,
        ),
      );
      testWidgets(
        'dark without a backdrop',
        (tester) => list(
          tester,
          'dark_opaque',
          brightness: Brightness.dark,
          withBackdrop: false,
        ),
      );
      testWidgets(
        'empty',
        (tester) =>
            list(tester, 'empty', brightness: Brightness.dark, texts: const []),
      );
      testWidgets(
        'filtered to links',
        (tester) => list(
          tester,
          'filter_links',
          brightness: Brightness.light,
          sync: connected,
          then: () async {
            await tester.tap(find.text('Links'));
            await tester.pump(const Duration(milliseconds: 400));
          },
        ),
      );
      testWidgets(
        'preview of an entry',
        (tester) => list(
          tester,
          'preview_sheet',
          brightness: Brightness.dark,
          sync: connected,
          then: () async {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
          },
        ),
      );
      testWidgets(
        'after deleting an entry',
        (tester) => list(
          tester,
          'undo_toast',
          brightness: Brightness.light,
          then: () async {
            await tester.sendKeyEvent(LogicalKeyboardKey.delete);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
          },
        ),
      );

      testWidgets('sync settings before a key is set', (tester) async {
        final network = MemoryNetwork();
        // Built inside runAsync so all of its work is on the real clock.
        late final SyncService sync;
        await tester.runAsync(() async {
          sync = _device(network, '1', 'OFFICE-PC');
          await sync.load();
        });
        await show(
          tester,
          (hasMaterial) => SyncSettingsView(
            sync: sync,
            hasMaterial: hasMaterial,
            onDone: () {},
          ),
          brightness: Brightness.dark,
        );
        await capture(tester, 'sync_no_key');
      });

      testWidgets('sync settings with a device connected', (tester) async {
        final network = MemoryNetwork();
        late final SyncService sync;
        late final SyncService other;
        await tester.runAsync(() async {
          sync = _device(network, '1', 'OFFICE-PC');
          other = _device(network, '2', 'Sam’s MacBook');
          await sync.load();
          await other.load();
          await sync.createKey();
          await other.useKey(sync.formattedKey!);
          network.announce();
          await eventually(() => sync.peers.isNotEmpty);
        });
        await show(
          tester,
          (hasMaterial) => SyncSettingsView(
            sync: sync,
            hasMaterial: hasMaterial,
            onDone: () {},
          ),
          brightness: Brightness.light,
        );
        await tester.tap(find.text('Show'));
        await tester.pump();
        await capture(tester, 'sync_connected');
        await tester.runAsync(() async {
          await sync.shutdown();
          await other.shutdown();
        });
      });
    },
  );
}

SyncService _device(MemoryNetwork network, String id, String name) {
  return SyncService(
    discovery: network.discovery('10.0.0.$id'),
    transport: network.transport('10.0.0.$id'),
    store: MemorySyncSettingsStore(
      SyncSettings(deviceId: id, deviceName: name),
    ),
    defaultDeviceName: () => name,
    pingInterval: const Duration(days: 1),
  );
}
