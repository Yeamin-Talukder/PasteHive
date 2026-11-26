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
import '../sync/sync_service_test.dart' show eventually, pairDevices;

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
    for (var i = 0; i < 800 && !done; i++) {
      await step(tester);
    }
    expect(failure, isNull);
    expect(done, isTrue, reason: 'the work never finished');
    await tester.pump();
  }

  /// Lets work started by a tap finish.
  Future<void> afterTap(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
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

  /// Both devices on, and each has heard the other.
  Future<void> bothOn(WidgetTester tester) async {
    await real(tester, () async {
      await sync.load();
      await other.load();
      await sync.setEnabled(true);
      await other.setEnabled(true);
      network.announce();
      await eventually(() => sync.nearby.isNotEmpty && other.nearby.isNotEmpty);
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

  testWidgets('while off it only offers to switch on', (tester) async {
    await real(tester, sync.load);
    await pumpView(tester);

    expect(switchOf(tester).value, isFalse);
    expect(find.textContaining('Switch on to find'), findsOneWidget);
    expect(find.text('Nearby Devices'), findsNothing);
  });

  testWidgets('switching on starts looking for devices', (tester) async {
    await real(tester, sync.load);
    await pumpView(tester);

    await tester.tap(find.byType(CupertinoSwitch));
    await afterTap(tester);
    await tester.pumpAndSettle();

    expect(sync.running, isTrue);
    expect(find.text('Nearby Devices'), findsOneWidget);
    expect(find.textContaining('Looking for devices'), findsOneWidget);
    expect(find.textContaining('“Office PC”'), findsOneWidget);
    await shutDown(tester);
  });

  testWidgets('lists a device nearby with a way to connect', (tester) async {
    await bothOn(tester);
    await pumpView(tester);

    expect(find.text("Sam's MacBook"), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.textContaining('No devices yet'), findsOneWidget);
    await shutDown(tester);
  });

  testWidgets('Connect asks the other device and shows the code to compare', (
    tester,
  ) async {
    await bothOn(tester);
    await pumpView(tester);

    await tester.tap(find.text('Connect'));
    await real(tester, () => eventually(() => other.requests.isNotEmpty));
    await afterTap(tester);

    final code = other.requests.single.code;
    expect(find.textContaining('Waiting for “Sam\'s MacBook”'), findsOneWidget);
    expect(
      find.text('${code.substring(0, 3)} ${code.substring(3)}'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await real(tester, () => eventually(() => other.requests.isEmpty));
    expect(find.textContaining('Waiting for'), findsNothing);
    await shutDown(tester);
  });

  testWidgets('a request from another device can be accepted', (tester) async {
    await bothOn(tester);
    await pumpView(tester);

    await real(tester, () async {
      unawaited(other.requestPairing(sync.deviceId));
      await eventually(() => sync.requests.isNotEmpty);
    });
    expect(find.text('“Sam\'s MacBook” wants to sync'), findsOneWidget);
    final code = sync.requests.single.code;
    expect(
      find.text('${code.substring(0, 3)} ${code.substring(3)}'),
      findsOneWidget,
    );

    await tester.tap(find.text('Accept'));
    await real(
      tester,
      () => eventually(() {
        network.announce();
        return sync.peers.isNotEmpty;
      }),
    );

    expect(find.textContaining('wants to sync'), findsNothing);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text("Sam's MacBook"), findsOneWidget);
    // The pairing connection is closed a moment after the answer is sent.
    await tester.pump(const Duration(seconds: 1));
    await shutDown(tester);
  });

  testWidgets('a request can be declined', (tester) async {
    await bothOn(tester);
    await pumpView(tester);
    await real(tester, () async {
      unawaited(other.requestPairing(sync.deviceId));
      await eventually(() => sync.requests.isNotEmpty);
    });

    await tester.tap(find.text('Decline'));
    await real(
      tester,
      () => eventually(() => other.outgoing?.state == OutgoingState.declined),
    );

    expect(find.textContaining('wants to sync'), findsNothing);
    expect(sync.hasKey, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await shutDown(tester);
  });

  testWidgets('says when the other device declined', (tester) async {
    await bothOn(tester);
    await pumpView(tester);

    await tester.tap(find.text('Connect'));
    await real(tester, () async {
      await eventually(() => other.requests.isNotEmpty);
      await other.decline(other.requests.single);
      await eventually(() => sync.outgoing?.state == OutgoingState.declined);
    });

    expect(find.text('“Sam\'s MacBook” declined'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.textContaining('declined'), findsNothing);
    await shutDown(tester);
  });

  testWidgets('stopping sync with all devices asks first', (tester) async {
    await real(tester, () async {
      await sync.load();
      await other.load();
      await pairDevices(network, sync, other);
    });
    await pumpView(tester);

    await tester.ensureVisible(find.text('Stop Syncing with All Devices…'));
    await tester.tap(find.text('Stop Syncing with All Devices…'));
    await tester.pump();
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(sync.hasKey, isTrue);

    await tester.tap(find.text('Stop Syncing with All Devices…'));
    await tester.pump();
    await tester.ensureVisible(find.text('Stop'));
    await tester.tap(find.text('Stop'));
    await afterTap(tester);

    expect(sync.hasKey, isFalse);
    expect(find.text('Stop Syncing with All Devices…'), findsNothing);
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
      await sync.setEnabled(true);
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
    await bothOn(tester);
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
        await pairDevices(network, sync, other);
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

      await sync.setEnabled(true);
      expect(syncSummaryOf(sync).label, 'Sync On');

      await other.load();
      final third = device('3', 'Laptop');
      await third.load();
      await pairDevices(network, sync, other);
      expect(syncSummaryOf(sync).label, "Sam's MacBook");
      expect(syncSummaryOf(sync).connected, isTrue);

      await pairDevices(network, third, sync);
      expect(syncSummaryOf(sync).label, '2 Devices');

      await third.shutdown();
      await other.shutdown();
      await eventually(() => sync.peers.isEmpty);
      expect(syncSummaryOf(sync).label, 'Searching…');

      await sync.setEnabled(false);
      expect(syncSummaryOf(sync).label, 'Sync Off');
    });
  });
}
