import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'byte_connection.dart';
import 'secure_channel.dart';
import 'sync_key.dart';
import 'sync_ports.dart';

/// Another device this one is currently connected to and syncing with.
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

/// A device running this app that was heard on the network just now.
@immutable
class NearbyDevice {
  const NearbyDevice({
    required this.id,
    required this.name,
    required this.inMyGroup,
  });

  final String id;
  final String name;

  /// Whether it already syncs with this device (it holds the same key).
  final bool inMyGroup;

  @override
  String toString() => 'NearbyDevice($name)';
}

/// Another device asking to sync with this one, waiting for an answer.
class PairRequest {
  PairRequest._(this.id, this.name, this.code, this._theirKey, this._channel);

  /// The asking device's id and name.
  final String id;
  final String name;

  /// Six digits that the asking device shows as well. If they match, the
  /// request really comes from that device and nobody is in between.
  final String code;

  final SyncKey? _theirKey;
  final SecureChannel _channel;
}

/// Where this device's own request to another one stands.
enum OutgoingState { waiting, accepted, declined, failed }

@immutable
class OutgoingRequest {
  const OutgoingRequest({
    required this.id,
    required this.name,
    required this.state,
    this.code,
  });

  final String id;
  final String name;
  final OutgoingState state;

  /// The verification code, once connected to the other device.
  final String? code;
}

/// Text that was copied on another device.
@immutable
class RemoteClip {
  const RemoteClip({required this.text, required this.fromName});

  final String text;
  final String fromName;
}

/// An entry of another device's history, sent so this one has it too.
@immutable
class RemoteHistoryEntry {
  const RemoteHistoryEntry({
    required this.text,
    required this.copiedAt,
    required this.fromName,
  });

  final String text;
  final DateTime copiedAt;
  final String fromName;
}

/// One entry of this device's history, as sent to another device.
typedef HistoryItem = ({String text, DateTime copiedAt});

/// Finds the other devices on the network, pairs with the ones the user
/// chooses, and carries copied text between all the devices in the group.
///
/// **Pairing.** A device asks another to sync ([requestPairing]); the other
/// one's user accepts or declines ([accept], [decline]). Both screens show
/// the same six-digit code for that conversation.
///
/// **Groups.** Devices that sync share one key, which the user never sees.
/// Accepting a request hands the asking device the key of the group the
/// accepting device is in (or a new key if neither had one). Every device
/// holding the key connects to every other one directly, so pairing a third
/// device with any member makes it sync with all of them.
///
/// While sync is off no network port is open.
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
    this.nearbyMemory = const Duration(seconds: 12),
    this.pairingTimeout = const Duration(seconds: 90),
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

  /// How long a device stays in the nearby list after it was last heard.
  final Duration nearbyMemory;

  /// How long a request waits for the other side's answer.
  final Duration pairingTimeout;

  /// Longer text is neither sent nor accepted.
  final int maxTextLength;

  final _remoteClips = StreamController<RemoteClip>.broadcast();
  final _remoteDeletes = StreamController<String>.broadcast();
  final _remoteClears = StreamController<void>.broadcast();
  final _remoteHistory = StreamController<RemoteHistoryEntry>.broadcast();

  /// How many history entries go into one message.
  static const _historyBatch = 40;
  final Map<String, _Session> _sessions = {};
  final Set<String> _connecting = {};
  final Map<String, Duration> _firstHeard = {};
  final Map<String, _Heard> _nearby = {};
  final Map<String, String> _expectedTags = {};
  final List<PairRequest> _requests = [];

  SyncSettings? _settings;
  SyncKey? _key;
  PeerListener? _listener;
  StreamSubscription<ByteConnection>? _incoming;
  StreamSubscription<PeerAnnouncement>? _announcements;
  Timer? _timer;
  bool _running = false;
  String? _error;
  OutgoingRequest? _outgoing;
  SecureChannel? _outgoingChannel;
  Future<void> _configuring = Future.value();

  /// Called when another device asks to sync, so the app can bring the
  /// question in front of the user.
  void Function(PairRequest request)? onPairRequest;

  /// Whether the user has switched sync on.
  bool get enabled => _settings?.enabled ?? false;

  /// Whether this device is in a group with at least one other device, now
  /// or in the past.
  bool get hasKey => _key != null;

  String get deviceName => _settings?.deviceName ?? '';

  String get deviceId => _settings?.deviceId ?? '';

  /// Whether this device is on the network right now.
  bool get running => _running;

  /// The devices currently connected, by name.
  List<SyncPeer> get peers => [
    for (final session in _sessions.values)
      SyncPeer(id: session.channel.peerId, name: session.channel.peerName),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Devices heard on the network that are not connected, by name: the ones
  /// that can be asked to sync.
  List<NearbyDevice> get nearby => [
    for (final entry in _nearby.entries)
      if (!_sessions.containsKey(entry.key))
        NearbyDevice(
          id: entry.key,
          name: entry.value.announcement.name,
          inMyGroup: entry.value.inMyGroup,
        ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Requests from other devices that are waiting for an answer.
  List<PairRequest> get requests => List.unmodifiable(_requests);

  /// This device's own request to another one, if there is one to show.
  OutgoingRequest? get outgoing => _outgoing;

  /// Why sync could not start, in words for the user, or null.
  String? get error => _error;

  /// Text copied on other devices, as it arrives.
  Stream<RemoteClip> get remoteClips => _remoteClips.stream;

  /// Text that was deleted from the history on another device.
  Stream<String> get remoteDeletes => _remoteDeletes.stream;

  /// Another device cleared its history.
  Stream<void> get remoteClears => _remoteClears.stream;

  /// Older entries another device is sharing.
  Stream<RemoteHistoryEntry> get remoteHistory => _remoteHistory.stream;

  /// Whether a device that joins is sent the history already here.
  bool get shareHistory => _settings?.shareHistory ?? false;

  /// Called when a device this one has never synced with connects.
  void Function(SyncPeer peer)? onNewDevice;

  Future<void> setShareHistory(bool value) async {
    final current = _settings;
    if (current == null || current.shareHistory == value) return;
    _settings = current.copyWith(shareHistory: value);
    await _store.save(_settings!);
    notifyListeners();
  }

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

  /// Switches sync on or off. On, this device can be seen by, and can see,
  /// the other devices on the network.
  Future<void> setEnabled(bool value) =>
      _update((settings) => settings.copyWith(enabled: value));

  /// Asks the nearby device [deviceId] to sync with this one. The answer
  /// shows in [outgoing].
  Future<void> requestPairing(String deviceId) async {
    final heard = _nearby[deviceId];
    if (!_running || heard == null || _outgoingChannel != null) return;
    final name = heard.announcement.name;
    _setOutgoing(
      OutgoingRequest(id: deviceId, name: name, state: OutgoingState.waiting),
    );
    try {
      final connection = await _transport.connect(
        heard.announcement.address,
        heard.announcement.port,
      );
      final channel = await SecureChannel.open(
        connection,
        keyFor: _keyFor,
        purpose: SecureChannel.pairPurpose,
        deviceId: this.deviceId,
        deviceName: deviceName,
        initiator: true,
        random: _random,
      );
      _outgoingChannel = channel;
      _setOutgoing(
        OutgoingRequest(
          id: deviceId,
          name: name,
          state: OutgoingState.waiting,
          code: channel.verificationCode,
        ),
      );
      unawaited(channel.send({'type': 'pair-request', 'key': _key?.canonical}));
      final answer = await channel.messages.first.timeout(pairingTimeout);
      final offered = answer['key'];
      final key = offered is String ? SyncKey.tryParse(offered) : null;
      if (answer['type'] == 'pair-accept' && key != null) {
        _setOutgoing(
          OutgoingRequest(
            id: deviceId,
            name: name,
            state: OutgoingState.accepted,
          ),
        );
        await channel.close();
        _outgoingChannel = null;
        await _setKey(key);
      } else {
        _finishOutgoing(deviceId, name, OutgoingState.declined);
      }
    } on Object catch (error) {
      debugPrint('Pairing with $name did not complete: $error');
      _finishOutgoing(deviceId, name, OutgoingState.failed);
    }
  }

  /// Takes back this device's own request, or clears its result.
  void cancelOutgoing() {
    final channel = _outgoingChannel;
    _outgoingChannel = null;
    if (channel != null) unawaited(channel.close());
    _setOutgoing(null);
  }

  /// Lets the asking device in. It joins this device's group; if this
  /// device was in none, the two form one (around the asking device's group
  /// if it had one).
  Future<void> accept(PairRequest request) async {
    if (!_requests.remove(request)) return;
    final key = _key ?? request._theirKey ?? SyncKey.generate(_random);
    await request._channel.send({'type': 'pair-accept', 'key': key.canonical});
    // Give the answer a moment to leave before the connection goes.
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 300),
        request._channel.close,
      ),
    );
    notifyListeners();
    if (key != _key) await _setKey(key);
  }

  /// Turns the asking device away.
  Future<void> decline(PairRequest request) async {
    if (!_requests.remove(request)) return;
    await request._channel.send({'type': 'pair-decline'});
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 300),
        request._channel.close,
      ),
    );
    notifyListeners();
  }

  /// Leaves the group: this device stops syncing with all the others. They
  /// keep syncing with each other.
  Future<void> leaveGroup() {
    _key = null;
    return _update(
      (settings) => settings.copyWith(key: () => null, knownDevices: const []),
    );
  }

  /// Sends [text] to every connected device.
  void sendClip(String text) {
    if (text.isEmpty || text.length > maxTextLength) return;
    for (final session in _sessions.values.toList()) {
      unawaited(session.channel.send({'type': 'clip', 'text': text}));
    }
  }

  /// Tells every connected device that [text] was deleted here.
  void sendDelete(String text) => _broadcast({'type': 'delete', 'text': text});

  /// Tells every connected device that the history was cleared here.
  void sendClear() => _broadcast({'type': 'clear'});

  /// Sends [items] of this device's history to the device [to], or to every
  /// connected device when [to] is null. They are added there without
  /// touching that device's clipboard.
  void sendHistory(Iterable<HistoryItem> items, {String? to}) {
    final sendable = [
      for (final item in items)
        if (item.text.isNotEmpty && item.text.length <= maxTextLength)
          {
            'text': item.text,
            'at': item.copiedAt.toUtc().millisecondsSinceEpoch,
          },
    ];
    for (var i = 0; i < sendable.length; i += _historyBatch) {
      _broadcast({
        'type': 'history',
        'entries': sendable.sublist(
          i,
          (i + _historyBatch).clamp(0, sendable.length),
        ),
      }, to: to);
    }
  }

  void _broadcast(Map<String, Object?> message, {String? to}) {
    for (final session in _sessions.values.toList()) {
      if (to == null || session.channel.peerId == to) {
        unawaited(session.channel.send(message));
      }
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
    final before = _nearby.length;
    _nearby.removeWhere((_, heard) => now - heard.at > nearbyMemory);
    if (_nearby.length != before) notifyListeners();
  }

  /// Disconnects and closes the network port. The settings are kept.
  Future<void> shutdown() {
    return _configuring = _configuring.then((_) => _stop());
  }

  @override
  void dispose() {
    unawaited(_remoteClips.close());
    unawaited(_remoteDeletes.close());
    unawaited(_remoteClears.close());
    unawaited(_remoteHistory.close());
    super.dispose();
  }

  SyncKey? _keyFor(String purpose) =>
      purpose == SecureChannel.pairPurpose ? SyncKey.pairing : _key;

  void _setOutgoing(OutgoingRequest? request) {
    _outgoing = request;
    notifyListeners();
  }

  void _finishOutgoing(String id, String name, OutgoingState state) {
    final channel = _outgoingChannel;
    _outgoingChannel = null;
    if (channel != null) unawaited(channel.close());
    // Cancelled meanwhile: nothing to report.
    if (_outgoing?.id != id) return;
    _setOutgoing(OutgoingRequest(id: id, name: name, state: state));
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
      if (enabled) await _start();
      notifyListeners();
    });
  }

  Future<void> _start() async {
    final key = _key;
    _error = null;
    try {
      final listener = await _transport.listen();
      _listener = listener;
      _incoming = listener.connections.listen(_accept);
      _announcements = _discovery.announcements.listen(_onAnnouncement);
      await _discovery.start(
        deviceId: deviceId,
        name: deviceName,
        port: listener.port,
        // A device in no group yet has nothing to prove.
        tag: key == null ? '' : await key.discoveryTag(deviceId),
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
    _nearby.clear();
    _expectedTags.clear();
    for (final request in _requests) {
      unawaited(request._channel.close());
    }
    _requests.clear();
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
    if (!_running || id == deviceId) return;

    var inMyGroup = false;
    if (key != null && announcement.tag.isNotEmpty) {
      final expected = _expectedTags[id] ??= await key.discoveryTag(id);
      // Sync may have been stopped or re-keyed while the tag was computed.
      if (!_running || key != _key) return;
      inMyGroup = announcement.tag == expected;
    }

    final now = _clock();
    final known = _nearby[id];
    _nearby[id] = _Heard(announcement, now, inMyGroup: inMyGroup);
    if (known == null ||
        known.inMyGroup != inMyGroup ||
        known.announcement.name != announcement.name) {
      notifyListeners();
    }

    if (!inMyGroup || key == null) return;
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
      final channel = await _open(connection, initiator: true);
      if (!_running || key != _key) {
        await channel.close();
      } else {
        _adopt(channel);
      }
    } on Object catch (error) {
      debugPrint('Could not connect to $announcement: $error');
    } finally {
      _connecting.remove(id);
    }
  }

  Future<void> _accept(ByteConnection connection) async {
    if (!_running) {
      await connection.close();
      return;
    }
    final key = _key;
    try {
      final channel = await _open(connection, initiator: false);
      if (!_running || key != _key) {
        await channel.close();
      } else if (channel.purpose == SecureChannel.pairPurpose) {
        unawaited(_receiveRequest(channel));
      } else {
        _adopt(channel);
      }
    } on Object catch (error) {
      debugPrint('Refused an incoming connection: $error');
    }
  }

  Future<SecureChannel> _open(
    ByteConnection connection, {
    required bool initiator,
  }) {
    return SecureChannel.open(
      connection,
      keyFor: _keyFor,
      deviceId: deviceId,
      deviceName: deviceName,
      initiator: initiator,
      random: _random,
    );
  }

  // Another device has connected to ask whether it may sync with this one.
  Future<void> _receiveRequest(SecureChannel channel) async {
    PairRequest? request;
    try {
      await for (final message in channel.messages.timeout(pairingTimeout)) {
        if (message['type'] != 'pair-request' || request != null) continue;
        final offered = message['key'];
        request = PairRequest._(
          channel.peerId,
          channel.peerName,
          channel.verificationCode,
          offered is String ? SyncKey.tryParse(offered) : null,
          channel,
        );
        // A second request from the same device replaces the first.
        _requests
          ..removeWhere((existing) => existing.id == request!.id)
          ..add(request);
        notifyListeners();
        onPairRequest?.call(request);
      }
    } on Object catch (error) {
      debugPrint('A pairing request ended: $error');
    }
    // The other side hung up, or nobody answered in time.
    await channel.close();
    if (request != null && _requests.remove(request)) notifyListeners();
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

    final settings = _settings;
    if (settings != null && !settings.knownDevices.contains(id)) {
      _settings = settings.copyWith(
        knownDevices: [...settings.knownDevices, id],
      );
      unawaited(_store.save(_settings!));
      onNewDevice?.call(SyncPeer(id: id, name: channel.peerName));
    }
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
      case 'delete':
        final text = message['text'];
        if (text is String && !_remoteDeletes.isClosed) {
          _remoteDeletes.add(text);
        }
      case 'clear':
        if (!_remoteClears.isClosed) _remoteClears.add(null);
      case 'history':
        final entries = message['entries'];
        if (entries is! List || _remoteHistory.isClosed) break;
        for (final entry in entries) {
          if (entry is! Map) continue;
          final text = entry['text'];
          final at = entry['at'];
          if (text is String &&
              text.isNotEmpty &&
              text.length <= maxTextLength &&
              at is int) {
            _remoteHistory.add(
              RemoteHistoryEntry(
                text: text,
                copiedAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
                fromName: session.channel.peerName,
              ),
            );
          }
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

class _Heard {
  _Heard(this.announcement, this.at, {required this.inMyGroup});

  final PeerAnnouncement announcement;
  final Duration at;
  final bool inMyGroup;
}
