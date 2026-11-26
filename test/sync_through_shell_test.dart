import 'package:flutter_test/flutter_test.dart';
import 'package:synchronize_clipboard/src/app_shell.dart';
import 'package:synchronize_clipboard/src/history/clipboard_history.dart';
import 'package:synchronize_clipboard/src/shell/panel_controller.dart';
import 'package:synchronize_clipboard/src/sync/sync_ports.dart';
import 'package:synchronize_clipboard/src/sync/sync_service.dart';

import 'fakes.dart';
import 'sync/memory_network.dart';
import 'sync/sync_service_test.dart' show eventually, pairDevices, settle;

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
    await pairDevices(network, mac.sync, pc.sync);
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

  group('deleting', () {
    Future<void> shareThree() async {
      await pair();
      for (final text in ['one', 'two', 'three']) {
        mac.clipboard.copyFromElsewhere(text);
        await eventually(() => pc.texts.contains(text));
      }
    }

    test('an entry deleted on one computer goes from the other too', () async {
      await shareThree();

      mac.history.remove(mac.history.entries[1].id);
      await eventually(() => pc.texts.length == 2);

      expect(mac.texts, ['three', 'one']);
      expect(pc.texts, ['three', 'one']);
    });

    test('it works in the other direction as well', () async {
      await shareThree();

      pc.history.remove(pc.history.entries.last.id);
      await eventually(() => mac.texts.length == 2);

      expect(mac.texts, ['three', 'two']);
    });

    test(
      'bringing a deleted entry back restores it everywhere, in place',
      () async {
        await shareThree();
        final removed = mac.history.entries[1];
        mac.history.remove(removed.id);
        await eventually(() => pc.texts.length == 2);

        mac.history.restore(removed);
        await eventually(() => pc.texts.length == 3);

        expect(mac.texts, ['three', 'two', 'one']);
        // The two pretend computers keep separate clocks, so only what is
        // in the other one's list is compared, not its order.
        expect(pc.texts, unorderedEquals(['three', 'two', 'one']));
        expect(
          pc.clipboard.text,
          'three',
          reason: 'the clipboard is untouched',
        );
      },
    );

    test('a delete is not passed back and forth', () async {
      await shareThree();
      mac.history.remove(mac.history.entries.first.id);
      await eventually(() => pc.texts.length == 2);
      await settle();
      final after = trafficCount();
      await settle();

      expect(trafficCount(), after);
    });

    test(
      'clearing the history clears it everywhere, keeping pinned entries',
      () async {
        await shareThree();
        pc.history.togglePin(pc.history.entries.last.id);

        mac.history.clearUnpinned();
        await eventually(() => pc.texts.length == 1);

        expect(mac.texts, isEmpty);
        expect(pc.texts, ['one']);
      },
    );

    test(
      'a deleted picture or file stays this computer\'s own business',
      () async {
        await pair();
        mac.history.recordFiles([r'C:\Docs\a.txt']);
        await settle();
        final before = trafficCount();

        mac.history.remove(mac.history.entries.first.id);
        await settle();

        expect(trafficCount(), before);
      },
    );

    test(
      'nothing is sent about deletes before the computers are paired',
      () async {
        mac.clipboard.copyFromElsewhere('private');
        await settle();
        mac.history.remove(mac.history.entries.single.id);
        await settle();

        expect(network.links, isEmpty);
      },
    );
  });

  group('sharing older history', () {
    setUp(() async {
      // Things copied before the two ever met.
      for (final text in ['old one', 'old two']) {
        mac.clipboard.copyFromElsewhere(text);
        await eventually(() => mac.texts.contains(text));
      }
    });

    test('is off unless asked for', () async {
      await pair();
      await settle();

      expect(pc.texts, isEmpty);
    });

    test(
      'a newly connected computer is given what was already there',
      () async {
        await mac.sync.setShareHistory(true);
        await pair();
        await eventually(() => pc.texts.length == 2);

        expect(pc.texts, ['old two', 'old one']);
        expect(
          [for (final entry in pc.history.entries) entry.copiedAt],
          [for (final entry in mac.history.entries) entry.copiedAt],
          reason: 'they keep the times they were copied at',
        );
        expect(
          pc.history.entries.every((entry) => entry.source == 'Mac'),
          isTrue,
        );
        expect(
          pc.clipboard.text,
          isNull,
          reason: 'the clipboard is not touched',
        );
        expect(pc.clipboard.written, isEmpty);
      },
    );

    test('it is given only once, not on every reconnect', () async {
      await mac.sync.setShareHistory(true);
      await pair();
      await eventually(() => pc.texts.length == 2);
      pc.history.remove(pc.history.entries.first.id);
      await eventually(() => mac.texts.length == 1);

      for (final link in network.links) {
        link.sever();
      }
      await eventually(() => mac.sync.peers.isEmpty);
      network.announce();
      await eventually(() => mac.sync.peers.isNotEmpty);
      await settle();

      expect(pc.texts, ['old one']);
    });

    test('it can be sent on request to computers already connected', () async {
      await pair();
      await settle();
      expect(pc.texts, isEmpty);

      mac.shell.shareHistory();
      await eventually(() => pc.texts.length == 2);

      expect(pc.texts, ['old two', 'old one']);
    });

    test(
      'entries the other computer already has are left as they are',
      () async {
        pc.clipboard.copyFromElsewhere('old one');
        await eventually(() => pc.texts.isNotEmpty);
        final mine = pc.history.entries.single;
        await pair();

        mac.shell.shareHistory();
        await eventually(() => pc.texts.length == 2);

        expect(pc.history.entries.firstWhere((e) => e.text == 'old one'), mine);
      },
    );

    test('a long history arrives whole', () async {
      for (var i = 0; i < 120; i++) {
        mac.history.record('entry $i');
      }
      await pair();

      mac.shell.shareHistory();
      await eventually(() => pc.texts.length == 122);

      expect(pc.texts, mac.texts);
    });
  });
}
