import 'dart:async';

import 'package:pastehive/src/sync/byte_connection.dart';
import 'package:pastehive/src/sync/sync_ports.dart';

/// A pretend local network: devices on it can announce themselves and
/// connect to each other without any real sockets.
class MemoryNetwork {
  final Map<String, _MemoryListener> _listeners = {};
  final List<MemoryDiscovery> _discoveries = [];
  int _nextPort = 5000;

  /// Every connection made, so a test can look at what went over the wire.
  final List<MemoryLink> links = [];

  /// When true, new connections are refused, like a firewall would.
  bool refuseConnections = false;

  MemoryTransport transport(String address) => MemoryTransport._(this, address);

  MemoryDiscovery discovery(String address) {
    final discovery = MemoryDiscovery._(address);
    _discoveries.add(discovery);
    return discovery;
  }

  /// One round of beacons: every device that is announcing is heard by all
  /// the others (and, like on a real network, by itself).
  void announce() {
    for (final from in _discoveries.where((d) => d._self != null)) {
      for (final to in _discoveries.where((d) => d._self != null)) {
        to._controller.add(
          PeerAnnouncement(
            deviceId: from._self!.deviceId,
            name: from._self!.name,
            address: from.address,
            port: from._self!.port,
            tag: from._self!.tag,
          ),
        );
      }
    }
  }
}

class MemoryDiscovery implements Discovery {
  MemoryDiscovery._(this.address);

  final String address;
  final _controller = StreamController<PeerAnnouncement>.broadcast();
  PeerAnnouncement? _self;

  bool get isAnnouncing => _self != null;

  /// What this device is announcing, or null while it is not.
  PeerAnnouncement? get self => _self;

  /// Delivers [announcement] to this device only, as if it had been heard.
  void hear(PeerAnnouncement announcement) => _controller.add(announcement);

  @override
  Stream<PeerAnnouncement> get announcements => _controller.stream;

  @override
  Future<void> start({
    required String deviceId,
    required String name,
    required int port,
    required String tag,
  }) async {
    _self = PeerAnnouncement(
      deviceId: deviceId,
      name: name,
      address: address,
      port: port,
      tag: tag,
    );
  }

  @override
  Future<void> stop() async => _self = null;
}

class MemoryTransport implements PeerTransport {
  MemoryTransport._(this._network, this.address);

  final MemoryNetwork _network;
  final String address;

  /// When true, [listen] fails, as it does when the firewall says no.
  bool failToListen = false;

  int connectCount = 0;

  @override
  Future<PeerListener> listen() async {
    if (failToListen) throw StateError('listening is blocked');
    final listener = _MemoryListener(_network, address, _network._nextPort++);
    _network._listeners[listener.key] = listener;
    return listener;
  }

  @override
  Future<ByteConnection> connect(String address, int port) async {
    connectCount++;
    final listener = _network._listeners['$address:$port'];
    if (listener == null || _network.refuseConnections) {
      throw StateError('connection refused');
    }
    final link = MemoryLink();
    _network.links.add(link);
    listener._controller.add(link.b);
    return link.a;
  }
}

class _MemoryListener implements PeerListener {
  _MemoryListener(this._network, this.address, this.port);

  final MemoryNetwork _network;
  final String address;
  final _controller = StreamController<ByteConnection>();

  @override
  final int port;

  String get key => '$address:$port';

  @override
  Stream<ByteConnection> get connections => _controller.stream;

  @override
  Future<void> close() async {
    _network._listeners.remove(key);
    unawaited(_controller.close());
  }
}

/// Two connected ends. Whatever one adds, the other receives.
class MemoryLink {
  MemoryLink() {
    a = _MemoryEnd(this, _toA, _toB);
    b = _MemoryEnd(this, _toB, _toA);
  }

  final _toA = StreamController<List<int>>();
  final _toB = StreamController<List<int>>();

  late final ByteConnection a;
  late final ByteConnection b;

  /// Every chunk of bytes that crossed the link, in either direction.
  final List<List<int>> traffic = [];

  bool isClosed = false;

  /// Cuts the link, as pulling the network cable would.
  void sever() {
    if (isClosed) return;
    isClosed = true;
    unawaited(_toA.close());
    unawaited(_toB.close());
  }
}

class _MemoryEnd implements ByteConnection {
  _MemoryEnd(this._link, this._inbox, this._outbox);

  final MemoryLink _link;
  final StreamController<List<int>> _inbox;
  final StreamController<List<int>> _outbox;

  @override
  Stream<List<int>> get incoming => _inbox.stream;

  @override
  void add(List<int> bytes) {
    if (_link.isClosed) return;
    _link.traffic.add(List.of(bytes));
    _outbox.add(bytes);
  }

  @override
  Future<void> close() async => _link.sever();
}
