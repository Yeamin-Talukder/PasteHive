import 'package:flutter_test/flutter_test.dart';
import 'package:synchronize_clipboard/src/sync/sync_ports.dart';
import 'package:synchronize_clipboard/src/sync/sync_service.dart';

import 'memory_network.dart';

/// One simulated device on a [MemoryNetwork].
class Device {
  Device(
    MemoryNetwork network, {
    required String id,
    required this.name,
    Duration Function()? clock,
  }) : store = MemorySyncSettingsStore(
         SyncSettings(deviceId: id, deviceName: name),
       ),
       discovery = network.discovery('10.0.0.$id'),
       transport = network.transport('10.0.0.$id') {
    service = build(clock: clock);
  }

  final String name;
  final MemorySyncSettingsStore store;
  final MemoryDiscovery discovery;
  final MemoryTransport transport;
  late SyncService service;
  final List<String> received = [];

  SyncService build({Duration Function()? clock}) {
    final service = SyncService(
      discovery: discovery,
      transport: transport,
      store: store,
      defaultDeviceName: () => name,
      clock: clock,
      // The tests call tick() themselves.
      pingInterval: const Duration(days: 1),
    );
    service.remoteClips.listen((clip) => received.add(clip.text));
    return service;
  }

  List<String> get peerNames => [for (final peer in service.peers) peer.name];
}

/// Waits until [condition] holds, failing if it never does.
Future<void> eventually(bool Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting${reason == null ? '' : ' for $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Lets anything already in motion finish, to show that nothing more happens.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

void main() {
  late MemoryNetwork network;
  late Device mac;
  late Device pc;
  late Duration now;

  setUp(() {
    network = MemoryNetwork();
    now = Duration.zero;
    // Ids are compared as text: "1" connects to "2".
    mac = Device(network, id: '1', name: "Sam's MacBook", clock: () => now);
    pc = Device(network, id: '2', name: 'Office PC', clock: () => now);
    addTearDown(() async {
      await mac.service.shutdown();
      await pc.service.shutdown();
    });
  });

  /// Gives both devices the same key and waits for them to connect.
  Future<void> pair() async {
    await mac.service.load();
    await pc.service.load();
    await mac.service.createKey();
    expect(await pc.service.useKey(mac.service.formattedKey!), isTrue);
    network.announce();
    await eventually(
      () => mac.service.peers.isNotEmpty && pc.service.peers.isNotEmpty,
      reason: 'the devices to connect',
    );
  }

  group('before a key is set', () {
    test(
      'a first launch makes an identity and stays off the network',
      () async {
        final fresh = SyncService(
          discovery: network.discovery('10.0.0.9'),
          transport: network.transport('10.0.0.9'),
          store: MemorySyncSettingsStore(),
          defaultDeviceName: () => 'New PC',
        );
        await fresh.load();

        expect(fresh.deviceName, 'New PC');
        expect(fresh.deviceId, matches(r'^[0-9a-f]{32}$'));
        expect(fresh.enabled, isFalse);
        expect(fresh.hasKey, isFalse);
        expect(fresh.running, isFalse);
        expect(fresh.formattedKey, isNull);
      },
    );

    test('switching sync on without a key opens nothing', () async {
      await mac.service.load();
      await mac.service.setEnabled(true);

      expect(mac.service.enabled, isTrue);
      expect(mac.service.running, isFalse);
      expect(mac.discovery.isAnnouncing, isFalse);
    });

    test('an incomplete key is refused and changes nothing', () async {
      await mac.service.load();
      expect(await mac.service.useKey('ABCDE-FGHJK'), isFalse);
      expect(mac.service.hasKey, isFalse);
      expect(mac.store.saved!.key, isNull);
    });
  });

  group('pairing', () {
    test('creating a key switches sync on and starts announcing', () async {
      await mac.service.load();
      await mac.service.createKey();

      expect(mac.service.hasKey, isTrue);
      expect(mac.service.enabled, isTrue);
      expect(mac.service.running, isTrue);
      expect(mac.discovery.isAnnouncing, isTrue);
      expect(mac.store.saved!.key, hasLength(20));
    });

    test(
      'two devices with the same key connect and see each other by name',
      () async {
        await pair();

        expect(mac.peerNames, ['Office PC']);
        expect(pc.peerNames, ["Sam's MacBook"]);
      },
    );

    test('only one of the two makes the connection', () async {
      await pair();
      network.announce();
      network.announce();
      await settle();

      expect(network.links, hasLength(1));
      expect(mac.transport.connectCount, 1);
      expect(pc.transport.connectCount, 0);
    });

    test('the other one connects if the first never hears it', () async {
      await mac.service.load();
      await pc.service.load();
      await mac.service.createKey();
      await pc.service.useKey(mac.service.formattedKey!);

      final macBeacon = mac.discovery.self!;
      pc.discovery.hear(macBeacon);
      await settle();
      expect(pc.transport.connectCount, 0, reason: 'giving the Mac its turn');

      now += const Duration(seconds: 7);
      pc.discovery.hear(macBeacon);
      await eventually(() => pc.service.peers.isNotEmpty);

      expect(pc.transport.connectCount, 1);
      expect(mac.peerNames, ['Office PC']);
    });

    test(
      'a device with a different key is not connected, and is noticed',
      () async {
        await mac.service.load();
        await pc.service.load();
        await mac.service.createKey();
        await pc.service.createKey();
        network.announce();
        await eventually(() => mac.service.differentKeyNearby);

        expect(pc.service.differentKeyNearby, isTrue);
        expect(mac.service.peers, isEmpty);
        expect(network.links, isEmpty);

        // It is forgotten once it has not been heard for a while.
        now += const Duration(seconds: 20);
        mac.service.tick();
        expect(mac.service.differentKeyNearby, isFalse);
      },
    );

    test('joining with the right key afterwards connects', () async {
      await mac.service.load();
      await pc.service.load();
      await mac.service.createKey();
      await pc.service.createKey();
      network.announce();
      await eventually(() => mac.service.differentKeyNearby);

      await pc.service.useKey(mac.service.formattedKey!);
      network.announce();
      await eventually(() => mac.service.peers.isNotEmpty);

      expect(pc.peerNames, ["Sam's MacBook"]);
    });

    test('tells listeners when a device connects', () async {
      await mac.service.load();
      var notifications = 0;
      mac.service.addListener(() => notifications++);
      await pair();
      expect(notifications, greaterThanOrEqualTo(2));
    });
  });

  group('copying', () {
    test('text copied on one device arrives on the other', () async {
      await pair();

      mac.service.sendClip('from the mac');
      pc.service.sendClip('from the pc\nsecond line “quoted”');
      await eventually(() => pc.received.isNotEmpty && mac.received.isNotEmpty);

      expect(pc.received, ['from the mac']);
      expect(mac.received, ['from the pc\nsecond line “quoted”']);
    });

    test('several copies arrive in the order they were made', () async {
      await pair();
      for (var i = 0; i < 10; i++) {
        mac.service.sendClip('copy $i');
      }
      await eventually(() => pc.received.length == 10);
      expect(pc.received, [for (var i = 0; i < 10; i++) 'copy $i']);
    });

    test('the copied text is not readable on the network', () async {
      await pair();
      mac.service.sendClip('hunter2-hunter2');
      await eventually(() => pc.received.isNotEmpty);

      final wire = String.fromCharCodes([
        for (final chunk in network.links.single.traffic) ...chunk,
      ]);
      expect(wire, isNot(contains('hunter2')));
    });

    test('empty and over-long text is not sent', () async {
      await pair();
      mac.service
        ..sendClip('')
        ..sendClip('x' * (mac.service.maxTextLength + 1))
        ..sendClip('fine');
      await eventually(() => pc.received.isNotEmpty);
      await settle();
      expect(pc.received, ['fine']);
    });

    test('sending with nobody connected does nothing', () async {
      await mac.service.load();
      await mac.service.createKey();
      mac.service.sendClip('into the void');
      await settle();
      expect(network.links, isEmpty);
    });
  });

  group('losing a device', () {
    test(
      'a dropped connection removes the device, and it comes back',
      () async {
        await pair();

        network.links.single.sever();
        await eventually(
          () => mac.service.peers.isEmpty && pc.service.peers.isEmpty,
        );

        network.announce();
        await eventually(
          () => mac.service.peers.isNotEmpty && pc.service.peers.isNotEmpty,
        );
        mac.service.sendClip('after reconnecting');
        await eventually(() => pc.received.isNotEmpty);
        expect(pc.received, ['after reconnecting']);
      },
    );

    test('a device that has gone silent is dropped', () async {
      await pair();

      now += const Duration(seconds: 20);
      mac.service.tick();
      expect(mac.service.peers, isNotEmpty, reason: 'not long enough yet');
      // The ping just sent is answered, which counts as hearing from it.
      await settle();

      now += const Duration(seconds: 31);
      mac.service.tick();
      await eventually(() => mac.service.peers.isEmpty);
    });

    test('pings keep a quiet connection alive', () async {
      await pair();
      for (var i = 0; i < 5; i++) {
        now += const Duration(seconds: 20);
        mac.service.tick();
        pc.service.tick();
        await settle();
      }
      expect(mac.peerNames, ['Office PC']);
      expect(pc.peerNames, ["Sam's MacBook"]);
    });

    test('switching sync off disconnects and leaves the network', () async {
      await pair();

      await pc.service.setEnabled(false);

      expect(pc.service.running, isFalse);
      expect(pc.service.peers, isEmpty);
      expect(pc.discovery.isAnnouncing, isFalse);
      expect(pc.service.hasKey, isTrue, reason: 'the key is kept');
      await eventually(() => mac.service.peers.isEmpty);

      await pc.service.setEnabled(true);
      network.announce();
      await eventually(() => mac.service.peers.isNotEmpty);
    });

    test('removing the key switches sync off and forgets the key', () async {
      await pair();

      await pc.service.removeKey();

      expect(pc.service.hasKey, isFalse);
      expect(pc.service.enabled, isFalse);
      expect(pc.service.running, isFalse);
      expect(pc.store.saved!.key, isNull);
      await eventually(() => mac.service.peers.isEmpty);
    });
  });

  group('between launches', () {
    test('sync comes back on by itself with the saved key', () async {
      await pair();
      await pc.service.shutdown();
      await eventually(() => mac.service.peers.isEmpty);

      pc.service = pc.build(clock: () => now);
      await pc.service.load();
      network.announce();
      await eventually(() => mac.service.peers.isNotEmpty);

      expect(pc.service.formattedKey, mac.service.formattedKey);
      expect(pc.service.deviceId, '2');
    });
  });

  group('when the network says no', () {
    test('not being allowed to listen is reported, not thrown', () async {
      mac.transport.failToListen = true;
      await mac.service.load();
      await mac.service.createKey();

      expect(mac.service.running, isFalse);
      expect(mac.service.error, contains('firewall'));
      expect(mac.discovery.isAnnouncing, isFalse);

      mac.transport.failToListen = false;
      await mac.service.setEnabled(true);
      expect(mac.service.running, isTrue);
      expect(mac.service.error, isNull);
    });

    test(
      'a refused connection is tried again on the next announcement',
      () async {
        await mac.service.load();
        await pc.service.load();
        await mac.service.createKey();
        await pc.service.useKey(mac.service.formattedKey!);

        network.refuseConnections = true;
        network.announce();
        await settle();
        expect(mac.service.peers, isEmpty);
        expect(mac.transport.connectCount, 1);

        network.refuseConnections = false;
        network.announce();
        await eventually(() => mac.service.peers.isNotEmpty);
      },
    );
  });
}
