import 'package:flutter_test/flutter_test.dart';
import 'package:synchronize_clipboard/src/app_shell.dart';
import 'package:synchronize_clipboard/src/history/clipboard_history.dart';
import 'package:synchronize_clipboard/src/history/history_store.dart';
import 'package:synchronize_clipboard/src/shell/panel_controller.dart';

import 'fakes.dart';

void main() {
  late MemoryHistoryStore store;
  late ClipboardHistory history;
  late FakeClipboard clipboard;
  late FakeTray tray;
  late FakeWindow window;
  late PanelController panel;
  late int quitCount;

  AppShell buildShell() {
    return AppShell(
      history: history,
      panel: panel,
      clipboard: clipboard,
      tray: tray,
      onQuit: () async => quitCount++,
    );
  }

  List<String> texts() => [for (final entry in history.entries) entry.text];

  setUp(() {
    store = MemoryHistoryStore();
    history = historyWith([], store: store);
    clipboard = FakeClipboard(text: 'already there');
    tray = FakeTray();
    window = FakeWindow();
    panel = PanelController(
      pointer: FakePointer(),
      window: window,
      pollInterval: const Duration(days: 1),
    );
    quitCount = 0;
    addTearDown(panel.dispose);
  });

  test(
    'start sets up the panel and the tray and records what is on the clipboard',
    () async {
      final shell = buildShell();
      await shell.start();

      expect(shell.panelReady, isTrue);
      expect(shell.trayReady, isTrue);
      expect(window.prepared, isTrue);
      expect(clipboard.isWatched, isTrue);
      expect(texts(), ['already there']);
    },
  );

  test('records what other apps copy, in order', () async {
    final shell = buildShell();
    await shell.start();

    clipboard.copyFromElsewhere('first');
    await pumpEventQueue();
    clipboard.copyFromElsewhere('second');
    await pumpEventQueue();

    expect(texts(), ['second', 'first', 'already there']);
  });

  test('a clipboard holding no text records nothing', () async {
    clipboard.text = null;
    await buildShell().start();
    expect(history.isEmpty, isTrue);
  });

  test('picking an entry puts it on the clipboard, moves it up and closes the panel', () async {
    history
      ..record('older')
      ..record('newer');
    clipboard.text = null;
    final shell = buildShell();
    await shell.start();
    panel.toggle();
    expect(panel.isOpen, isTrue);

    shell.copy(history.entries.last);
    await pumpEventQueue();

    expect(clipboard.written, ['older']);
    expect(texts(), ['older', 'newer']);
    expect(panel.isOpen, isFalse);
  });

  test(
    'picking an entry works where clipboard changes cannot be watched',
    () async {
      clipboard = FakeClipboard(canWatch: false);
      history
        ..record('older')
        ..record('newer');
      final shell = buildShell();
      await shell.start();
      expect(clipboard.isWatched, isFalse);

      shell.copy(history.entries.last);

      expect(clipboard.written, ['older']);
      expect(texts(), ['older', 'newer']);
    },
  );

  group('tray menu', () {
    test('toggles the panel', () async {
      await buildShell().start();
      tray.actions!.onTogglePanel();
      expect(panel.isOpen, isTrue);
      tray.actions!.onTogglePanel();
      expect(panel.isOpen, isFalse);
    });

    test('pausing stops recording until resumed', () async {
      await buildShell().start();

      tray.actions!.onPausedChanged(true);
      clipboard.copyFromElsewhere('secret');
      await pumpEventQueue();
      expect(texts(), ['already there']);

      tray.actions!.onPausedChanged(false);
      clipboard.copyFromElsewhere('public');
      await pumpEventQueue();
      expect(texts(), ['public', 'already there']);
    });

    test('clearing keeps pinned entries', () async {
      await buildShell().start();
      clipboard.copyFromElsewhere('keep me');
      await pumpEventQueue();
      history.togglePin(history.entries.first.id);

      tray.actions!.onClearHistory();

      expect(texts(), ['keep me']);
    });

    test('quitting saves first, then takes the icon down', () async {
      await buildShell().start();
      clipboard.copyFromElsewhere('last copy');
      await pumpEventQueue();

      tray.actions!.onQuit();
      await pumpEventQueue();

      expect(
        [for (final entry in store.saved) entry.text],
        ['last copy', 'already there'],
      );
      expect(tray.disposed, isTrue);
      expect(quitCount, 1);
      expect(clipboard.isWatched, isFalse);
    });
  });

  test('still starts when the system has no tray', () async {
    tray = FakeTray(supported: false);
    final shell = buildShell();
    await shell.start();
    expect(shell.trayReady, isFalse);
    expect(shell.panelReady, isTrue);
  });
}
