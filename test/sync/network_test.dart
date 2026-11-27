import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pastehive/src/sync/network.dart';
import 'package:pastehive/src/sync/sync_ports.dart';
import 'package:pastehive/src/sync/sync_service.dart';

import 'memory_network.dart';
import 'sync_service_test.dart' show eventually, pairDevices;

void main() {
  group('beacon', () {
    test('survives the trip', () {
      final bytes = encodeBeacon(
        deviceId: 'abc123',
        name: 'Office PC',
        port: 50123,
        tag: 'feed',
      );
      final announcement = decodeBeacon(bytes, '192.168.1.20')!;

      expect(announcement.deviceId, 'abc123');
      expect(announcement.name, 'Office PC');
      expect(announcement.port, 50123);
      expect(announcement.tag, 'feed');
      expect(announcement.address, '192.168.1.20');
    });

    test('carries only the id, name, port and tag', () {
      final decoded = jsonDecode(
        utf8.decode(encodeBeacon(deviceId: 'a', name: 'n', port: 1, tag: 't')),
      ) as Map<String, Object?>;
      expect(
        decoded.keys,
        unorderedEquals(['app', 'v', 'id', 'name', 'port', 'tag']),
      );
    });

    test('ignores datagrams from anything else', () {
      Object? decode(Object? json) =>
          decodeBeacon(utf8.encode(jsonEncode(json)), '10.0.0.1');
      const good = {
        'app': 'syncclip',
        'v': 1,
        'id': 'a',
        'port': 80,
        'tag': 't',
      };

      expect(decode(good), isNotNull);
      expect(decodeBeacon([0xff, 0xfe, 0x00], '10.0.0.1'), isNull);
      expect(
        decodeBeacon(utf8.encode('M-SEARCH * HTTP/1.1'), '10.0.0.1'),
        isNull,
      );
      expect(decode([1, 2, 3]), isNull);
      expect(decode({...good, 'app': 'other'}), isNull);
      expect(decode({...good, 'v': 2}), isNull);
      expect(decode({...good, 'id': ''}), isNull);
      expect(decode({...good, 'id': 5}), isNull);
      expect(decode({...good, 'port': 0}), isNull);
      expect(decode({...good, 'port': 70000}), isNull);
      expect(decode({...good, 'port': '80'}), isNull);
      expect(decode({...good}..remove('tag')), isNull);
    });
  });

  group('settings file', () {
    late Directory directory;
    late File file;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('sync_settings_test');
      file = File(path.join(directory.path, 'nested', 'sync.json'));
    });

    tearDown(() => directory.deleteSync(recursive: true));

    test('reads back what it saved', () async {
      final store = JsonFileSyncSettingsStore(file);
      expect(await store.load(), isNull);

      await store.save(
        const SyncSettings(
          deviceId: 'abc',
          deviceName: "Sam's MacBook",
          enabled: true,
          key: 'ABCDEFGHJKMNPQRSTVWX',
        ),
      );
      final loaded = (await JsonFileSyncSettingsStore(file).load())!;

      expect(loaded.deviceId, 'abc');
      expect(loaded.deviceName, "Sam's MacBook");
      expect(loaded.enabled, isTrue);
      expect(loaded.key, 'ABCDEFGHJKMNPQRSTVWX');
    });

    test('treats a damaged file as a first launch', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{"deviceId": 4');
      expect(await JsonFileSyncSettingsStore(file).load(), isNull);

      file.writeAsStringSync('{"deviceId": 4, "deviceName": "x"}');
      expect(await JsonFileSyncSettingsStore(file).load(), isNull);
    });
  });

  // Real sockets, on this machine only: nothing leaves the loopback
  // interface, so no firewall is involved.
  group('over TCP', () {
    test('two devices connect and exchange text', () async {
      final network = MemoryNetwork();
      SyncService device(String id, String name) => SyncService(
        discovery: network.discovery('127.0.0.1'),
        transport: TcpTransport(bindAddress: InternetAddress.loopbackIPv4),
        store: MemorySyncSettingsStore(
          SyncSettings(deviceId: id, deviceName: name),
        ),
        defaultDeviceName: () => name,
      );
      final mac = device('1', 'Mac');
      final pc = device('2', 'PC');
      addTearDown(() async {
        await mac.shutdown();
        await pc.shutdown();
      });
      final atPc = <String>[];
      final atMac = <String>[];
      pc.remoteClips.listen((clip) => atPc.add(clip.text));
      mac.remoteClips.listen((clip) => atMac.add(clip.text));

      await mac.load();
      await pc.load();
      await pairDevices(network, mac, pc);

      final long = 'long text ' * 20000;
      mac.sendClip(long);
      pc.sendClip('short');
      await eventually(() => atPc.isNotEmpty && atMac.isNotEmpty);

      expect(atPc.single, long);
      expect(atMac.single, 'short');

      await pc.shutdown();
      await eventually(() => mac.peers.isEmpty);
    });
  });
}
