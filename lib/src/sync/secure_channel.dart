import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'byte_connection.dart';
import 'sync_key.dart';

/// Why a connection to another device could not be set up.
enum HandshakeFailure {
  /// The other side does not hold the same sync key.
  wrongKey,

  /// The other side sent something this version does not understand.
  protocol,

  /// The other side stopped answering.
  timeout,

  /// The connection was to this device itself.
  self,
}

class HandshakeException implements Exception {
  const HandshakeException(this.failure, [this.detail]);

  final HandshakeFailure failure;
  final String? detail;

  @override
  String toString() =>
      'HandshakeException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// An encrypted, authenticated connection to one other device.
///
/// Setting one up ([open]) goes like this:
///
/// 1. Each side sends a hello in the clear: its device id, a random nonce and
///    a fresh X25519 public key made for this connection only.
/// 2. Both compute the X25519 shared secret and derive two encryption keys
///    (one per direction) with HKDF-SHA256 from that secret **and the sync
///    key**, salted with a hash of both hellos.
/// 3. Everything after that is ChaCha20-Poly1305 with a counter as the nonce.
///    The first encrypted message carries the device's name; if it cannot be
///    decrypted, the other side has a different sync key.
///
/// Because the sync key goes into the key derivation, someone on the network
/// without it can neither read nor join, even if they sit between the two
/// devices. Because the X25519 keys are thrown away afterwards, traffic that
/// was recorded cannot be decrypted later if the sync key leaks.
///
/// This is a small protocol written for this app from standard parts. It has
/// not been reviewed by a cryptographer.
class SecureChannel {
  SecureChannel._({
    required this._connection,
    required this._frames,
    required _DirectionKey sendKey,
    required _DirectionKey receiveKey,
    required this.peerId,
    required this.peerName,
    required this.initiatorId,
  }) : _send = sendKey,
       _receive = receiveKey {
    unawaited(_pump());
  }

  static const _version = 1;
  static const _info = 'syncclip/1 session keys';

  final ByteConnection _connection;
  final StreamIterator<Uint8List> _frames;
  final _DirectionKey _send;
  final _DirectionKey _receive;
  final _messages = StreamController<Map<String, Object?>>();
  Future<void> _lastSend = Future.value();
  bool _closed = false;

  final String peerId;
  final String peerName;

  /// The device that made the connection (as opposed to accepting it).
  final String initiatorId;

  /// Decrypted messages from the other device. Closes when the connection
  /// ends; a message that fails authentication ends it with an error.
  Stream<Map<String, Object?>> get messages => _messages.stream;

  static Future<SecureChannel> open(
    ByteConnection connection, {
    required SyncKey key,
    required String deviceId,
    required String deviceName,
    required bool initiator,
    Duration timeout = const Duration(seconds: 10),
    Random? random,
  }) async {
    final frames = StreamIterator(decodeFrames(connection.incoming));
    try {
      return await _handshake(
        connection,
        frames,
        key: key,
        deviceId: deviceId,
        deviceName: deviceName,
        initiator: initiator,
        random: random ?? Random.secure(),
      ).timeout(timeout);
    } on TimeoutException {
      await _abandon(connection, frames);
      throw const HandshakeException(HandshakeFailure.timeout);
    } on HandshakeException {
      await _abandon(connection, frames);
      rethrow;
    } on Object catch (error) {
      await _abandon(connection, frames);
      throw HandshakeException(HandshakeFailure.protocol, '$error');
    }
  }

  /// Sends [message]. Messages go out in the order send was called.
  Future<void> send(Map<String, Object?> message) {
    if (_closed) return Future.value();
    final payload = utf8.encode(jsonEncode(message));
    return _lastSend = _lastSend.then((_) async {
      if (_closed) return;
      _connection.add(encodeFrame(await _send.seal(payload)));
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _connection.close();
    await _frames.cancel();
    // Not awaited: with nobody listening, the close would never complete.
    if (!_messages.isClosed) unawaited(_messages.close());
  }

  Future<void> _pump() async {
    try {
      while (await _frames.moveNext()) {
        final clear = await _receive.open(_frames.current);
        final decoded = jsonDecode(utf8.decode(clear));
        if (decoded is Map<String, Object?> && !_messages.isClosed) {
          _messages.add(decoded);
        }
      }
    } on Object catch (error, stackTrace) {
      if (!_closed && !_messages.isClosed) {
        _messages.addError(error, stackTrace);
      }
    } finally {
      await close();
    }
  }

  static Future<SecureChannel> _handshake(
    ByteConnection connection,
    StreamIterator<Uint8List> frames, {
    required SyncKey key,
    required String deviceId,
    required String deviceName,
    required bool initiator,
    required Random random,
  }) async {
    final x25519 = X25519();
    final ephemeral = await x25519.newKeyPair();
    final ephemeralPublic = await ephemeral.extractPublicKey();
    final myHello = utf8.encode(
      jsonEncode({
        'v': _version,
        'id': deviceId,
        'nonce': base64Encode([
          for (var i = 0; i < 32; i++) random.nextInt(256),
        ]),
        'eph': base64Encode(ephemeralPublic.bytes),
      }),
    );
    connection.add(encodeFrame(myHello));

    if (!await frames.moveNext()) {
      throw const HandshakeException(
        HandshakeFailure.protocol,
        'closed before hello',
      );
    }
    final theirHello = Uint8List.fromList(frames.current);
    final hello = jsonDecode(utf8.decode(theirHello));
    if (hello is! Map<String, Object?> || hello['v'] != _version) {
      throw const HandshakeException(
        HandshakeFailure.protocol,
        'unknown version',
      );
    }
    final peerId = hello['id'];
    final peerNonce = hello['nonce'];
    final peerEphemeral = hello['eph'];
    if (peerId is! String ||
        peerId.isEmpty ||
        peerNonce is! String ||
        peerEphemeral is! String) {
      throw const HandshakeException(
        HandshakeFailure.protocol,
        'malformed hello',
      );
    }
    if (peerId == deviceId) {
      throw const HandshakeException(HandshakeFailure.self);
    }
    final peerPublic = base64Decode(peerEphemeral);
    if (peerPublic.length != 32 || base64Decode(peerNonce).length != 32) {
      throw const HandshakeException(
        HandshakeFailure.protocol,
        'malformed hello',
      );
    }

    final shared = await x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(peerPublic, type: KeyPairType.x25519),
    );
    // Both sides hash the hellos in the same order: the initiator's first.
    final transcript = BytesBuilder()
      ..add(encodeFrame(initiator ? myHello : theirHello))
      ..add(encodeFrame(initiator ? theirHello : myHello));
    final salt = await Sha256().hash(transcript.takeBytes());
    final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: 64).deriveKey(
      secretKey: SecretKey([
        ...await shared.extractBytes(),
        ...key.secretBytes,
      ]),
      nonce: salt.bytes,
      info: utf8.encode(_info),
    );
    final keys = await derived.extractBytes();
    final initiatorToResponder = _DirectionKey(keys.sublist(0, 32));
    final responderToInitiator = _DirectionKey(keys.sublist(32, 64));
    final send = initiator ? initiatorToResponder : responderToInitiator;
    final receive = initiator ? responderToInitiator : initiatorToResponder;

    connection.add(
      encodeFrame(
        await send.seal(
          utf8.encode(jsonEncode({'type': 'ready', 'name': deviceName})),
        ),
      ),
    );
    if (!await frames.moveNext()) {
      // A side that cannot decrypt our message hangs up without answering.
      throw const HandshakeException(HandshakeFailure.wrongKey);
    }
    final Object? ready;
    try {
      ready = jsonDecode(utf8.decode(await receive.open(frames.current)));
    } on SecretBoxAuthenticationError {
      throw const HandshakeException(HandshakeFailure.wrongKey);
    }
    if (ready is! Map<String, Object?> || ready['type'] != 'ready') {
      throw const HandshakeException(
        HandshakeFailure.protocol,
        'expected ready',
      );
    }
    final name = ready['name'];

    return SecureChannel._(
      connection: connection,
      frames: frames,
      sendKey: send,
      receiveKey: receive,
      peerId: peerId,
      peerName: name is String && name.trim().isNotEmpty ? name : peerId,
      initiatorId: initiator ? deviceId : peerId,
    );
  }

  static Future<void> _abandon(
    ByteConnection connection,
    StreamIterator<Uint8List> frames,
  ) async {
    await connection.close();
    await frames.cancel();
  }
}

/// One direction's key and message counter.
class _DirectionKey {
  _DirectionKey(List<int> bytes) : _key = SecretKey(bytes);

  static final _cipher = Chacha20.poly1305Aead();
  static const _macLength = 16;

  final SecretKey _key;
  int _counter = 0;

  /// A nonce is never reused under one key: the counter only goes up, and
  /// each direction has a key of its own.
  Uint8List _nextNonce() {
    final nonce = Uint8List(12);
    ByteData.sublistView(nonce).setUint64(4, _counter++);
    return nonce;
  }

  Future<Uint8List> seal(List<int> clear) async {
    final box = await _cipher.encrypt(
      clear,
      secretKey: _key,
      nonce: _nextNonce(),
    );
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  Future<List<int>> open(Uint8List sealed) async {
    if (sealed.length < _macLength) {
      throw const FrameException('frame shorter than its authentication tag');
    }
    final split = sealed.length - _macLength;
    return _cipher.decrypt(
      SecretBox(
        Uint8List.sublistView(sealed, 0, split),
        nonce: _nextNonce(),
        mac: Mac(Uint8List.sublistView(sealed, split)),
      ),
      secretKey: _key,
    );
  }
}
