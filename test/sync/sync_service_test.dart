import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pastehive/src/sync/sync_ports.dart';
import 'package:pastehive/src/sync/sync_service.dart';

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

  List<String> get nearbyNames => [
    for (final device in service.nearby) device.name,
  ];
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

/// Has [asker] ask [answerer] to sync, has [answerer] accept, and waits
/// until the two are connected. Both must be loaded; sync is switched on for
/// them if it is not.
Future<void> pairDevices(
  MemoryNetwork network,
  SyncService asker,
  SyncService answerer,
) async {
  if (!asker.enabled) await asker.setEnabled(true);
  if (!answerer.enabled) await answerer.setEnabled(true);
  network.announce();
  await eventually(
    () => asker.nearby.any((device) => device.id == answerer.deviceId),
    reason: 'the asking device to see the other one',
  );
  unawaited(asker.requestPairing(answerer.deviceId));
  await eventually(() => answerer.requests.isNotEmpty, reason: 'the request');
  await answerer.accept(answerer.requests.first);
  await eventually(() {
    // Both restart with the shared key; they find each other again by
    // their announcements.
    network.announce();
    return asker.peers.any((peer) => peer.id == answerer.deviceId) &&
        answerer.peers.any((peer) => peer.id == asker.deviceId);
  }, reason: 'the two devices to connect');
}

void main() {
  late MemoryNetwork network;
  late Device mac;
  late Device pc;
  late Device phone;
  late Duration now;

  setUp(() async {
    network = MemoryNetwork();
    now = Duration.zero;
    // Ids are compared as text: "1" connects to "2".
    mac = Device(network, id: '1', name: "Sam's MacBook", clock: () => now);
    pc = Device(network, id: '2', name: 'Office PC', clock: () => now);
    phone = Device(network, id: '3', name: 'Pixel', clock: () => now);
    addTearDown(() async {
      await mac.service.shutdown();
      await pc.service.shutdown();
      await phone.service.shutdown();
    });
    await mac.service.load();
    await pc.service.load();
    await phone.service.load();
  });

  Future<void> pair(Device asker, Device answerer) =>
      pairDevices(network, asker.service, answerer.service);

  group('before sync is switched on', () {
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
      },
    );

    test('a device with sync off is not seen and sees nothing', () async {
      await mac.service.setEnabled(true);
      network.announce();
      await settle();

      expect(pc.discovery.isAnnouncing, isFalse);
      expect(pc.service.nearby, isEmpty);
      expect(mac.service.nearby, isEmpty);
    });
  });

  group('finding devices', () {
    test('devices with sync on see each other by name', () async {
      await mac.service.setEnabled(true);
      await pc.service.setEnabled(true);
      network.announce();
      await eventually(() => mac.service.nearby.isNotEmpty);

      expect(mac.nearbyNames, ['Office PC']);
      expect(pc.nearbyNames, ["Sam's MacBook"]);
      expect(mac.service.nearby.single.inMyGroup, isFalse);
      // Seeing is not syncing.
      expect(mac.service.peers, isEmpty);
      expect(network.links, isEmpty);
    });

    test('a device that stops announcing drops off the list', () async {
      await mac.service.setEnabled(true);
      await pc.service.setEnabled(true);
      network.announce();
      await eventually(() => mac.service.nearby.isNotEmpty);

      now += const Duration(seconds: 20);
      mac.service.tick();

      expect(mac.service.nearby, isEmpty);
    });
  });

  group('pairing', () {
    test('a request shows on the other device with a matching code', () async {
      await mac.service.setEnabled(true);
      await pc.service.setEnabled(true);
      network.announce();
      await eventually(() => mac.service.nearby.isNotEmpty);
      PairRequest? announced;
      pc.service.onPairRequest = (request) => announced = request;

      unawaited(mac.service.requestPairing(pc.service.deviceId));
      await eventually(() => pc.service.requests.isNotEmpty);

      final request = pc.service.requests.single;
      expect(request.name, "Sam's MacBook");
      expect(request.code, matches(r'^\d{6}$'));
      expect(announced, same(request));
      await eventually(() => mac.service.outgoing?.code != null);
      expect(mac.service.outgoing!.state, OutgoingState.waiting);
      expect(mac.service.outgoing!.code, request.code);
      // Nothing syncs until the answer.
      expect(mac.service.peers, isEmpty);
    });

    test('accepting connects the two devices', () async {
      await pair(mac, pc);

      expect(mac.peerNames, ['Office PC']);
      expect(pc.peerNames, ["Sam's MacBook"]);
      expect(mac.service.hasKey, isTrue);
      expect(mac.store.saved!.key, pc.store.saved!.key);
      expect(mac.service.outgoing!.state, OutgoingState.accepted);
      expect(pc.service.requests, isEmpty);
    });

    test('declining connects nothing, and says so', () async {
      await mac.service.setEnabled(true);
      await pc.service.setEnabled(true);
      network.announce();
      await eventually(() => mac.service.nearby.isNotEmpty);
      unawaited(mac.service.requestPairing(pc.service.deviceId));
      await eventually(() => pc.service.requests.isNotEmpty);

      await pc.service.decline(pc.service.requests.single);
      await eventually(
        () => mac.service.outgoing?.state == OutgoingState.declined,
      );

      expect(mac.service.hasKey, isFalse);
      expect(pc.service.hasKey, isFalse);
      network.announce();
      await settle();
      expect(mac.service.peers, isEmpty);
    });

    test('a cancelled request disappears from the other device', () async {
      await mac.service.setEnabled(true);
      await pc.service.setEnabled(true);
      network.announce();
      await eventually(() => mac.service.nearby.isNotEmpty);
      unawaited(mac.service.requestPairing(pc.service.deviceId));
      await eventually(() => pc.service.requests.isNotEmpty);

      mac.service.cancelOutgoing();

      await eventually(() => pc.service.requests.isEmpty);
      expect(mac.service.outgoing, isNull);
    });

    test('a device that cannot be reached is reported', () async {
      await mac.service.setEnabled(true);
      await pc.service.setEnabled(true);
      network.announce();
      await eventually(() => mac.service.nearby.isNotEmpty);
      network.refuseConnections = true;

      await mac.service.requestPairing(pc.service.deviceId);

      expect(mac.service.outgoing!.state, OutgoingState.failed);
    });

    test('asking a device that is not nearby does nothing', () async {
      await mac.service.setEnabled(true);
      await mac.service.requestPairing('nobody');
      expect(mac.service.outgoing, isNull);
    });

    test('only one of the two makes the syncing connection', () async {
      await pair(mac, pc);
      final before = network.links.where((link) => !link.isClosed).length;
      network.announce();
      network.announce();
      await settle();

      expect(network.links.where((link) => !link.isClosed).length, before);
      expect(before, 1);
    });
  });

  group('groups', () {
    test(
      'a third device paired with one member syncs with all of them',
      () async {
        await pair(mac, phone);
        // The laptop only ever talks to the Mac about pairing.
        await pair(pc, mac);
        await eventually(() {
          network.announce();
          return pc.service.peers.length == 2 &&
              phone.service.peers.length == 2;
        }, reason: 'everyone to connect to everyone');

        expect(pc.peerNames, ['Pixel', "Sam's MacBook"]);
        expect(phone.peerNames, ['Office PC', "Sam's MacBook"]);

        pc.service.sendClip('from the laptop');
        await eventually(
          () => phone.received.isNotEmpty && mac.received.isNotEmpty,
        );
        expect(phone.received, ['from the laptop']);
      },
    );

    test('it works the same when the member does the asking', () async {
      await pair(mac, phone);
      await pair(mac, pc);
      await eventually(() {
        network.announce();
        return pc.service.peers.length == 2 && phone.service.peers.length == 2;
      });

      expect(mac.store.saved!.key, pc.store.saved!.key);
      expect(mac.store.saved!.key, phone.store.saved!.key);
    });

    test('devices already in the group are not offered for pairing', () async {
      await pair(mac, pc);
      await mac.service.shutdown();
      mac.service = mac.build(clock: () => now);
      await mac.service.load();
      network.refuseConnections = true;
      network.announce();
      await eventually(() => mac.service.nearby.isNotEmpty);

      expect(mac.service.nearby.single.inMyGroup, isTrue);
    });

    test('leaving stops this device syncing but not the others', () async {
      await pair(mac, phone);
      await pair(pc, mac);
      await eventually(() {
        network.announce();
        return pc.service.peers.length == 2;
      });

      await pc.service.leaveGroup();
      network.announce();
      await eventually(() => mac.service.peers.length == 1);

      expect(pc.service.hasKey, isFalse);
      expect(pc.service.peers, isEmpty);
      expect(pc.store.saved!.key, isNull);
      expect(mac.peerNames, ['Pixel']);
      // It is still on the network, and can be paired again.
      expect(pc.service.running, isTrue);
      await eventually(() {
        network.announce();
        return pc.service.nearby.length == 2;
      });
      expect(pc.service.nearby.every((device) => !device.inMyGroup), isTrue);
    });
  });

  group('copying', () {
    test('text copied on one device arrives on the other', () async {
      await pair(mac, pc);

      mac.service.sendClip('from the mac');
      pc.service.sendClip('from the pc\nsecond line “quoted”');
      await eventually(() => pc.received.isNotEmpty && mac.received.isNotEmpty);

      expect(pc.received, ['from the mac']);
      expect(mac.received, ['from the pc\nsecond line “quoted”']);
    });

    test('several copies arrive in the order they were made', () async {
      await pair(mac, pc);
      for (var i = 0; i < 10; i++) {
        mac.service.sendClip('copy $i');
      }
      await eventually(() => pc.received.length == 10);
      expect(pc.received, [for (var i = 0; i < 10; i++) 'copy $i']);
    });

    test('the copied text is not readable on the network', () async {
      await pair(mac, pc);
      mac.service.sendClip('hunter2-hunter2');
      await eventually(() => pc.received.isNotEmpty);

      final wire = String.fromCharCodes([
        for (final link in network.links)
          for (final chunk in link.traffic) ...chunk,
      ]);
      expect(wire, isNot(contains('hunter2')));
      expect(wire, isNot(contains(mac.store.saved!.key!)));
    });

    test('a device that only sees this one gets nothing', () async {
      await pair(mac, pc);
      await phone.service.setEnabled(true);
      network.announce();
      await eventually(() => phone.service.nearby.length == 2);

      mac.service.sendClip('not for the phone');
      await eventually(() => pc.received.isNotEmpty);
      await settle();

      expect(phone.received, isEmpty);
      expect(phone.service.peers, isEmpty);
    });

    test('empty and over-long text is not sent', () async {
      await pair(mac, pc);
      mac.service
        ..sendClip('')
        ..sendClip('x' * (mac.service.maxTextLength + 1))
        ..sendClip('fine');
      await eventually(() => pc.received.isNotEmpty);
      await settle();
      expect(pc.received, ['fine']);
    });
  });

  group('losing a device', () {
    test(
      'a dropped connection removes the device, and it comes back',
      () async {
        await pair(mac, pc);

        for (final link in network.links) {
          link.sever();
        }
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
      await pair(mac, pc);

      now += const Duration(seconds: 20);
      mac.service.tick();
      expect(mac.service.peers, isNotEmpty, reason: 'not long enough yet');
      // The ping just sent is answered, which counts as hearing from it.
      await settle();

      now += const Duration(seconds: 31);
      mac.service.tick();
      await eventually(() => mac.service.peers.isEmpty);
    });

    test('switching sync off disconnects and leaves the network', () async {
      await pair(mac, pc);

      await pc.service.setEnabled(false);

      expect(pc.service.running, isFalse);
      expect(pc.service.peers, isEmpty);
      expect(pc.discovery.isAnnouncing, isFalse);
      expect(pc.service.hasKey, isTrue, reason: 'it stays in the group');
      await eventually(() => mac.service.peers.isEmpty);

      await pc.service.setEnabled(true);
      network.announce();
      await eventually(() => mac.service.peers.isNotEmpty);
    });
  });

  group('between launches', () {
    test('sync comes back by itself with the devices it had', () async {
      await pair(mac, pc);
      await pc.service.shutdown();
      await eventually(() => mac.service.peers.isEmpty);

      pc.service = pc.build(clock: () => now);
      await pc.service.load();
      network.announce();
      await eventually(() => mac.service.peers.isNotEmpty);

      expect(pc.service.deviceId, '2');
      expect(pc.peerNames, ["Sam's MacBook"]);
    });
  });

  group('when the network says no', () {
    test('not being allowed to listen is reported, not thrown', () async {
      mac.transport.failToListen = true;
      await mac.service.setEnabled(true);

      expect(mac.service.running, isFalse);
      expect(mac.service.error, contains('firewall'));
      expect(mac.discovery.isAnnouncing, isFalse);

      mac.transport.failToListen = false;
      await mac.service.setEnabled(true);
      expect(mac.service.running, isTrue);
      expect(mac.service.error, isNull);
    });
  });
}
