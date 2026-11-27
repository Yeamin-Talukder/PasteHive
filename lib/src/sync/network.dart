/// Sync over a real local network: TCP between devices, UDP to find them, a
/// JSON file for the settings.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'byte_connection.dart';
import 'sync_ports.dart';

/// The UDP port every copy of the app announces itself on.
const int kDiscoveryPort = 45817;

/// A multicast group in the range reserved for use inside one site.
const String kDiscoveryGroup = '239.255.77.67';

const _beaconApp = 'syncclip';
const _beaconVersion = 1;

/// The datagram a device sends to say where it is listening.
List<int> encodeBeacon({
  required String deviceId,
  required String name,
  required int port,
  required String tag,
}) {
  return utf8.encode(
    jsonEncode({
      'app': _beaconApp,
      'v': _beaconVersion,
      'id': deviceId,
      'name': name,
      'port': port,
      'tag': tag,
    }),
  );
}

/// Reads a datagram received from [address]. Returns null for anything that
/// is not one of this app's beacons: other software uses the network too.
PeerAnnouncement? decodeBeacon(List<int> bytes, String address) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) return null;
    if (decoded['app'] != _beaconApp || decoded['v'] != _beaconVersion) {
      return null;
    }
    final id = decoded['id'];
    final port = decoded['port'];
    final tag = decoded['tag'];
    if (id is! String || id.isEmpty || tag is! String) return null;
    if (port is! int || port < 1 || port > 65535) return null;
    final name = decoded['name'];
    return PeerAnnouncement(
      deviceId: id,
      name: name is String && name.trim().isNotEmpty ? name : 'Unnamed device',
      address: address,
      port: port,
      tag: tag,
    );
  } on FormatException {
    return null;
  }
}

/// Announces this device by UDP every few seconds, to a multicast group and
/// to the broadcast address, and listens for the same from others.
///
/// This reaches devices on the same network segment (the same Wi-Fi or
/// switch). Networks that block devices from seeing each other, as guest
/// Wi-Fi often does, will not work.
class UdpDiscovery implements Discovery {
  UdpDiscovery({this.interval = const Duration(seconds: 3)});

  final Duration interval;

  final _announcements = StreamController<PeerAnnouncement>.broadcast();
  RawDatagramSocket? _socket;
  Timer? _timer;
  List<int> _beacon = const [];
  bool _checking = false;

  /// This machine's addresses when the socket was opened; a change means it
  /// has moved to another network, or back onto the same one.
  String _addresses = '';

  @override
  Stream<PeerAnnouncement> get announcements => _announcements.stream;

  @override
  Future<void> start({
    required String deviceId,
    required String name,
    required int port,
    required String tag,
  }) async {
    await stop();
    _beacon = encodeBeacon(
      deviceId: deviceId,
      name: name,
      port: port,
      tag: tag,
    );
    // A failure here is the caller's to report; later ones are retried.
    await _open();
    _send();
    _timer = Timer.periodic(interval, (_) => _check());
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> _open() async {
    final addresses = await _localAddresses();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kDiscoveryPort,
      reuseAddress: true,
      // Lets a second copy share the port where the system supports it;
      // Windows does that with reuseAddress alone.
      reusePort: !Platform.isWindows,
    );
    socket.broadcastEnabled = true;
    await _joinGroup(socket);
    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final announcement = decodeBeacon(
          datagram.data,
          datagram.address.address,
        );
        if (announcement != null) _announcements.add(announcement);
      },
      // The system can take a socket away, as a phone does when it sleeps
      // or changes network. The next round opens another.
      onError: (Object _) => _drop(socket),
      onDone: () => _drop(socket),
    );
    _socket = socket;
    _addresses = addresses;
  }

  void _drop(RawDatagramSocket socket) {
    if (identical(_socket, socket)) _socket = null;
    socket.close();
  }

  /// Sends the beacon, first making sure there is a working socket on the
  /// network the machine is on now. Membership of the multicast group
  /// belongs to a network connection, so it is lost when Wi-Fi drops and
  /// comes back even though the socket itself survives; without rejoining,
  /// the device would announce itself and hear nobody.
  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final current = _socket;
      if (current != null && await _localAddresses() != _addresses) {
        _drop(current);
      }
      if (_timer == null) return;
      if (_socket == null) await _open();
      _send();
    } on SocketException {
      // No network for the moment; the next round tries again.
    } on OSError {
      // Same.
    } finally {
      _checking = false;
    }
  }

  Future<String> _localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final addresses = [
        for (final interface in interfaces)
          for (final address in interface.addresses)
            '${interface.name}/${address.address}',
      ]..sort();
      return addresses.join(',');
    } on SocketException {
      return '';
    }
  }

  Future<void> _joinGroup(RawDatagramSocket socket) async {
    final group = InternetAddress(kDiscoveryGroup);
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        try {
          socket.joinMulticast(group, interface);
        } on OSError {
          // An interface that cannot do multicast; broadcast still works.
        } on SocketException {
          // Same.
        }
      }
    } on SocketException catch (error) {
      debugPrint('Could not list network interfaces: $error');
    }
  }

  void _send() {
    final socket = _socket;
    if (socket == null) return;
    for (final target in const [kDiscoveryGroup, '255.255.255.255']) {
      try {
        socket.send(_beacon, InternetAddress(target), kDiscoveryPort);
      } on SocketException {
        // The network is down for the moment; the next round tries again.
      } on OSError {
        // Same.
      }
    }
  }
}

/// Plain TCP. Everything sent over it is encrypted one layer up, by
/// `SecureChannel`.
class TcpTransport implements PeerTransport {
  TcpTransport({
    this.connectTimeout = const Duration(seconds: 5),
    InternetAddress? bindAddress,
  }) : bindAddress = bindAddress ?? InternetAddress.anyIPv4;

  final Duration connectTimeout;

  /// Which of this machine's addresses to accept connections on; all of
  /// them unless told otherwise.
  final InternetAddress bindAddress;

  @override
  Future<PeerListener> listen() async {
    // Port 0: the system picks a free one, which the beacon then announces.
    final server = await ServerSocket.bind(bindAddress, 0);
    return _TcpListener(server);
  }

  @override
  Future<ByteConnection> connect(String address, int port) async {
    return _SocketConnection(
      await Socket.connect(address, port, timeout: connectTimeout),
    );
  }
}

class _TcpListener implements PeerListener {
  _TcpListener(this._server);

  final ServerSocket _server;

  @override
  int get port => _server.port;

  @override
  Stream<ByteConnection> get connections => _server.map(_SocketConnection.new);

  @override
  Future<void> close() => _server.close();
}

class _SocketConnection implements ByteConnection {
  _SocketConnection(this._socket) {
    _socket.setOption(SocketOption.tcpNoDelay, true);
    // A broken connection is reported through [incoming] ending; the write
    // side's error must not go unhandled as well.
    _socket.done.catchError((Object _) {});
  }

  final Socket _socket;
  bool _closed = false;

  @override
  Stream<List<int>> get incoming => _socket;

  @override
  void add(List<int> bytes) {
    if (_closed) return;
    try {
      _socket.add(bytes);
    } on StateError {
      // Closed underneath us; the reader will notice.
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
  }
}

/// The sync settings, sync key included, in one JSON file.
///
/// The key is stored as plain text: anyone who can read this user's files
/// can read it.
class JsonFileSyncSettingsStore implements SyncSettingsStore {
  JsonFileSyncSettingsStore(this.file);

  final File file;

  @override
  Future<SyncSettings?> load() async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      return SyncSettings.fromJson(decoded);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> save(SyncSettings settings) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await temporary.rename(file.path);
  }
}
