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
import 'package:synchronize_clipboard/src/ui/clipboard_panel.dart';

import '../fakes.dart';

final _enabled = Platform.environment['PANEL_PREVIEW'] == '1';

Future<void> _loadFonts() async {
  final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    );
  await icons.load();

  // Whatever system UI font this machine has; previews are for eyes only.
  for (final candidate in const [
    r'C:\Windows\Fonts\segoeui.ttf',
    '/System/Library/Fonts/SFNS.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ]) {
    final file = File(candidate);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    final text = FontLoader('PreviewText')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await text.load();
    break;
  }
}

void main() {
  final boundaryKey = GlobalKey();

  Future<void> render(
    WidgetTester tester,
    String name, {
    required Brightness brightness,
    bool hasMaterial = true,
    List<String>? texts,
    String query = '',
  }) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1040, 1240);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final history = historyWith(
      texts ??
          [
            'ssh deploy@staging-03.internal',
            'Notes from the design review\n- tighten the header\n- try a wider search field',
            'https://developer.apple.com/design/human-interface-guidelines/materials',
            'The quick brown fox jumps over the lazy dog and keeps going for a while longer',
            '4111 1111 1111 1111',
            'final window = WindowManager.instance.getCurrent();',
            'https://flutter.dev/docs',
            'Remember to call the dentist',
            'W:\\Mobile Application\\Synchronize Clipboard',
          ],
    );
    if (history.entries.length > 2) history.togglePin(history.entries[2].id);

    final dark = brightness == Brightness.dark;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: brightness, fontFamily: 'PreviewText'),
          home: DecoratedBox(
            // Stands in for a blurred desktop behind the window.
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
                child: SizedBox(
                  width: 440,
                  height: 540,
                  child: ClipboardPanel(
                    history: history,
                    reveal: const AlwaysStoppedAnimation(1),
                    visit: 1,
                    hasMaterial: hasMaterial,
                    onCopy: (_) {},
                    onDismiss: () {},
                    clock: () => DateTime.utc(2026, 11, 26, 9, 40),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (query.isNotEmpty) {
      await tester.enterText(find.byType(TextField), query);
    }
    await tester.pump();

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

  group(
    'previews',
    skip: _enabled ? false : 'set PANEL_PREVIEW=1 to render',
    () {
      testWidgets(
        'dark',
        (tester) => render(tester, 'dark', brightness: Brightness.dark),
      );
      testWidgets(
        'light',
        (tester) => render(tester, 'light', brightness: Brightness.light),
      );
      testWidgets(
        'dark without a material',
        (tester) => render(
          tester,
          'dark_opaque',
          brightness: Brightness.dark,
          hasMaterial: false,
        ),
      );
      testWidgets(
        'empty',
        (tester) => render(
          tester,
          'empty',
          brightness: Brightness.dark,
          texts: const [],
        ),
      );
      testWidgets(
        'no results',
        (tester) => render(
          tester,
          'no_results',
          brightness: Brightness.light,
          query: 'zebra',
        ),
      );
    },
  );
}
