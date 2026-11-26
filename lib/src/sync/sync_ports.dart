/// What sync needs from the network and the disk, as interfaces, so the sync
/// logic can be tested with in-memory stand-ins. The real ones are in
/// `network.dart`.
library;

import 'dart:async';

import 'byte_connection.dart';

/// "A device with this id is listening at this address", heard on the local
/// network.
class PeerAnnouncement {
  const PeerAnnouncement({
    required this.deviceId,
    required this.name,
    required this.address,
    required this.port,
    required this.tag,
  });

  final String deviceId;

  /// What the device calls itself, for the list of devices nearby.
  final String name;
  final String address;
  final int port;

  /// Proof of holding a sync key, see `SyncKey.discoveryTag`; empty for a
  /// device that is not in a group yet.
  final String tag;

  @override
  String toString() => 'PeerAnnouncement($deviceId at $address:$port)';
}

/// Finds other devices on the local network, and lets them find this one.
abstract interface class Discovery {
  /// Announcements from other devices, repeated every few seconds for as
  /// long as they are around. May include this device's own.
  Stream<PeerAnnouncement> get announcements;

  /// Starts announcing this device and listening for others.
  Future<void> start({
    required String deviceId,
    required String name,
    required int port,
    required String tag,
  });

  Future<void> stop();
}

/// Accepts connections from other devices.
abstract interface class PeerListener {
  /// The port other devices connect to.
  int get port;

  Stream<ByteConnection> get connections;

  Future<void> close();
}

/// Makes and accepts connections between devices.
abstract interface class PeerTransport {
  Future<PeerListener> listen();

  Future<ByteConnection> connect(String address, int port);
}

/// What sync remembers between launches.
class SyncSettings {
  const SyncSettings({
    required this.deviceId,
    required this.deviceName,
    this.enabled = false,
    this.key,
    this.shareHistory = false,
    this.knownDevices = const [],
  });

  factory SyncSettings.fromJson(Map<String, Object?> json) {
    return SyncSettings(
      deviceId: json['deviceId']! as String,
      deviceName: json['deviceName']! as String,
      enabled: json['enabled'] as bool? ?? false,
      key: json['key'] as String?,
      shareHistory: json['shareHistory'] as bool? ?? false,
      knownDevices: [
        for (final id in json['knownDevices'] as List? ?? const [])
          id as String,
      ],
    );
  }

  /// Random, made once; tells devices apart.
  final String deviceId;

  /// What other devices show for this one.
  final String deviceName;

  final bool enabled;

  /// The sync key's 20 characters, or null when none has been set.
  final String? key;

  /// Whether a device that joins is sent the history already here.
  final bool shareHistory;

  /// The ids of the devices this one has synced with before, so a device
  /// connecting for the first time can be told apart.
  final List<String> knownDevices;

  SyncSettings copyWith({
    bool? enabled,
    String? Function()? key,
    bool? shareHistory,
    List<String>? knownDevices,
  }) {
    return SyncSettings(
      deviceId: deviceId,
      deviceName: deviceName,
      enabled: enabled ?? this.enabled,
      key: key == null ? this.key : key(),
      shareHistory: shareHistory ?? this.shareHistory,
      knownDevices: knownDevices ?? this.knownDevices,
    );
  }

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'enabled': enabled,
    'key': key,
    'shareHistory': shareHistory,
    'knownDevices': knownDevices,
  };
}

abstract interface class SyncSettingsStore {
  /// The saved settings, or null on a first launch or unreadable data.
  Future<SyncSettings?> load();

  Future<void> save(SyncSettings settings);
}

class MemorySyncSettingsStore implements SyncSettingsStore {
  MemorySyncSettingsStore([this.saved]);

  SyncSettings? saved;

  @override
  Future<SyncSettings?> load() async => saved;

  @override
  Future<void> save(SyncSettings settings) async => saved = settings;
}
