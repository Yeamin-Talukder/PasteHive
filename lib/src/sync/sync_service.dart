import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'byte_connection.dart';
import 'secure_channel.dart';
import 'sync_key.dart';
import 'sync_ports.dart';

/// Another device this one is currently connected to.
@immutable
class SyncPeer {
  const SyncPeer({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is SyncPeer && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'SyncPeer($name)';
}

/// Text that was copied on another device.
@immutable
class RemoteClip {
  const RemoteClip({required this.text, required this.fromName});

  final String text;
  final String fromName;
}

/// Keeps this device connected to the others that hold the same sync key,
/// and carries copied text between them.
///
/// Devices find each other through [Discovery] and talk over a
/// [SecureChannel] each. Sync runs only while it is switched on and a key is
/// set; until then no network port is opened at all.
class SyncService extends ChangeNotifier {
  SyncService({
    required this._discovery,
    required this._transport,
    required this._store,
    required this._defaultDeviceName,
    Random? random,
    Duration Function()? clock,
    this.pingInterval = const Duration(seconds: 10),
    this.peerTimeout = const Duration(seconds: 30),
    this.fallbackConnectDelay = const Duration(seconds: 6),
    this.foreignMemory = const Duration(seconds: 15),
    this.maxTextLength = 1000000,
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? _stopwatchClock();

  final Discovery _discovery;
  final PeerTransport _transport;
  final SyncSettingsStore _store;
  final String Function() _defaultDeviceName;
  final Random _random;
  final Duration Function() _clock;

  /// How often each connection is checked and kept alive.
  final Duration pingInterval;

  /// A device that has been silent this long is considered gone.
  final Duration peerTimeout;

  /// Normally the device with the smaller id makes the connection. If that
  /// has not happened after this long, the other one tries as well.
  final Duration fallbackConnectDelay;

  /// How long a nearby device with a different key is remembered.
  final Duration foreignMemory;

  /// Longer text is neither sent nor accepted.
  final int maxTextLength;

  final _remoteClips = StreamController<RemoteClip>.broadcast();
  final Map<String, _Session> _sessions = {};
  final Set<String> _connecting = {};
  final Map<String, Duration> _firstHeard = {};
  final Map<String, Duration> _foreignHeard = {};
  final Map<String, String> _expectedTags = {};

  SyncSettings? _settings;
  SyncKey? _key;
  PeerListener? _listener;
  StreamSubscription<ByteConnection>? _incoming;
  StreamSubscription<PeerAnnouncement>? _announcements;
  Timer? _timer;
  bool _running = false;
  String? _error;
  Future<void> _configuring = Future.value();

  /// Whether the user has switched sync on.
  bool get enabled => _settings?.enabled ?? false;

  bool get hasKey => _key != null;

  /// The sync key as shown to the user, or null when none is set.
  String? get formattedKey => _key?.formatted;

  String get deviceName => _settings?.deviceName ?? '';

  String get deviceId => _settings?.deviceId ?? '';

  /// Whether this device is on the network right now, looking for others.
  bool get running => _running;

  /// The devices currently connected, by name.
  List<SyncPeer> get peers => [
    for (final session in _sessions.values)
      SyncPeer(id: session.channel.peerId, name: session.channel.peerName),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Whether a device running this app with a different key was heard
  /// recently; usually a sign that a key was mistyped.
  bool get differentKeyNearby => _foreignHeard.isNotEmpty;

  /// Why sync could not start, in words for the user, or null.
  String? get error => _error;

  /// Text copied on other devices, as it arrives.
  Stream<RemoteClip> get remoteClips => _remoteClips.stream;

  /// Reads the saved settings and starts syncing if it was left on.
  Future<void> load() async {
    var settings = await _store.load();
    if (settings == null) {
      settings = SyncSettings(
        deviceId: _newDeviceId(),
        deviceName: _defaultDeviceName(),
      );
      await _store.save(settings);
    }
    _settings = settings;
    final saved = settings.key;
    _key = saved == null ? null : SyncKey.tryParse(saved);
    await _reconfigure();
  }

  Future<void> setEnabled(bool value) =>
      _update((settings) => settings.copyWith(enabled: value));

  /// Makes a new key and switches sync on. The other devices need this key
  /// before they can join.
  Future<void> createKey() => _setKey(SyncKey.generate(_random));

  /// Joins the group of the device [input] was read from. Returns false, and
  /// changes nothing, when [input] is not a complete key.
  Future<bool> useKey(String input) async {
    final key = SyncKey.tryParse(input);
    if (key == null) return false;
    await _setKey(key);
    return true;
  }

  /// Forgets the key and switches sync off.
  Future<void> removeKey() {
    _key = null;
    return _update(
      (settings) => settings.copyWith(enabled: false, key: () => null),
    );
  }

  /// Sends [text] to every connected device.
  void sendClip(String text) {
    if (text.isEmpty || text.length > maxTextLength) return;
    for (final session in _sessions.values.toList()) {
      unawaited(session.channel.send({'type': 'clip', 'text': text}));
    }
  }

  /// Checks every connection once. Called on a timer; public for tests.
  void tick() {
    final now = _clock();
    for (final session in _sessions.values.toList()) {
      if (now - session.lastHeard > peerTimeout) {
        unawaited(session.channel.close());
      } else {
        unawaited(session.channel.send({'type': 'ping'}));
      }
    }
    final before = _foreignHeard.length;
    _foreignHeard.removeWhere((_, heard) => now - heard > foreignMemory);
    if (_foreignHeard.length != before) notifyListeners();
  }

  /// Disconnects and closes the network port. The settings are kept.
  Future<void> shutdown() {
    return _configuring = _configuring.then((_) => _stop());
  }

  @override
  void dispose() {
    unawaited(_remoteClips.close());
    super.dispose();
  }

  Future<void> _setKey(SyncKey key) {
    _key = key;
    return _update(
      (settings) => settings.copyWith(enabled: true, key: () => key.canonical),
    );
  }

  Future<void> _update(SyncSettings Function(SyncSettings) change) async {
    final current = _settings;
    if (current == null) return;
    _settings = change(current);
    await _store.save(_settings!);
    await _reconfigure();
  }

  // Starting and stopping are queued so two quick changes cannot interleave.
  Future<void> _reconfigure() {
    return _configuring = _configuring.then((_) async {
      await _stop();
      if (enabled && _key != null) await _start();
      notifyListeners();
    });
  }

  Future<void> _start() async {
    final key = _key!;
    _error = null;
    try {
      final listener = await _transport.listen();
      _listener = listener;
      _incoming = listener.connections.listen(_accept);
      _announcements = _discovery.announcements.listen(_onAnnouncement);
      await _discovery.start(
        deviceId: deviceId,
        port: listener.port,
        tag: await key.discoveryTag(deviceId),
      );
    } on Object catch (error) {
      debugPrint('Sync could not start: $error');
      await _stop();
      _error =
          'Could not use the network. Check that this app is allowed '
          'through the firewall.';
      return;
    }
    _timer = Timer.periodic(pingInterval, (_) => tick());
    _running = true;
  }

  Future<void> _stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    await _announcements?.cancel();
    _announcements = null;
    await _incoming?.cancel();
    _incoming = null;
    for (final session in _sessions.values.toList()) {
      await session.channel.close();
    }
    _sessions.clear();
    _connecting.clear();
    _firstHeard.clear();
    _foreignHeard.clear();
    _expectedTags.clear();
    try {
      await _discovery.stop();
      await _listener?.close();
    } on Object catch (error) {
      debugPrint('Sync did not stop cleanly: $error');
    }
    _listener = null;
  }

  Future<void> _onAnnouncement(PeerAnnouncement announcement) async {
    final key = _key;
    final id = announcement.deviceId;
    if (!_running || key == null || id == deviceId) return;

    final expected = _expectedTags[id] ??= await key.discoveryTag(id);
    // Sync may have been stopped or re-keyed while the tag was computed.
    if (!_running || key != _key) return;

    final now = _clock();
    if (announcement.tag != expected) {
      final isNew = !_foreignHeard.containsKey(id);
      _foreignHeard[id] = now;
      if (isNew) notifyListeners();
      return;
    }
    if (_sessions.containsKey(id) || _connecting.contains(id)) return;

    // One side connects, so two devices do not end up with two connections.
    final firstHeard = _firstHeard.putIfAbsent(id, () => now);
    final shouldInitiate = deviceId.compareTo(id) < 0;
    if (!shouldInitiate && now - firstHeard < fallbackConnectDelay) return;

    _connecting.add(id);
    try {
      final connection = await _transport.connect(
        announcement.address,
        announcement.port,
      );
      await _open(connection, key, initiator: true);
    } on Object catch (error) {
      debugPrint('Could not connect to $announcement: $error');
    } finally {
      _connecting.remove(id);
    }
  }

  Future<void> _accept(ByteConnection connection) async {
    final key = _key;
    if (!_running || key == null) {
      await connection.close();
      return;
    }
    try {
      await _open(connection, key, initiator: false);
    } on Object catch (error) {
      debugPrint('Refused an incoming connection: $error');
    }
  }

  Future<void> _open(
    ByteConnection connection,
    SyncKey key, {
    required bool initiator,
  }) async {
    final channel = await SecureChannel.open(
      connection,
      key: key,
      deviceId: deviceId,
      deviceName: deviceName,
      initiator: initiator,
      random: _random,
    );
    if (!_running || key != _key) {
      await channel.close();
      return;
    }
    _adopt(channel);
  }

  void _adopt(SecureChannel channel) {
    final id = channel.peerId;
    final existing = _sessions[id];
    if (existing != null) {
      if (existing.channel.initiatorId != channel.initiatorId) {
        // Both sides connected at once. Both keep the connection made by
        // the device with the smaller id, so they agree on which survives.
        final keeper = deviceId.compareTo(id) < 0 ? deviceId : id;
        if (channel.initiatorId != keeper) {
          unawaited(channel.close());
          return;
        }
      }
      _sessions.remove(id);
      unawaited(existing.channel.close());
    }

    final session = _Session(channel, _clock());
    _sessions[id] = session;
    _firstHeard.remove(id);
    channel.messages.listen(
      (message) => _onMessage(session, message),
      onError: (Object error) {
        debugPrint('Connection to ${channel.peerName} failed: $error');
      },
      onDone: () {
        if (identical(_sessions[id], session)) {
          _sessions.remove(id);
          notifyListeners();
        }
      },
    );
    notifyListeners();
  }

  void _onMessage(_Session session, Map<String, Object?> message) {
    session.lastHeard = _clock();
    switch (message['type']) {
      case 'clip':
        final text = message['text'];
        if (text is String &&
            text.isNotEmpty &&
            text.length <= maxTextLength &&
            !_remoteClips.isClosed) {
          _remoteClips.add(
            RemoteClip(text: text, fromName: session.channel.peerName),
          );
        }
      case 'ping':
        unawaited(session.channel.send({'type': 'pong'}));
    }
  }

  String _newDeviceId() => [
    for (var i = 0; i < 16; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  static Duration Function() _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}

class _Session {
  _Session(this.channel, this.lastHeard);

  final SecureChannel channel;
  Duration lastHeard;
}
