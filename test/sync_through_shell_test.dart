import 'package:flutter_test/flutter_test.dart';
import 'package:synchronize_clipboard/src/app_shell.dart';
import 'package:synchronize_clipboard/src/history/clipboard_history.dart';
import 'package:synchronize_clipboard/src/shell/panel_controller.dart';
import 'package:synchronize_clipboard/src/sync/sync_ports.dart';
import 'package:synchronize_clipboard/src/sync/sync_service.dart';

import 'fakes.dart';
import 'sync/memory_network.dart';
import 'sync/sync_service_test.dart' show eventually, settle;

/// A whole (pretend) computer: clipboard, history, panel, tray and sync.
class Computer {
  Computer(MemoryNetwork network, {required String id, required String name})
    : history = historyWith([]),
      sync = SyncService(
        discovery: network.discovery('10.0.0.$id'),
        transport: network.transport('10.0.0.$id'),
        store: MemorySyncSettingsStore(
          SyncSettings(deviceId: id, deviceName: name),
        ),
        defaultDeviceName: () => name,
        pingInterval: const Duration(days: 1),
      ) {
    panel = PanelController(
      pointer: pointer,
      window: window,
      pollInterval: const Duration(days: 1),
    );
    shell = AppShell(
      history: history,
      panel: panel,
      sync: sync,
      clipboard: clipboard,
      tray: tray,
      onQuit: () async {},
    );
  }

  final ClipboardHistory history;
  final SyncService sync;
  final clipboard = FakeClipboard();
  final tray = FakeTray();
  final window = FakeWindow();
  final pointer = FakePointer();
  late final PanelController panel;
  late final AppShell shell;

  List<String> get texts => [for (final entry in history.entries) entry.text];
}

void main() {
  late MemoryNetwork network;
  late Computer mac;
  late Computer pc;

  setUp(() async {
    network = MemoryNetwork();
    mac = Computer(network, id: '1', name: 'Mac');
    pc = Computer(network, id: '2', name: 'PC');
    addTearDown(() async {
      await mac.shell.quit();
      await pc.shell.quit();
    });
    await mac.shell.start();
    await pc.shell.start();
  });

  Future<void> pair() async {
    await mac.sync.createKey();
    await pc.sync.useKey(mac.sync.formattedKey!);
    network.announce();
    await eventually(
      () => mac.sync.peers.isNotEmpty && pc.sync.peers.isNotEmpty,
    );
  }

  /// How many encrypted messages have crossed the network so far.
  int trafficCount() =>
      network.links.fold(0, (sum, link) => sum + link.traffic.length);

  test('nothing is sent before the devices are paired', () async {
    mac.clipboard.copyFromElsewhere('private');
    await settle();

    expect(mac.texts, ['private']);
    expect(pc.texts, isEmpty);
    expect(network.links, isEmpty);
  });

  test(
    'text copied on one computer lands on the other one\'s clipboard and list',
    () async {
      await pair();

      mac.clipboard.copyFromElsewhere('copied on the mac');
      await eventually(() => pc.texts.isNotEmpty);

      expect(pc.clipboard.text, 'copied on the mac');
      expect(pc.clipboard.written, ['copied on the mac']);
      expect(pc.texts, ['copied on the mac']);

      pc.clipboard.copyFromElsewhere('copied on the pc');
      await eventually(() => mac.texts.length == 2);

      expect(mac.clipboard.text, 'copied on the pc');
      expect(mac.texts, ['copied on the pc', 'copied on the mac']);
    },
  );

  test('a copy does not bounce back and forth', () async {
    await pair();

    mac.clipboard.copyFromElsewhere('once');
    await eventually(() => pc.texts.isNotEmpty);
    await settle();
    final afterDelivery = trafficCount();
    await settle();

    expect(trafficCount(), afterDelivery, reason: 'nothing more was sent');
    expect(pc.clipboard.written, ['once']);
    expect(mac.clipboard.written, isEmpty);
    expect(mac.texts, ['once']);
    expect(pc.texts, ['once']);
  });

  test('picking an old entry from the list sends it too', () async {
    await pair();
    mac.clipboard.copyFromElsewhere('first');
    await eventually(() => pc.texts.length == 1);
    mac.clipboard.copyFromElsewhere('second');
    await eventually(() => pc.texts.length == 2);

    pc.shell.copy(pc.history.entries.last);
    await eventually(() => mac.clipboard.text == 'first');

    expect(mac.texts, ['first', 'second']);
    expect(pc.texts, ['first', 'second']);
  });

  test('copying the same text again is not sent twice', () async {
    await pair();
    mac.clipboard.copyFromElsewhere('same');
    await eventually(() => pc.texts.isNotEmpty);
    await settle();
    final before = trafficCount();

    mac.clipboard.copyFromElsewhere('same');
    await settle();

    expect(trafficCount(), before);
  });

  group('while paused', () {
    test('this computer sends nothing', () async {
      await pair();
      mac.history.paused = true;

      mac.clipboard.copyFromElsewhere('secret');
      await settle();

      expect(pc.texts, isEmpty);
      expect(pc.clipboard.text, isNull);
    });

    test('this computer takes nothing in', () async {
      await pair();
      pc.history.paused = true;

      mac.clipboard.copyFromElsewhere('for the pc');
      await settle();
      expect(pc.clipboard.text, isNull);
      expect(pc.texts, isEmpty);

      pc.history.paused = false;
      mac.clipboard.copyFromElsewhere('later');
      await eventually(() => pc.texts.isNotEmpty);
      expect(pc.clipboard.text, 'later');
    });
  });

  group('sync settings', () {
    test('the tray item opens the panel on the settings and pins it open', () {
      pc.tray.actions!.onOpenSyncSettings();

      expect(pc.panel.isOpen, isTrue);
      expect(pc.shell.page.value, PanelPage.sync);
      expect(pc.panel.holdOpen, isTrue);

      // Neither the pointer being elsewhere nor a click elsewhere closes it.
      pc.pointer.cursor = const Offset(100, 800);
      pc.panel.poll();
      pc.window.blur();
      expect(pc.panel.isOpen, isTrue);

      pc.panel.dismiss();
      expect(pc.panel.isOpen, isFalse);
    });

    test('going back to the list lets the panel close by itself again', () {
      pc.tray.actions!.onOpenSyncSettings();
      pc.shell.page.value = PanelPage.history;
      expect(pc.panel.holdOpen, isFalse);
    });

    test('the next visit starts on the list', () {
      pc.tray.actions!.onOpenSyncSettings();
      pc.panel.dismiss();
      expect(pc.shell.page.value, PanelPage.sync);

      pc.panel.open();

      expect(pc.shell.page.value, PanelPage.history);
      expect(pc.panel.holdOpen, isFalse);
    });
  });

  test('quitting leaves the network', () async {
    await pair();
    await pc.shell.quit();

    expect(pc.sync.running, isFalse);
    await eventually(() => mac.sync.peers.isEmpty);
  });
}
