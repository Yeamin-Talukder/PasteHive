import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synchronize_clipboard/src/sync/byte_connection.dart';
import 'package:synchronize_clipboard/src/sync/secure_channel.dart';
import 'package:synchronize_clipboard/src/sync/sync_key.dart';

import 'memory_network.dart';

final key = SyncKey.tryParse('ABCDE-FGHJK-MNPQR-STVWX')!;
final otherKey = SyncKey.tryParse('ABCDE-FGHJK-MNPQR-STVWY')!;

Future<SecureChannel> openMac(ByteConnection connection, {SyncKey? withKey}) {
  return SecureChannel.open(
    connection,
    key: withKey ?? key,
    deviceId: 'mac-id',
    deviceName: "Sam's MacBook",
    initiator: true,
    timeout: const Duration(seconds: 2),
  );
}

Future<SecureChannel> openPc(ByteConnection connection, {SyncKey? withKey}) {
  return SecureChannel.open(
    connection,
    key: withKey ?? key,
    deviceId: 'pc-id',
    deviceName: 'Office PC',
    initiator: false,
    timeout: const Duration(seconds: 2),
  );
}

bool containsBytes(List<List<int>> traffic, String needle) {
  final all = latin1.decode([for (final chunk in traffic) ...chunk]);
  return all.contains(latin1.decode(utf8.encode(needle)));
}

/// A connection whose incoming frames can be altered or repeated, as someone
/// in the middle of the network could do.
class Meddler implements ByteConnection {
  Meddler(this._inner);

  final ByteConnection _inner;

  /// Called with each frame after the first two (the hello and the ready
  /// message); returns the frames to deliver in its place.
  List<Uint8List> Function(Uint8List frame)? meddle;

  @override
  Stream<List<int>> get incoming async* {
    var index = 0;
    await for (final frame in decodeFrames(_inner.incoming)) {
      final replacement = index++ < 2 || meddle == null
          ? [frame]
          : meddle!(frame);
      for (final out in replacement) {
        yield encodeFrame(out);
      }
    }
  }

  @override
  void add(List<int> bytes) => _inner.add(bytes);

  @override
  Future<void> close() => _inner.close();
}

void main() {
  test('two devices with the same key learn who the other is', () async {
    final link = MemoryLink();
    final [mac, pc] = await Future.wait([openMac(link.a), openPc(link.b)]);

    expect(mac.peerId, 'pc-id');
    expect(mac.peerName, 'Office PC');
    expect(pc.peerId, 'mac-id');
    expect(pc.peerName, "Sam's MacBook");
    expect(mac.initiatorId, 'mac-id');
    expect(pc.initiatorId, 'mac-id');
  });

  test('messages arrive whole and in order, both ways', () async {
    final link = MemoryLink();
    final [mac, pc] = await Future.wait([openMac(link.a), openPc(link.b)]);

    for (var i = 0; i < 20; i++) {
      unawaited(mac.send({'n': i, 'text': 'héllo “$i” 🚀' * (i + 1)}));
    }
    unawaited(pc.send({'reply': true}));

    final received = await pc.messages.take(20).toList();
    expect(
      [for (final message in received) message['n']],
      [for (var i = 0; i < 20; i++) i],
    );
    expect(received.last['text'], 'héllo “19” 🚀' * 20);
    expect(await mac.messages.first, {'reply': true});
  });

  test('nothing readable crosses the network', () async {
    final link = MemoryLink();
    final [mac, pc] = await Future.wait([openMac(link.a), openPc(link.b)]);

    unawaited(mac.send({'type': 'clip', 'text': 'my-secret-password-123'}));
    await pc.messages.first;

    expect(containsBytes(link.traffic, 'my-secret-password-123'), isFalse);
    expect(containsBytes(link.traffic, 'clip'), isFalse);
    expect(containsBytes(link.traffic, 'MacBook'), isFalse);
    expect(containsBytes(link.traffic, 'Office PC'), isFalse);
    expect(containsBytes(link.traffic, key.canonical), isFalse);
    // The device ids are public: they are in the discovery beacons too.
    expect(containsBytes(link.traffic, 'mac-id'), isTrue);
  });

  test('the same message is encrypted differently every time', () async {
    Future<List<int>> lastFrameOfASession() async {
      final link = MemoryLink();
      final [mac, pc] = await Future.wait([openMac(link.a), openPc(link.b)]);
      unawaited(mac.send({'text': 'same'}));
      await pc.messages.first;
      return link.traffic.last;
    }

    final first = await lastFrameOfASession();
    final second = await lastFrameOfASession();
    expect(first, isNot(second));
  });

  test('a device with a different key is turned away', () async {
    final link = MemoryLink();
    final mac = openMac(link.a);
    final pc = openPc(link.b, withKey: otherKey);

    final wrongKey = isA<HandshakeException>().having(
      (e) => e.failure,
      'failure',
      HandshakeFailure.wrongKey,
    );
    await Future.wait([
      expectLater(mac, throwsA(wrongKey)),
      expectLater(pc, throwsA(wrongKey)),
    ]);
    expect(link.isClosed, isTrue);
  });

  test('a message altered on the way ends the connection', () async {
    final link = MemoryLink();
    final meddler = Meddler(link.b)
      ..meddle = (frame) {
        frame[0] ^= 0x01;
        return [frame];
      };
    final [mac, pc] = await Future.wait([openMac(link.a), openPc(meddler)]);

    unawaited(mac.send({'text': 'hello'}));

    await expectLater(
      pc.messages,
      emitsInOrder([emitsError(anything), emitsDone]),
    );
    expect(link.isClosed, isTrue);
  });

  test('a message played back a second time ends the connection', () async {
    final link = MemoryLink();
    final meddler = Meddler(link.b)..meddle = (frame) => [frame, frame];
    final [mac, pc] = await Future.wait([openMac(link.a), openPc(meddler)]);

    unawaited(mac.send({'text': 'pay 10'}));

    await expectLater(
      pc.messages,
      emitsInOrder([
        {'text': 'pay 10'},
        emitsError(anything),
        emitsDone,
      ]),
    );
  });

  test('gives up on a device that never answers', () async {
    final link = MemoryLink();
    await expectLater(
      SecureChannel.open(
        link.a,
        key: key,
        deviceId: 'mac-id',
        deviceName: 'Mac',
        initiator: true,
        timeout: const Duration(milliseconds: 100),
      ),
      throwsA(
        isA<HandshakeException>().having(
          (e) => e.failure,
          'failure',
          HandshakeFailure.timeout,
        ),
      ),
    );
    expect(link.isClosed, isTrue);
  });

  test('refuses a connection to itself', () async {
    final link = MemoryLink();
    final a = openMac(link.a);
    final b = SecureChannel.open(
      link.b,
      key: key,
      deviceId: 'mac-id',
      deviceName: 'Mac again',
      initiator: false,
      timeout: const Duration(seconds: 2),
    );
    final self = isA<HandshakeException>().having(
      (e) => e.failure,
      'failure',
      HandshakeFailure.self,
    );
    await Future.wait([
      expectLater(a, throwsA(self)),
      expectLater(b, throwsA(self)),
    ]);
  });

  test('refuses something that is not this app', () async {
    final link = MemoryLink();
    final mac = openMac(link.a);
    link.b.add(encodeFrame(utf8.encode('GET / HTTP/1.1')));

    await expectLater(
      mac,
      throwsA(
        isA<HandshakeException>().having(
          (e) => e.failure,
          'failure',
          HandshakeFailure.protocol,
        ),
      ),
    );
  });

  test('closing one end ends the other', () async {
    final link = MemoryLink();
    final [mac, pc] = await Future.wait([openMac(link.a), openPc(link.b)]);

    await mac.close();

    await expectLater(pc.messages, emitsDone);
    // Sending afterwards is quietly ignored.
    await mac.send({'late': true});
    await pc.send({'late': true});
  });

  group('framing', () {
    test('frames survive being split and joined on the way', () async {
      final frames = [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList(List.generate(1000, (i) => i % 256)),
      ];
      final bytes = [for (final frame in frames) ...encodeFrame(frame)];

      for (final chunkSize in [1, 2, 3, 5, 7, 500, bytes.length]) {
        final chunks = [
          for (var i = 0; i < bytes.length; i += chunkSize)
            bytes.sublist(i, (i + chunkSize).clamp(0, bytes.length)),
        ];
        expect(
          await decodeFrames(Stream.fromIterable(chunks)).toList(),
          frames,
          reason: 'chunks of $chunkSize',
        );
      }
    });

    test('an absurd length is refused instead of waited for', () async {
      final header = Uint8List(4);
      ByteData.sublistView(header).setUint32(0, kMaxFrameLength + 1);
      await expectLater(
        decodeFrames(Stream.value(header)).toList(),
        throwsA(isA<FrameException>()),
      );
    });
  });
}
