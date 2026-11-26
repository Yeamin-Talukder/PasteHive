// Renders the panel to PNG files so its design can be looked at without
// launching the app. Skipped in a normal test run.
//
//   $env:PANEL_PREVIEW = "1"; flutter test test/ui/panel_preview_test.dart
//
// The pictures land in build/previews/. They show the panel's own drawing over
// a stand-in backdrop; the real blur behind the window comes from the system
// and is not part of a test render.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synchronize_clipboard/src/sync/sync_ports.dart';
import 'package:synchronize_clipboard/src/sync/sync_service.dart';
import 'package:synchronize_clipboard/src/ui/clipboard_panel.dart';
import 'package:synchronize_clipboard/src/ui/sync_settings_view.dart';

import '../fakes.dart';
import '../sync/memory_network.dart';
import '../sync/sync_service_test.dart' show eventually;

final _enabled = Platform.environment['PANEL_PREVIEW'] == '1';

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

const _sampleTexts = [
  'ssh deploy@staging-03.internal',
  'Notes from the design review\n- tighten the header\n- try a wider search field',
  'https://developer.apple.com/design/human-interface-guidelines/materials',
  'The quick brown fox jumps over the lazy dog and keeps going for a while longer',
  '4111 1111 1111 1111',
  'final window = WindowManager.instance.getCurrent();',
  'https://flutter.dev/docs',
  'Remember to call the dentist',
  'W:\\Mobile Application\\Synchronize Clipboard',
];

void main() {
  final boundaryKey = GlobalKey();

  /// Shows [panel] in a 440x540 frame over a stand-in desktop.
  Future<void> show(
    WidgetTester tester,
    Widget panel, {
    required Brightness brightness,
  }) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1040, 1240);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final dark = brightness == Brightness.dark;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: brightness, fontFamily: 'PreviewText'),
          home: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [
                        Color(0xFF3A2F5B),
                        Color(0xFF1F3B4D),
                        Color(0xFF41302B),
                      ]
                    : const [
                        Color(0xFFBFD3F2),
                        Color(0xFFE9D5E6),
                        Color(0xFFF3E3C8),
                      ],
              ),
            ),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(width: 440, height: 540, child: panel),
              ),
            ),
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
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/previews/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    });
    // Let the history's delayed save run out before the test ends.
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> list(
    WidgetTester tester,
    String name, {
    required Brightness brightness,
    bool hasMaterial = true,
    List<String> texts = _sampleTexts,
    String query = '',
    SyncSummary? sync,
  }) async {
    final history = historyWith(texts);
    if (history.entries.length > 2) history.togglePin(history.entries[2].id);
    await show(
      tester,
      ClipboardPanel(
        history: history,
        reveal: const AlwaysStoppedAnimation(1),
        visit: 1,
        hasMaterial: hasMaterial,
        onCopy: (_) {},
        onDismiss: () {},
        sync: sync,
        onOpenSync: sync == null ? null : () {},
        clock: () => DateTime.utc(2026, 11, 26, 9, 40),
      ),
      brightness: brightness,
    );
    if (query.isNotEmpty) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump();
    }
    await capture(tester, name);
  }

  group(
    'previews',
    skip: _enabled ? false : 'set PANEL_PREVIEW=1 to render',
    () {
      testWidgets(
        'dark',
        (tester) => list(
          tester,
          'dark',
          brightness: Brightness.dark,
          sync: const SyncSummary(label: 'Sam’s MacBook', connected: true),
        ),
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
        'dark without a material',
        (tester) => list(
          tester,
          'dark_opaque',
          brightness: Brightness.dark,
          hasMaterial: false,
        ),
      );
      testWidgets(
        'empty',
        (tester) =>
            list(tester, 'empty', brightness: Brightness.dark, texts: const []),
      );
      testWidgets(
        'no results',
        (tester) => list(
          tester,
          'no_results',
          brightness: Brightness.light,
          query: 'zebra',
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
          SyncSettingsView(sync: sync, hasMaterial: true, onDone: () {}),
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
          SyncSettingsView(sync: sync, hasMaterial: true, onDone: () {}),
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
