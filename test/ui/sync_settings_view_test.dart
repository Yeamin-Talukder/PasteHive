import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synchronize_clipboard/src/app_shell.dart' show PanelPage;
import 'package:synchronize_clipboard/src/history/clipboard_history.dart';
import 'package:synchronize_clipboard/src/shell/panel_controller.dart';
import 'package:synchronize_clipboard/src/sync/sync_ports.dart';
import 'package:synchronize_clipboard/src/sync/sync_service.dart';
import 'package:synchronize_clipboard/src/ui/clipboard_panel.dart';
import 'package:synchronize_clipboard/src/ui/panel_scene.dart';
import 'package:synchronize_clipboard/src/ui/sync_settings_view.dart';

import '../fakes.dart';
import '../sync/memory_network.dart';
import '../sync/sync_service_test.dart' show eventually;

const hiddenKey = '•••••-•••••-•••••-•••••';

void main() {
  late MemoryNetwork network;
  late SyncService sync;
  late SyncService other;
  late int doneCount;

  SyncService device(String id, String name) => SyncService(
    discovery: network.discovery('10.0.0.$id'),
    transport: network.transport('10.0.0.$id'),
    store: MemorySyncSettingsStore(
      SyncSettings(deviceId: id, deviceName: name),
    ),
    defaultDeviceName: () => name,
    pingInterval: const Duration(days: 1),
  );

  /// Turns both clocks a little: the test's pretend one and the real one.
  /// The sync service does part of its work on each, depending on where a
  /// piece of it was started, so neither alone lets it finish.
  Future<void> step(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }

  /// Runs [body] to completion, then redraws.
  Future<void> real(WidgetTester tester, Future<void> Function() body) async {
    var done = false;
    Object? failure;
    await tester.runAsync(() async {
      unawaited(
        body().then(
          (_) => done = true,
          onError: (Object error) {
            failure = error;
            done = true;
          },
        ),
      );
    });
    for (var i = 0; i < 600 && !done; i++) {
      await step(tester);
    }
    expect(failure, isNull);
    expect(done, isTrue, reason: 'the work never finished');
    await tester.pump();
  }

  /// Lets work started by a tap (key derivation, saving) finish.
  Future<void> afterTap(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await step(tester);
    }
    await tester.pump();
  }

  Future<void> pumpView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SyncSettingsView(
          sync: sync,
          hasMaterial: true,
          onDone: () => doneCount++,
        ),
      ),
    );
  }

  Future<void> shutDown(WidgetTester tester) async {
    await real(tester, () async {
      await sync.shutdown();
      await other.shutdown();
    });
  }

  CupertinoSwitch switchOf(WidgetTester tester) =>
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch));

  setUp(() {
    network = MemoryNetwork();
    sync = device('1', 'Office PC');
    other = device('2', "Sam's MacBook");
    doneCount = 0;
  });

  testWidgets(
    'without a key it explains what to do and cannot be switched on',
    (tester) async {
      await real(tester, sync.load);
      await pumpView(tester);

      expect(find.text('Create a Key'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
      expect(
        find.text('Add a sync key to connect your devices.'),
        findsOneWidget,
      );
      expect(switchOf(tester).value, isFalse);
      expect(switchOf(tester).onChanged, isNull);
    },
  );

  testWidgets('creating a key shows it, switches sync on and starts looking', (
    tester,
  ) async {
    await real(tester, sync.load);
    await pumpView(tester);

    await tester.tap(find.text('Create a Key'));
    await afterTap(tester);

    expect(sync.hasKey, isTrue);
    expect(find.text(sync.formattedKey!), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(switchOf(tester).value, isTrue);
    expect(
      find.text('Looking for your other devices on this network…'),
      findsOneWidget,
    );
    expect(find.textContaining('“Office PC”'), findsOneWidget);
    await shutDown(tester);
  });

  testWidgets('a saved key stays hidden until asked for', (tester) async {
    await real(tester, () async {
      await sync.load();
      await sync.createKey();
    });
    await pumpView(tester);

    expect(find.text(hiddenKey), findsOneWidget);
    expect(find.text(sync.formattedKey!), findsNothing);

    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text(sync.formattedKey!), findsOneWidget);

    await tester.tap(find.text('Hide'));
    await tester.pump();
    expect(find.text(hiddenKey), findsOneWidget);
    await shutDown(tester);
  });

  testWidgets('joining needs a complete key', (tester) async {
    await real(tester, () async {
      await sync.load();
      await other.load();
      await other.createKey();
    });
    await pumpView(tester);

    await tester.enterText(find.byType(TextField), 'abcde-fghjk');
    await tester.tap(find.text('Join'));
    await afterTap(tester);
    expect(find.textContaining('not a complete key'), findsOneWidget);
    expect(sync.hasKey, isFalse);

    // Typed the way people type: lower case, spaces instead of dashes.
    await tester.enterText(
      find.byType(TextField),
      other.formattedKey!.toLowerCase().replaceAll('-', ' '),
    );
    await tester.tap(find.text('Join'));
    await afterTap(tester);

    expect(sync.formattedKey, other.formattedKey);
    expect(find.textContaining('not a complete key'), findsNothing);
    expect(find.text(hiddenKey), findsOneWidget);
    await shutDown(tester);
  });

  testWidgets('removing the key asks first', (tester) async {
    await real(tester, () async {
      await sync.load();
      await sync.createKey();
    });
    await pumpView(tester);

    await tester.tap(find.text('Remove Key…'));
    await tester.pump();
    expect(find.text('Sync stops on this device.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(sync.hasKey, isTrue);

    await tester.tap(find.text('Remove Key…'));
    await tester.pump();
    await tester.tap(find.text('Remove'));
    await afterTap(tester);

    expect(sync.hasKey, isFalse);
    expect(find.text('Create a Key'), findsOneWidget);
    await shutDown(tester);
  });

  testWidgets('the switch turns sync off and on', (tester) async {
    await real(tester, () async {
      await sync.load();
      await sync.createKey();
    });
    await pumpView(tester);

    await tester.tap(find.byType(CupertinoSwitch));
    await afterTap(tester);
    await tester.pumpAndSettle();
    expect(sync.enabled, isFalse);
    expect(find.text('Sync is off.'), findsOneWidget);

    await tester.tap(find.byType(CupertinoSwitch));
    await afterTap(tester);
    await tester.pumpAndSettle();
    expect(sync.running, isTrue);
    await shutDown(tester);
  });

  testWidgets('lists a connected device by name', (tester) async {
    await real(tester, () async {
      await sync.load();
      await other.load();
      await sync.createKey();
      await other.useKey(sync.formattedKey!);
      network.announce();
      await eventually(() => sync.peers.isNotEmpty);
    });
    await pumpView(tester);

    expect(find.text("Sam's MacBook"), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.textContaining('Looking for'), findsNothing);
    await shutDown(tester);
  });

  testWidgets('points out a nearby device with a different key', (
    tester,
  ) async {
    await real(tester, () async {
      await sync.load();
      await other.load();
      await sync.createKey();
      await other.createKey();
      network.announce();
      await eventually(() => sync.differentKeyNearby);
    });
    await pumpView(tester);

    expect(find.textContaining('using a different key'), findsOneWidget);
    await shutDown(tester);
  });

  testWidgets('says so when the network cannot be used', (tester) async {
    final transport = network.transport('10.0.0.9')..failToListen = true;
    sync = SyncService(
      discovery: network.discovery('10.0.0.9'),
      transport: transport,
      store: MemorySyncSettingsStore(),
      defaultDeviceName: () => 'PC',
    );
    await real(tester, () async {
      await sync.load();
      await sync.createKey();
    });
    await pumpView(tester);

    expect(find.textContaining('firewall'), findsOneWidget);
    await shutDown(tester);
  });

  testWidgets('the back button and Escape return to the list', (tester) async {
    await real(tester, sync.load);
    await pumpView(tester);
    await tester.pump();

    await tester.tap(find.text('Clipboard'));
    expect(doneCount, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(doneCount, 2);
  });

  testWidgets('fits at the largest text size without overflowing', (
    tester,
  ) async {
    await real(tester, () async {
      await sync.load();
      await sync.createKey();
    });
    tester.view.physicalSize = const Size(440, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(440, 540),
            textScaler: TextScaler.linear(2),
          ),
          child: SyncSettingsView(sync: sync, hasMaterial: true, onDone: () {}),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await shutDown(tester);
  });

  group('in the panel', () {
    late PanelController controller;
    late ValueNotifier<PanelPage> page;
    late ClipboardHistory history;

    // Made here rather than inside the tests: their timers are real ones
    // then, and do not count as left-overs of the test's pretend clock.
    setUp(() {
      controller = PanelController(
        pointer: FakePointer(),
        window: FakeWindow(),
        pollInterval: const Duration(days: 1),
      )..start();
      page = ValueNotifier(PanelPage.history);
      history = historyWith(['one']);
      addTearDown(controller.dispose);
    });

    Future<void> pumpScene(WidgetTester tester) async {
      tester.view.physicalSize = const Size(440, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PanelScene(
            controller: controller,
            history: history,
            onCopy: (_) {},
            sync: sync,
            page: page,
          ),
        ),
      );
      controller.open();
      await tester.pumpAndSettle();
    }

    testWidgets('the footer shows the sync state and opens the settings', (
      tester,
    ) async {
      await real(tester, sync.load);
      await pumpScene(tester);

      expect(find.text('Sync Off'), findsOneWidget);
      await tester.tap(find.text('Sync Off'));
      await tester.pumpAndSettle();

      expect(page.value, PanelPage.sync);
      expect(find.byType(SyncSettingsView), findsOneWidget);
      expect(find.byType(ClipboardPanel), findsNothing);

      await tester.tap(find.text('Clipboard'));
      await tester.pumpAndSettle();
      expect(page.value, PanelPage.history);
      expect(find.text('one'), findsOneWidget);
    });

    testWidgets('the footer names the connected device', (tester) async {
      await real(tester, () async {
        await sync.load();
        await other.load();
        await sync.createKey();
        await other.useKey(sync.formattedKey!);
        network.announce();
        await eventually(() => sync.peers.isNotEmpty);
      });
      await pumpScene(tester);

      expect(find.text("Sam's MacBook"), findsOneWidget);

      await real(tester, () async {
        await other.shutdown();
        await eventually(() => sync.peers.isEmpty);
      });
      expect(find.text('Searching…'), findsOneWidget);
      await shutDown(tester);
    });
  });

  group('summary', () {
    test('covers every state in a word or two', () async {
      await sync.load();
      expect(syncSummaryOf(sync).label, 'Sync Off');
      expect(syncSummaryOf(sync).connected, isFalse);

      await sync.createKey();
      expect(syncSummaryOf(sync).label, 'Searching…');

      await other.load();
      await other.useKey(sync.formattedKey!);
      final third = device('3', 'Laptop');
      await third.load();
      await third.useKey(sync.formattedKey!);
      network.announce();
      await eventually(() => sync.peers.length == 2);
      expect(syncSummaryOf(sync).label, '2 Devices');
      expect(syncSummaryOf(sync).connected, isTrue);

      await third.shutdown();
      await eventually(() => sync.peers.length == 1);
      expect(syncSummaryOf(sync).label, "Sam's MacBook");

      await sync.setEnabled(false);
      expect(syncSummaryOf(sync).label, 'Sync Off');
      await other.shutdown();
    });
  });
}
